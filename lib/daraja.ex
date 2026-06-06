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

  Pass the initiator password and certificate as a tuple — `PaymentRequest.new/1`
  encrypts it internally (the tuple form is sugar over calling
  `Daraja.SecurityCredential.encrypt/2` yourself):

      Daraja.B2C.payment(client, %{
        originator_conversation_id: "my-unique-id-001",
        initiator_name: "testapi",
        security_credential: {"your-initiator-password", File.read!("sandbox-cert.cer")},
        command_id: "BusinessPayment",
        amount: 10,
        party_a: "600997",
        party_b: "254705912645",
        remarks: "Payout",
        queue_timeout_url: "https://example.com/b2c/timeout",
        result_url: "https://example.com/b2c/result",
        occasion: "Promo"
      })

  For production, pre-encrypt with `Daraja.SecurityCredential.encrypt/2` at
  deploy time and store only the resulting Base64 string so plaintext passwords
  never live in application state:

      {:ok, security_credential} =
        Daraja.SecurityCredential.encrypt(
          "your-initiator-password",
          File.read!("cert.cer")
        )

      Daraja.B2C.payment(client, %{security_credential: security_credential, ...})

  ## Business to Business (B2B)

  Same credential options as B2C — tuple for convenience, pre-encrypted string for
  production:

      Daraja.B2B.request(client, %{
        initiator: "testapi",
        security_credential: {"your-initiator-password", File.read!("sandbox-cert.cer")},
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

  ## Callback security

  Daraja does not sign inbound webhooks. Use `Daraja.Callback.Security` for IP
  allowlisting and shared-secret checks, `Daraja.Callback.Guard` for idempotency,
  and `parse/1` on the product callback modules before fulfilling orders.

  Default callback IP allowlists are community-documented Safaricom ranges—not
  fetched from the live Daraja API. Override them for production:

      config :daraja,
        callback_cidrs: ["196.201.212.0/24", "196.201.213.0/24", "196.201.214.0/24"],
        callback_hosts: ["196.201.214.200", "196.201.212.127"]

  ## Token Caching

  **Production deployments must start both Finch and `Daraja.Supervisor`.** Without
  the supervisor, every API call performs a separate OAuth round-trip (logged once
  as a warning when `:warn_uncached_token` is enabled, which is the default outside
  `:test`).

  Add both to your application's supervision tree:

      children = [
        {Finch, name: Daraja.Finch},
        {Daraja.Supervisor, []}
      ]

  In umbrella apps, start one supervisor per credential set with distinct names
  and point the library at the right cache via config:

      # supervision tree
      {Daraja.Supervisor, name: :billing_sup, cache_name: :billing_cache}

      # config/config.exs (or the umbrella child's config)
      config :daraja, token_cache: :billing_cache

  The `:token_cache` config value must be an atom. Omit it to use the default
  `Daraja.TokenCache`. See `Daraja.Auth.get_token/1` for details.

  ## HTTP timeouts and retries

  The default Finch adapter uses a 10 second receive timeout. Override in config:

      config :daraja, :http_receive_timeout, 10_000

  OAuth token fetches can opt into retry with exponential backoff (disabled by default):

      config :daraja, :http_retry,
        enabled: true,
        max_attempts: 3,
        base_ms: 100,
        max_ms: 2_000

  Payment POST calls are never retried automatically.

  ## Custom HTTP Client

  Implement `Daraja.HTTPClient` and configure it:

      config :daraja, :http_client, MyApp.CustomHTTPClient

  Custom adapters must verify TLS peers, avoid logging credentials or request
  bodies, use bounded timeouts, and not follow redirects to unintended hosts.
  See `Daraja.HTTPClient.Compliance` for a review checklist.
  """

  @doc false
  def http_client(ensure_loaded \\ &Code.ensure_loaded?/1) do
    cache = ensure_loaded == (&Code.ensure_loaded?/1)
    Daraja.Runtime.http_client_module(ensure_loaded, cache)
  end
end
