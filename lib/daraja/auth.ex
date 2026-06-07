defmodule Daraja.Auth do
  @moduledoc """
  Handles OAuth 2.0 authentication with the Daraja API.

  ## Cached vs uncached tokens

  Use `get_token/1` for the recommended entry point. It returns a cached token
  when `Daraja.TokenCache` is running, and falls back to a fresh network fetch
  otherwise:

      client = Daraja.Client.new()
      {:ok, token} = Daraja.Auth.get_token(client)

  Add `Daraja.Supervisor` to your application's supervision tree to enable
  caching:

      children = [
        {Daraja.Supervisor, []}
      ]

  `fetch_token/1` always hits the network and is unaffected by the cache.

  ## Umbrella apps / custom cache names

  `get_token/1` looks up the cache registered as `Daraja.TokenCache` by
  default. To use a cache started under a custom name, set the config key:

      config :daraja, token_cache: :billing_cache

  The `:token_cache` value must be an atom. Omit the key entirely to use the
  default `Daraja.TokenCache`.
  """

  alias Daraja.{APIError, Client}

  @auth_url "/oauth/v1/generate?grant_type=client_credentials"
  @default_ttl 3600

  @type token_info :: %{
          access_token: String.t(),
          expires_in: pos_integer()
        }

  @doc """
  Returns a cached access token when `Daraja.TokenCache` is running; otherwise
  fetches a fresh one from the network.

  The cache name is read from `Application.get_env(:daraja, :token_cache,
  Daraja.TokenCache)`. The config value must be an atom; omit the key to use
  the default `Daraja.TokenCache`.

  ## Returns

    * `{:ok, token}` — a valid access token string.
    * `{:error, :auth_failed, %Daraja.APIError{}}` — credentials were rejected or
      the response body could not be parsed.
    * `{:error, :http_error, reason}` — a network or transport-level failure.
  """
  @spec get_token(Client.t()) ::
          {:ok, String.t()} | {:error, :auth_failed, term()} | {:error, :http_error, term()}
  def get_token(%Client{} = client) do
    cache = Daraja.Runtime.token_cache_name()

    if Process.whereis(cache) do
      Daraja.TokenCache.get_token(client, cache)
    else
      Daraja.Runtime.warn_uncached_token_once()
      fetch_token(client)
    end
  end

  @doc false
  @spec invalidate_token(Client.t()) :: :ok
  def invalidate_token(%Client{} = client) do
    cache = Daraja.Runtime.token_cache_name()

    if Process.whereis(cache) do
      Daraja.TokenCache.invalidate(client, cache)
    end

    :ok
  end

  @doc false
  @spec with_token(Client.t(), (String.t() -> term())) :: term()
  def with_token(%Client{} = client, fun) when is_function(fun, 1) do
    with_token(client, fun, false)
  end

  defp with_token(client, fun, retried?) do
    case get_token(client) do
      {:ok, token} ->
        case fun.(token) do
          result ->
            cond do
              not retried? and token_auth_failure?(result) ->
                invalidate_token(client)
                with_token(client, fun, true)

              match?({:error, :request_failed, _}, result) and token_auth_failure?(result) ->
                {:error, :auth_failed, elem(result, 2)}

              true ->
                result
            end
        end

      error ->
        error
    end
  end

  defp token_auth_failure?({:error, :auth_failed, _}), do: true

  defp token_auth_failure?({:error, :request_failed, error}) do
    Daraja.HTTPResponse.invalid_access_token?(error)
  end

  defp token_auth_failure?(_), do: false

  @doc """
  Fetches a fresh access token for the given client.

  Encodes the client's Consumer Key and Consumer Secret as a Basic Auth
  credential and requests a `client_credentials` token from the Daraja
  Authorization API. Every call hits the network.

  ## Returns

    * `{:ok, token}` — a valid access token string.
    * `{:error, :auth_failed, %Daraja.APIError{}}` — the request completed but
      credentials were rejected or the response body could not be parsed.
    * `{:error, :http_error, reason}` — a network or transport-level failure.
  """
  @spec fetch_token(Client.t()) ::
          {:ok, String.t()} | {:error, :auth_failed, term()} | {:error, :http_error, term()}
  def fetch_token(%Client{} = client) do
    case fetch_token_info(client) do
      {:ok, %{access_token: token}} -> {:ok, token}
      error -> error
    end
  end

  @doc false
  @spec fetch_token_info(Client.t(), pos_integer()) ::
          {:ok, token_info()} | {:error, :auth_failed, term()} | {:error, :http_error, term()}
  def fetch_token_info(%Client{} = client, default_ttl \\ @default_ttl) do
    Daraja.HTTP.Retry.run(fn -> do_fetch_token_info(client, default_ttl) end)
  end

  defp do_fetch_token_info(%Client{} = client, default_ttl) do
    url = Client.base_url(client) <> @auth_url
    credentials = Base.encode64(client.consumer_key <> ":" <> client.consumer_secret)
    headers = [{"Authorization", "Basic " <> credentials}]

    case Daraja.http_client().request(:get, url, headers, "") do
      {:ok, 200, _headers, body} ->
        decode_body(body, default_ttl, 200)

      {:ok, status, _headers, body} ->
        {:error, :auth_failed, APIError.from_body(body, status: status)}

      {:error, reason} ->
        {:error, :http_error, reason}
    end
  end

  defp decode_body(body, default_ttl, status) do
    case JSON.decode(body) do
      {:ok, %{"access_token" => token} = map} ->
        {:ok, %{access_token: token, expires_in: parse_expires_in(map, default_ttl)}}

      _ ->
        {:error, :auth_failed, APIError.from_body(body, status: status)}
    end
  end

  defp parse_expires_in(%{"expires_in" => expires_in}, default_ttl) do
    coerce_expires_in(expires_in) || default_ttl
  end

  defp parse_expires_in(_map, default_ttl), do: default_ttl

  defp coerce_expires_in(expires_in) when is_integer(expires_in) and expires_in > 0,
    do: expires_in

  defp coerce_expires_in(expires_in) when is_binary(expires_in) do
    case Integer.parse(expires_in) do
      {value, ""} when value > 0 -> value
      _ -> nil
    end
  end

  defp coerce_expires_in(_), do: nil
end
