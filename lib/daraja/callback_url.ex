defmodule Daraja.CallbackURL do
  @moduledoc """
  Validates callback URLs before they are registered with Safaricom.

  Safaricom's servers call these URLs on payment events. Rejecting unsafe values
  at the library boundary reduces server-side callback SSRF risk when URLs come
  from multi-tenant input or compromised credentials.

  ## Configuration

      config :daraja,
        environment: :production,
        validate_callback_urls: true,
        allowed_callback_hosts: ["myapp.com", "api.myapp.com"]

  * `:validate_callback_urls` — when `false`, validation is skipped in
    `:sandbox` only. Production always validates.
  * `:allowed_callback_hosts` — when set, the URL host must match an entry
    exactly or be a subdomain of one. Omit to allow any public hostname.

  ## Rules

  * Production requires `https://`. Sandbox also allows `http://`.
  * Literal private, loopback, link-local, and metadata addresses are rejected.
  * Known metadata hostnames (for example `metadata.google.internal`) are rejected.
  """

  @blocked_hostnames ~w(localhost metadata metadata.google.internal)

  @spec validate(String.t(), keyword()) :: :ok | {:error, String.t()}
  def validate(url, opts \\ []) when is_binary(url) do
    environment = Keyword.get(opts, :environment, Daraja.Config.get(:environment, :sandbox))

    if skip_validation?(environment) do
      :ok
    else
      do_validate(url, environment)
    end
  end

  @spec validate_all(map(), [atom()], keyword()) ::
          :ok | {:error, [{atom(), String.t()}]}
  def validate_all(params, fields, opts \\ []) when is_map(params) and is_list(fields) do
    errors =
      Enum.flat_map(fields, fn field ->
        case Map.get(params, field) do
          url when is_binary(url) ->
            case validate(url, opts) do
              :ok -> []
              {:error, message} -> [{field, message}]
            end

          _ ->
            []
        end
      end)

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp skip_validation?(environment) do
    environment == :sandbox and Daraja.Config.get(:validate_callback_urls, true) == false
  end

  defp do_validate(url, environment) do
    uri = URI.parse(url)

    with :ok <- require_url_parts(uri),
         :ok <- validate_scheme(uri.scheme, environment),
         :ok <- validate_host(uri.host) do
      validate_allowlist(uri.host)
    end
  end

  defp require_url_parts(%URI{scheme: scheme, host: host})
       when scheme in ["http", "https"] and is_binary(host) and host != "" do
    :ok
  end

  defp require_url_parts(_uri), do: {:error, "must be a valid http or https URL with a host"}

  defp validate_scheme(scheme, environment) do
    allowed =
      case environment do
        :production -> ["https"]
        _ -> ["https", "http"]
      end

    if scheme in allowed do
      :ok
    else
      {:error, "must use https in production"}
    end
  end

  defp validate_host(host) do
    normalized = String.downcase(host)

    cond do
      normalized in @blocked_hostnames ->
        {:error, "host is not allowed"}

      String.ends_with?(normalized, ".localhost") ->
        {:error, "host is not allowed"}

      ip_blocked?(host) ->
        {:error, "host must not be a private or metadata address"}

      true ->
        :ok
    end
  end

  defp validate_allowlist(host) do
    case Daraja.Config.get(:allowed_callback_hosts, nil) do
      hosts when is_list(hosts) and hosts != [] ->
        if host_allowed?(host, hosts) do
          :ok
        else
          {:error, "host is not in the allowed callback hosts list"}
        end

      _ ->
        :ok
    end
  end

  defp host_allowed?(host, hosts) do
    normalized = String.downcase(host)

    Enum.any?(hosts, fn allowed ->
      allowed = String.downcase(allowed)
      normalized == allowed or String.ends_with?(normalized, "." <> allowed)
    end)
  end

  defp ip_blocked?(host) do
    host
    |> normalize_ip_host()
    |> parse_ip()
    |> case do
      {:ipv4, address} -> ipv4_private?(address)
      {:ipv6, address} -> ipv6_blocked?(address)
      :not_ip -> false
    end
  end

  defp normalize_ip_host("[" <> rest), do: String.trim_trailing(rest, "]")
  defp normalize_ip_host(host), do: host

  defp parse_ip(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, {a, b, c, d}} ->
        {:ipv4, {a, b, c, d}}

      {:ok, {0, 0, 0, 0, 0, 65535, a, b}} ->
        {:ipv4, {a, b, 0, 0}}

      {:ok, ip} when tuple_size(ip) == 8 ->
        {:ipv6, ip}

      _ ->
        :not_ip
    end
  end

  defp ipv4_private?({10, _, _, _}), do: true
  defp ipv4_private?({127, _, _, _}), do: true
  defp ipv4_private?({169, 254, _, _}), do: true
  defp ipv4_private?({172, second, _, _}) when second in 16..31, do: true
  defp ipv4_private?({192, 168, _, _}), do: true
  defp ipv4_private?({0, _, _, _}), do: true
  defp ipv4_private?(_), do: false

  defp ipv6_blocked?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp ipv6_blocked?({0, 0, 0, 0, 0, 65535, a, b}), do: ipv4_private?({a, b, 0, 0})
  defp ipv6_blocked?({second, _, _, _, _, _, _, _}) when second in 0xFE80..0xFEBF, do: true
  defp ipv6_blocked?(_), do: false
end
