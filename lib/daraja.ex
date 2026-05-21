defmodule Daraja do
  @moduledoc """
  Elixir client for the Safaricom Daraja API.

  ## M-Pesa Express (STK Push)

  Initiate a payment prompt on a customer's phone:

      Daraja.stk_push(%{
        amount: 100,
        phone_number: "254712345678",
        account_reference: "Order-001"
      })

  Configure credentials in your application config:

      config :daraja,
        consumer_key: "...",
        consumer_secret: "...",
        business_short_code: "174379",
        passkey: "bfb279...",
        callback_url: "https://example.com/callback",
        environment: :sandbox

  ## Custom HTTP Client

  Implement `Daraja.HTTPClient` and configure it:

      config :daraja, :http_client, MyApp.CustomHTTPClient
  """

  @doc false
  def http_client do
    Application.get_env(:daraja, :http_client, Daraja.HTTPClient.Finch)
  end

  @doc """
  Initiates an STK Push (M-Pesa Express) payment request.

  Required params: `amount`, `phone_number`, `account_reference`.
  Optional params: `transaction_desc`, `transaction_type`.
  """
  defdelegate stk_push(params), to: Daraja.Express
end
