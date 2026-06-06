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

  alias Daraja.Client

  @auth_url "/oauth/v1/generate?grant_type=client_credentials"

  @doc """
  Returns a cached access token when `Daraja.TokenCache` is running; otherwise
  fetches a fresh one from the network.

  The cache name is read from `Application.get_env(:daraja, :token_cache,
  Daraja.TokenCache)`. The config value must be an atom; omit the key to use
  the default `Daraja.TokenCache`.

  ## Returns

    * `{:ok, token}` — a valid access token string.
    * `{:error, :auth_failed, body}` — credentials were rejected or the
      response body could not be parsed.
    * `{:error, :http_error, reason}` — a network or transport-level failure.
  """
  @spec get_token(Client.t()) ::
          {:ok, String.t()} | {:error, :auth_failed, term()} | {:error, :http_error, term()}
  def get_token(%Client{} = client) do
    cache = Application.get_env(:daraja, :token_cache, Daraja.TokenCache)

    if Process.whereis(cache) do
      Daraja.TokenCache.get_token(client, cache)
    else
      fetch_token(client)
    end
  end

  @doc """
  Fetches a fresh access token for the given client.

  Encodes the client's Consumer Key and Consumer Secret as a Basic Auth
  credential and requests a `client_credentials` token from the Daraja
  Authorization API. Every call hits the network.

  ## Returns

    * `{:ok, token}` — a valid access token string.
    * `{:error, :auth_failed, body}` — the request completed but credentials
      were rejected or the response body could not be parsed.
    * `{:error, :http_error, reason}` — a network or transport-level failure.
  """
  @spec fetch_token(Client.t()) ::
          {:ok, String.t()} | {:error, :auth_failed, term()} | {:error, :http_error, term()}
  def fetch_token(%Client{} = client) do
    url = Client.base_url(client) <> @auth_url
    credentials = Base.encode64(client.consumer_key <> ":" <> client.consumer_secret)
    headers = [{"Authorization", "Basic " <> credentials}]

    case Daraja.http_client().request(:get, url, headers, "") do
      {:ok, 200, _headers, body} -> decode_body(body)
      {:ok, _status, _headers, body} -> {:error, :auth_failed, body}
      {:error, reason} -> {:error, :http_error, reason}
    end
  end

  defp decode_body(body) do
    case JSON.decode(body) do
      {:ok, %{"access_token" => token}} -> {:ok, token}
      _ -> {:error, :auth_failed, body}
    end
  end
end
