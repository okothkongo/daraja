defmodule Daraja.Auth do
  @moduledoc """
  Handles OAuth 2.0 authentication with the Daraja API.

  Before making any Daraja API call, an access token must be obtained via
  `fetch_token/0`. Tokens are valid for 3600 seconds (1 hour).

  ## Prerequisites

  Configure your Consumer Key and Consumer Secret (retrieved from the Daraja
  portal) via `Daraja.Config`:

      config :daraja,
        consumer_key: "your_consumer_key",
        consumer_secret: "your_consumer_secret"
  """
  @auth_url "/oauth/v1/generate?grant_type=client_credentials"

  @doc """
  Fetches an OAuth 2.0 access token from the Daraja Authorization API.

  Encodes the configured Consumer Key and Consumer Secret as a Basic Auth
  credential, then requests a `client_credentials` token. The returned token
  must be included as a Bearer token in all subsequent Daraja API calls.

  Tokens expire after **3600 seconds** (1 hour).

  ## Returns

    * `{:ok, token}` — a valid access token string on success.
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
    url = Daraja.Config.base_url() <> @auth_url

    credentials =
      Base.encode64(Daraja.Config.consumer_key() <> ":" <> Daraja.Config.consumer_secret())

    headers = [{"Authorization", "Basic " <> credentials}]

    case Daraja.http_client().request(:get, url, headers, "") do
      {:ok, 200, _headers, body} ->
        case JSON.decode(body) do
          {:ok, %{"access_token" => token}} -> {:ok, token}
          _ -> {:error, :auth_failed, body}
        end

      {:ok, _status, _headers, body} ->
        {:error, :auth_failed, body}

      {:error, reason} ->
        {:error, :http_error, reason}
    end
  end
end
