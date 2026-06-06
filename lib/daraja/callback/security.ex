defmodule Daraja.Callback.Security do
  @moduledoc """
  Optional verification helpers for inbound M-PESA webhook requests.

  Safaricom Daraja callbacks are unsigned JSON POSTs. Authenticity must be
  enforced by the host application—typically via HTTPS, a shared secret embedded
  in the callback URL, IP allowlisting, idempotency on transaction IDs, and
  reconciliation against outbound API calls or Safaricom query/status APIs.

  This module does **not** prove a payment occurred; it only helps reject
  requests that clearly did not come through your expected transport controls.

  ## IP allowlist provenance

  The built-in defaults are **community-documented** Safaricom Kenya callback
  egress addresses widely cited in M-Pesa integrator guides and open-source
  packages. They are **not** fetched from the live Daraja API and may change
  without notice.

  Defaults combine:

    * CIDR subnets `196.201.212.0/24`, `196.201.213.0/24`, and
      `196.201.214.0/24` (Safaricom `196.201.x.x` address space)
    * An explicit host list matching commonly published production callback IPs

  Verify the current list with Safaricom support or your own production logs,
  then override via application config:

      config :daraja,
        callback_cidrs: ["196.201.214.0/24", "196.201.213.0/24", "196.201.212.0/24"],
        callback_hosts: ["196.201.214.200", "196.201.212.127"]

  Per-request overrides are also supported through `verify/1` and `safaricom_ip?/2`.

  IP allowlisting is intended for **production**. Sandbox callbacks (for example
  via ngrok) typically will not match these ranges—disable `check_ip` in dev.

  ## Example (Phoenix)

      with :ok <-
             Daraja.Callback.Security.verify(
               ip: conn.remote_ip,
               check_ip: true,
               shared_secret: Application.fetch_env!(:my_app, :mpesa_callback_secret),
               provided_secret: conn.params["token"]
             ),
           {:ok, callback} <- Daraja.Express.Callback.parse(payload),
           :ok <- Daraja.Callback.Guard.ensure_fresh(callback.checkout_request_id) do
        # ...fulfil order...
        json(conn, Daraja.Express.Callback.accept())
      else
        {:error, :untrusted_ip} -> send_resp(conn, 403, "Forbidden")
        {:error, :invalid_secret} -> send_resp(conn, 403, "Forbidden")
        {:error, :invalid_callback, _} -> send_resp(conn, 400, "Bad Request")
        {:error, :duplicate} -> json(conn, Daraja.Express.Callback.accept())
      end

  Register callback URLs with a secret query parameter, for example
  `https://example.com/mpesa/callback?token=your-secret`, and pass the same
  value to `provided_secret`.
  """

  import Bitwise

  @default_cidrs ["196.201.212.0/24", "196.201.213.0/24", "196.201.214.0/24"]

  @known_callback_hosts [
    "196.201.212.69",
    "196.201.212.74",
    "196.201.212.127",
    "196.201.212.128",
    "196.201.212.129",
    "196.201.212.132",
    "196.201.212.136",
    "196.201.212.138",
    "196.201.213.44",
    "196.201.213.114",
    "196.201.214.200",
    "196.201.214.206",
    "196.201.214.207",
    "196.201.214.208"
  ]

  @type verify_error :: :untrusted_ip | :invalid_secret | :invalid_ip
  @type allowlist :: %{cidrs: [String.t()], hosts: [String.t()]}

  @doc """
  Returns the configured callback CIDR allowlist.

  Reads `:callback_cidrs` from `config :daraja, ...` when set, otherwise
  `default_cidrs/0`.
  """
  @spec callback_cidrs() :: [String.t()]
  def callback_cidrs do
    Application.get_env(:daraja, :callback_cidrs, @default_cidrs)
  end

  @doc """
  Returns the configured explicit callback host allowlist.

  Reads `:callback_hosts` from `config :daraja, ...` when set, otherwise
  `known_callback_hosts/0`.
  """
  @spec callback_hosts() :: [String.t()]
  def callback_hosts do
    Application.get_env(:daraja, :callback_hosts, @known_callback_hosts)
  end

  @doc """
  Returns the active CIDR and host allowlists as a map.
  """
  @spec allowlist() :: allowlist()
  def allowlist do
    %{cidrs: callback_cidrs(), hosts: callback_hosts()}
  end

  @doc """
  Built-in CIDR defaults shipped with the library.
  """
  @spec default_cidrs() :: [String.t()]
  def default_cidrs, do: @default_cidrs

  @doc """
  Built-in explicit host defaults shipped with the library.

  These mirror commonly published Safaricom production callback IPs cited in
  integrator documentation. Prefer `callback_hosts/0` at runtime.
  """
  @spec known_callback_hosts() :: [String.t()]
  def known_callback_hosts, do: @known_callback_hosts

  @doc """
  Runs enabled verification checks. Skips any check whose inputs are omitted.

  Options:

    * `:ip` — client address as an IPv4/IPv6 tuple or string (e.g. `conn.remote_ip`)
    * `:check_ip` — when `true`, requires `:ip` to match `:cidrs` and/or `:hosts`
    * `:cidrs` — CIDR strings for this request; defaults to `callback_cidrs/0`
    * `:hosts` — explicit IPv4 strings for this request; defaults to `callback_hosts/0`
    * `:shared_secret` — expected secret (e.g. from app config)
    * `:provided_secret` — secret from the callback URL query/path

  Returns `:ok` or `{:error, reason}`.
  """
  @spec verify(keyword()) :: :ok | {:error, verify_error()}
  def verify(opts) when is_list(opts) do
    with :ok <- verify_ip(opts) do
      verify_shared_secret(opts)
    end
  end

  @doc """
  Returns `true` when `ip` matches the active allowlist.

  `ip` may be an IPv4 tuple, or a string parseable by `:inet.parse_address/1`.
  Only IPv4 matching is supported.

  When the second argument is a plain list of CIDR strings (no `cidr/host` keys),
  only those CIDRs are checked—useful in tests. Otherwise pass `[]` or a keyword
  list with optional `:cidrs` and `:hosts` overrides.
  """
  @spec safaricom_ip?(term(), keyword() | [String.t()]) :: boolean()
  def safaricom_ip?(ip, allowlist_override \\ [])

  def safaricom_ip?(ip, allowlist_override) do
    case normalize_ipv4(ip) do
      {:ok, quad} -> ip_allowed?(quad, resolve_allowlist(allowlist_override))
      :error -> false
    end
  end

  @doc """
  Constant-time comparison of callback URL secrets.

  Returns `true` when both values are binaries and equal. Returns `false` when
  either value is `nil`, not a binary, or they differ.
  """
  @spec shared_secret_valid?(term(), term()) :: boolean()
  def shared_secret_valid?(provided, expected)
      when is_binary(provided) and is_binary(expected) and byte_size(provided) > 0 and
             byte_size(expected) > 0 do
    byte_size(provided) == byte_size(expected) and :crypto.hash_equals(provided, expected)
  end

  def shared_secret_valid?(_, _), do: false

  defp verify_ip(opts) do
    if Keyword.get(opts, :check_ip, false) do
      ip = Keyword.get(opts, :ip)
      allowlist_override = Keyword.take(opts, [:cidrs, :hosts])

      case normalize_ipv4(ip) do
        {:ok, quad} ->
          if ip_allowed?(quad, resolve_allowlist(allowlist_override)),
            do: :ok,
            else: {:error, :untrusted_ip}

        :error ->
          {:error, :invalid_ip}
      end
    else
      :ok
    end
  end

  defp verify_shared_secret(opts) do
    expected = Keyword.get(opts, :shared_secret)
    provided = Keyword.get(opts, :provided_secret)

    cond do
      is_nil(expected) -> :ok
      shared_secret_valid?(provided, expected) -> :ok
      true -> {:error, :invalid_secret}
    end
  end

  defp resolve_allowlist(allowlist_override) do
    cond do
      keyword_allowlist?(allowlist_override) ->
        %{
          cidrs: Keyword.get(allowlist_override, :cidrs, callback_cidrs()),
          hosts: Keyword.get(allowlist_override, :hosts, callback_hosts())
        }

      match?([_ | _], allowlist_override) ->
        %{cidrs: allowlist_override, hosts: []}

      true ->
        allowlist()
    end
  end

  defp keyword_allowlist?(list) do
    case list do
      [{key, _} | _] when key in [:cidrs, :hosts] -> true
      _ -> false
    end
  end

  defp ip_allowed?(quad, %{cidrs: cidrs, hosts: hosts}) do
    ipv4_string = ipv4_to_string(quad)

    Enum.any?(cidrs, &ipv4_in_cidr?(quad, &1)) or ipv4_string in hosts
  end

  defp normalize_ipv4(ip) when is_tuple(ip) and tuple_size(ip) == 4, do: {:ok, ip}

  defp normalize_ipv4(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, quad} when is_tuple(quad) and tuple_size(quad) == 4 -> {:ok, quad}
      _ -> :error
    end
  end

  defp normalize_ipv4(_), do: :error

  defp ipv4_to_string({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp ipv4_in_cidr?(quad, cidr) when is_binary(cidr) do
    case String.split(cidr, "/") do
      [network, prefix_str] ->
        with {:ok, net_quad} <- parse_ipv4_network(network),
             {prefix, ""} <- Integer.parse(prefix_str),
             true <- prefix in 0..32 do
          mask = ipv4_mask(prefix)
          Bitwise.band(ipv4_to_int(quad), mask) == Bitwise.band(ipv4_to_int(net_quad), mask)
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp ipv4_in_cidr?(_, _), do: false

  defp parse_ipv4_network(network) do
    case :inet.parse_address(String.to_charlist(network)) do
      {:ok, quad} when is_tuple(quad) and tuple_size(quad) == 4 -> {:ok, quad}
      _ -> :error
    end
  end

  defp ipv4_to_int({a, b, c, d}), do: a <<< 24 ||| b <<< 16 ||| c <<< 8 ||| d

  defp ipv4_mask(0), do: 0
  defp ipv4_mask(prefix), do: Bitwise.band(-1 <<< (32 - prefix), 0xFFFFFFFF)
end
