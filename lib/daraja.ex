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

  ## Customer to Business (C2B)

  Register callback URLs for payment notifications:

      Daraja.register_url(%{
        short_code: "600984",
        response_type: "Completed",
        confirmation_url: "https://example.com/c2b/confirmation",
        validation_url: "https://example.com/c2b/validation"
      })

  Simulate a payment in the sandbox environment:

      Daraja.simulate(%{
        short_code: "600984",
        command_id: "CustomerPayBillOnline",
        amount: 100,
        msisdn: "254708374149",
        bill_ref_number: "INV-001"
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

  @doc """
  Registers C2B callback URLs for payment notifications.

  Required params: `short_code`, `response_type`, `confirmation_url`, `validation_url`.
  """
  defdelegate register_url(params), to: Daraja.C2B

  @doc """
  Simulates a C2B payment transaction. Sandbox only.

  Required params: `short_code`, `command_id`, `amount`, `msisdn`.
  Optional params: `bill_ref_number`.
  """
  defdelegate simulate(params), to: Daraja.C2B
end
