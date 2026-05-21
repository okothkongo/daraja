defmodule Daraja.Auth do
  @moduledoc """
  Handles OAuth 2.0 authentication with the Daraja API.

  The access token is automatically cached and reused until it nears expiry,
  at which point a new one is fetched transparently. Caching is managed
  internally by a supervised `GenServer`.

  Before making any Daraja API call, an access token must be obtained via
  `fetch_token/0`.

  ## Prerequisites

  Configure your Consumer Key and Consumer Secret (retrieved from the Daraja
  portal) via `Daraja.Config`:

      config :daraja,
        consumer_key: "your_consumer_key",
        consumer_secret: "your_consumer_secret"
  """

  @doc """
  Returns a valid access token, fetching a new one only when the cache is empty
  or the token has expired.

  On the first call (or after expiry) the function encodes the configured
  Consumer Key and Consumer Secret as a Basic Auth credential and requests a
  `client_credentials` token from the Daraja Authorization API. Subsequent
  calls within the token's lifetime return the cached token immediately without
  making an HTTP request.

  Tokens returned by the API are valid for 3600 seconds; this module refreshes
  60 seconds early to avoid serving a nearly-expired token.

  ## Returns

    * `{:ok, token}` — a valid access token string.
    * `{:error, :auth_failed, body}` — the request completed but credentials
      were rejected or the response body could not be parsed (e.g. wrong
      Consumer Key/Secret, invalid grant type).
    * `{:error, :http_error, reason}` — a network or transport-level failure.

  ## Examples

      iex> Daraja.Auth.fetch_token()
      {:ok, "c9SQxWWhmdVRlyh0zh8gZDTkubVF"}

      iex> Daraja.Auth.fetch_token()
      {:error, :auth_failed, ~s({"errorCode":"400.008.01","errorMessage":"Invalid authentication type"})}

  """
  @spec fetch_token() ::
          {:ok, String.t()} | {:error, :auth_failed, term()} | {:error, :http_error, term()}
  def fetch_token do
    Daraja.Auth.Cache.fetch_token()
  end

  @doc """
  Clears the cached token, forcing the next `fetch_token/0` call to fetch a
  fresh one from the Daraja Authorization API.

  Intended for use in tests to ensure each test starts with a cold cache.
  """
  @spec reset_token() :: :ok
  def reset_token do
    Daraja.Auth.Cache.reset_token()
  end
end
