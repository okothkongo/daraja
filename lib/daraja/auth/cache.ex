defmodule Daraja.Auth.Cache do
  @moduledoc false

  use GenServer

  @auth_url "/oauth/v1/generate?grant_type=client_credentials"
  # Refresh 60 s before the 3600 s Daraja expiry to avoid using a nearly-expired token.
  @token_ttl 3540

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def fetch_token do
    GenServer.call(__MODULE__, :fetch_token)
  end

  def reset_token do
    GenServer.call(__MODULE__, :reset_token)
  end

  @impl true
  def init(_), do: {:ok, %{token: nil, expires_at: 0}}

  @impl true
  def handle_call(:fetch_token, _from, state) do
    if token_valid?(state) do
      {:reply, {:ok, state.token}, state}
    else
      case do_fetch_token() do
        {:ok, token} ->
          expires_at = System.monotonic_time(:second) + @token_ttl
          {:reply, {:ok, token}, %{token: token, expires_at: expires_at}}

        error ->
          {:reply, error, state}
      end
    end
  end

  def handle_call(:reset_token, _from, _state) do
    {:reply, :ok, %{token: nil, expires_at: 0}}
  end

  defp token_valid?(%{token: nil}), do: false
  defp token_valid?(%{expires_at: expires_at}), do: System.monotonic_time(:second) < expires_at

  defp do_fetch_token do
    url = Daraja.Config.base_url() <> @auth_url

    credentials =
      Base.encode64(Daraja.Config.consumer_key() <> ":" <> Daraja.Config.consumer_secret())

    headers = [{"Authorization", "Basic " <> credentials}]

    case Daraja.http_client().request(:get, url, headers, "") do
      {:ok, 200, _headers, body} ->
        decode_body(body)

      {:ok, _status, _headers, body} ->
        {:error, :auth_failed, body}

      {:error, reason} ->
        {:error, :http_error, reason}
    end
  end

  defp decode_body(body) do
    case JSON.decode(body) do
      {:ok, %{"access_token" => token}} -> {:ok, token}
      _ -> {:error, :auth_failed, body}
    end
  end
end
