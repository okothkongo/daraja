defmodule Daraja.Config do
  @moduledoc """
  Reads Daraja configuration from the application environment.

  Configure in your application:

      config :daraja,
        consumer_key: "...",
        consumer_secret: "...",
        business_short_code: "174379",
        passkey: "bfb279...",
        callback_url: "https://example.com/callback",
        environment: :sandbox  # or :production
  """

  @sandbox_url "https://sandbox.safaricom.co.ke"
  @production_url "https://api.safaricom.co.ke"

  @spec base_url() :: String.t()
  def base_url do
    case get(:environment, :sandbox) do
      :production -> @production_url
      _ -> @sandbox_url
    end
  end

  @spec consumer_key() :: String.t()
  def consumer_key, do: get!(:consumer_key)

  @spec consumer_secret() :: String.t()
  def consumer_secret, do: get!(:consumer_secret)

  @spec business_short_code() :: String.t()
  def business_short_code, do: get!(:business_short_code)

  @spec passkey() :: String.t()
  def passkey, do: get!(:passkey)

  @spec callback_url() :: String.t()
  def callback_url, do: get!(:callback_url)

  @spec get!(atom()) :: term()
  def get!(key) do
    case Application.get_env(:daraja, key) do
      nil -> raise "Daraja config key #{inspect(key)} is required but not set"
      value -> value
    end
  end

  @spec get(atom(), term()) :: term()
  def get(key, default), do: Application.get_env(:daraja, key, default)
end
