defmodule Daraja.Auth do
  @moduledoc false

  @spec fetch_token() ::
          {:ok, String.t()} | {:error, :auth_failed, term()} | {:error, :http_error, term()}
  def fetch_token do
    url = Daraja.Config.base_url() <> "/oauth/v1/generate?grant_type=client_credentials"

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
