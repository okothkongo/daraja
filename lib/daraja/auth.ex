defmodule Daraja.Auth do
  @moduledoc """
  Handles OAuth 2.0 authentication with the Daraja API.

  Each call to `fetch_token/1` performs a fresh `client_credentials` exchange
  against the Daraja Authorization API — there is no caching layer. Callers
  that need to amortise the round trip can wrap this function themselves.

  ## Usage

      client = Daraja.Client.new()
      {:ok, token} = Daraja.Auth.fetch_token(client)
  """

  alias Daraja.Client

  @auth_url "/oauth/v1/generate?grant_type=client_credentials"

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
