defmodule Daraja do
  @moduledoc """
  Elixir client for the Safaricom Daraja API.

  All API calls take a `Daraja.Client` as their first argument. Build a client
  once and reuse it; per-request options on `Daraja.Client.new/1` override
  values read from the application environment, which is handy for multi-tenant
  callers.

      client = Daraja.Client.new()

  ## M-Pesa Express (STK Push)

  Initiate a payment prompt on a customer's phone:

      Daraja.Express.request(client, %{
        amount: 100,
        phone_number: "254712345678",
        account_reference: "Order-001"
      })

  ## Customer to Business (C2B)

  Register callback URLs for payment notifications:

      Daraja.C2B.register_url(client, %{
        short_code: "600984",
        response_type: "Completed",
        confirmation_url: "https://example.com/c2b/confirmation",
        validation_url: "https://example.com/c2b/validation"
      })

  Simulate a payment in the sandbox environment:

      Daraja.C2B.simulate(client, %{
        short_code: "600984",
        command_id: "CustomerPayBillOnline",
        amount: 100,
        msisdn: "254708374149",
        bill_ref_number: "INV-001"
      })

  ## Business to Customer (B2C)

  Encrypt your initiator password to build a `SecurityCredential`:

      {:ok, security_credential} =
        Daraja.B2C.SecurityCredential.encrypt(
          "your-initiator-password",
          File.read!("sandbox-cert.cer")
        )

  Initiate a B2C payout request:

      Daraja.B2C.payment(client, %{
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

  ## Business to Business (B2B)

  Build a security credential (same utility used by B2C):

      {:ok, security_credential} =
        Daraja.B2C.SecurityCredential.encrypt(
          "your-initiator-password",
          File.read!("sandbox-cert.cer")
        )

  Initiate a B2B transfer request:

      Daraja.B2B.request(client, %{
        initiator: "testapi",
        security_credential: security_credential,
        command_id: "BusinessPayBill",
        sender_identifier_type: 4,
        receiver_identifier_type: 4,
        amount: 10_500,
        party_a: "600992",
        party_b: "600000",
        account_reference: "INV-001",
        remarks: "B2B Payment",
        queue_timeout_url: "https://example.com/b2b/timeout",
        result_url: "https://example.com/b2b/result"
      })

  ## Configuration

  Configure default credentials in your application config:

      config :daraja,
        consumer_key: "...",
        consumer_secret: "...",
        business_short_code: "174379",
        passkey: "bfb279...",
        callback_url: "https://example.com/callback",
        environment: :sandbox,
        b2b_initiator: "testapi",
        b2b_security_credential: "base64-credential",
        b2b_queue_timeout_url: "https://example.com/b2b/timeout",
        b2b_result_url: "https://example.com/b2b/result",
        b2c_initiator_name: "testapi",
        b2c_security_credential: "base64-credential",
        b2c_queue_timeout_url: "https://example.com/b2c/timeout",
        b2c_result_url: "https://example.com/b2c/result"

  The `b2b_*` and `b2c_*` keys are optional defaults for `Daraja.B2B.request/2`
  and `Daraja.B2C.payment/2`. Per-call params always take precedence over env
  values, which is handy for multi-tenant callers that need to override
  defaults per request.

  Per-call overrides for multi-tenant callers:

      client =
        Daraja.Client.new(
          consumer_key: merchant.consumer_key,
          consumer_secret: merchant.consumer_secret
        )

  ## Custom HTTP Client

  Implement `Daraja.HTTPClient` and configure it:

      config :daraja, :http_client, MyApp.CustomHTTPClient
  """

  @doc false
  def http_client do
    Application.get_env(:daraja, :http_client, Daraja.HTTPClient.Finch)
  end
end
