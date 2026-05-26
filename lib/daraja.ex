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

  ## Business to Customer (B2C)

  Encrypt your initiator password to build `SecurityCredential`:

      {:ok, security_credential} =
        Daraja.encrypt_b2c_credential(
          "your-initiator-password",
          File.read!("sandbox-cert.cer")
        )

  Initiate a B2C payout request:

      Daraja.b2c_payment(%{
        originator_conversation_id: "my-unique-id-001",
        initiator_name: "testapi",
        security_credential: security_credential,
        command_id: "BusinessPayment",
        amount: 10,
        party_a: "600997",
        party_b: "254705912645",
        remarks: "Payout",
        queue_timeout_url: "https://example.com/b2c/timeout",
        result_url: "https://example.com/b2c/result",
        occasion: "Promo"
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

  @doc """
  Initiates a B2C payout request.

  Required params: `originator_conversation_id`, `initiator_name`,
  `security_credential`, `command_id`, `amount`, `party_a`, `party_b`,
  `remarks`, `queue_timeout_url`, `result_url`.
  Optional params: `occasion`.
  """
  defdelegate b2c_payment(params), to: Daraja.B2C, as: :payment

  @doc """
  Encrypts plaintext initiator password into B2C `SecurityCredential`.
  """
  defdelegate encrypt_b2c_credential(password, cert_pem),
    to: Daraja.B2C.SecurityCredential,
    as: :encrypt
end
