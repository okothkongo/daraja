# Daraja

[![Elixir CI](https://github.com/okothkongo/daraja/actions/workflows/ci.yml/badge.svg)](https://github.com/okothkongo/daraja/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

Elixir client for the [Safaricom Daraja API](https://developer.safaricom.co.ke).

Daraja is a programmatic API client for M-Pesa — not an IEx helper library. Every
call takes a `Daraja.Client` as its first argument, returns typed `{:ok, _}` /
`{:error, reason, _}` tuples, and works against both sandbox and production
environments. Build a client once, reuse it across Express, C2B, B2B, and B2C
endpoints.

## Features

- Clean API separated per Daraja product: `Daraja.Express`, `Daraja.C2B`, `Daraja.B2B`, `Daraja.B2C`
- `Daraja.Client` as the first argument to every call (multi-tenant friendly)
- Typed request/response structs with `{:ok, _}` / `{:error, reason, _}` tuples
- OAuth token caching via `Daraja.Supervisor` and `Daraja.TokenCache`
- Built-in security credential encryption (`Daraja.SecurityCredential`)
- Callback parsers for STK Push, C2B, B2B, and B2C webhooks
- Optional callback verification (`Daraja.Callback.Security`) and idempotency (`Daraja.Callback.Guard`)
- Pluggable HTTP client (`Daraja.HTTPClient`; Finch default)

## Usage

Start a console with `iex -S mix`, configure your credentials (see
[Configuration](#configuration)), then:

### Client

```elixir
iex> client = Daraja.Client.new()
%Daraja.Client{environment: :sandbox, ...}

iex> client = Daraja.Client.new(
...>   consumer_key: merchant.consumer_key,
...>   consumer_secret: merchant.consumer_secret
...> )
%Daraja.Client{...}
```

### M-Pesa Express (STK Push)

Initiate a payment prompt on a customer's phone:

```elixir
iex> Daraja.Express.request(client, %{
...>   amount: 100,
...>   phone_number: "254712345678",
...>   account_reference: "Order-001",
...>   transaction_desc: "Payment"
...> })
{:ok, %Daraja.Express.Response.Success{...}}
```

The client must carry `business_short_code`, `passkey`, and `callback_url`
(via `Daraja.Client.new/1` options or application config).

### Customer to Business (C2B)

Register callback URLs for payment notifications:

```elixir
iex> Daraja.C2B.register_url(client, %{
...>   short_code: "600984",
...>   response_type: "Completed",
...>   confirmation_url: "https://example.com/c2b/confirmation",
...>   validation_url: "https://example.com/c2b/validation"
...> })
{:ok, %Daraja.C2B.Response.Success{...}}
```

Simulate a payment in the sandbox environment:

```elixir
iex> Daraja.C2B.simulate(client, %{
...>   short_code: "600984",
...>   command_id: "CustomerPayBillOnline",
...>   amount: 100,
...>   msisdn: "254708374149",
...>   bill_ref_number: "INV-001"
...> })
{:ok, %Daraja.C2B.Response.Success{...}}
```

### Business to Customer (B2C)

Pass the initiator password and certificate as a tuple — the library encrypts it
internally (sugar over `Daraja.SecurityCredential.encrypt/2`):

```elixir
iex> Daraja.B2C.payment(client, %{
...>   originator_conversation_id: "my-unique-id-001",
...>   initiator_name: "testapi",
...>   security_credential: {"your-initiator-password", File.read!("sandbox-cert.cer")},
...>   command_id: "BusinessPayment",
...>   amount: 10,
...>   party_a: "600997",
...>   party_b: "254705912645",
...>   remarks: "Payout",
...>   queue_timeout_url: "https://example.com/b2c/timeout",
...>   result_url: "https://example.com/b2c/result",
...>   occasion: "Promo"
...> })
{:ok, %Daraja.B2C.Response.Success{...}}
```

For production, pre-encrypt at deploy time and store only the Base64 string:

```elixir
iex> {:ok, security_credential} =
...>   Daraja.SecurityCredential.encrypt(
...>     "your-initiator-password",
...>     File.read!("cert.cer")
...>   )

iex> Daraja.B2C.payment(client, %{security_credential: security_credential, ...})
```

### Business to Business (B2B)

Same credential options as B2C — tuple for convenience, pre-encrypted string
for production:

```elixir
iex> Daraja.B2B.request(client, %{
...>   initiator: "testapi",
...>   security_credential: {"your-initiator-password", File.read!("sandbox-cert.cer")},
...>   command_id: "BusinessPayBill",
...>   sender_identifier_type: 4,
...>   receiver_identifier_type: 4,
...>   amount: 10_500,
...>   party_a: "600992",
...>   party_b: "600000",
...>   account_reference: "INV-001",
...>   remarks: "B2B Payment",
...>   queue_timeout_url: "https://example.com/b2b/timeout",
...>   result_url: "https://example.com/b2b/result"
...> })
{:ok, %Daraja.B2B.Response.Success{...}}
```

### Callbacks

Safaricom Daraja callbacks are **unsigned** JSON POSTs. Verify each request
before treating parsed output as proof of payment. Register HTTPS callback URLs
with a secret query parameter (for example `?token=...`), allowlist Safaricom
IP ranges, deduplicate on transaction IDs, and reconcile against your outbound
API calls when possible.

`Daraja.Callback.Security` ships community-documented Safaricom callback CIDRs
and explicit host defaults. They are **not** fetched from the live Daraja API—
verify against Safaricom support or your production logs, then override:

```elixir
config :daraja,
  callback_cidrs: ["196.201.212.0/24", "196.201.213.0/24", "196.201.214.0/24"],
  callback_hosts: ["196.201.214.200", "196.201.212.127"]
```

Disable `check_ip: true` in sandbox/dev (ngrok and local tunnels will not match
production Safaricom ranges).

Start an optional idempotency guard:

```elixir
children = [
  {Daraja.Callback.Guard, []}
]
```

Parse and verify inbound webhook payloads:

```elixir
callback_secret = Application.fetch_env!(:my_app, :mpesa_callback_secret)
payload = conn.body_params

with :ok <-
       Daraja.Callback.Security.verify(
         ip: conn.remote_ip,
         check_ip: true,
         shared_secret: callback_secret,
         provided_secret: conn.params["token"]
       ),
     {:ok, callback} <- Daraja.Express.Callback.parse(payload),
     :ok <- Daraja.Callback.Guard.ensure_fresh(callback.checkout_request_id) do
  # fulfil order, persist receipt, etc.
  json(conn, Daraja.Express.Callback.accept())
else
  {:error, :untrusted_ip} -> send_resp(conn, 403, "Forbidden")
  {:error, :invalid_secret} -> send_resp(conn, 403, "Forbidden")
  {:error, :invalid_callback, _} -> send_resp(conn, 400, "Bad Request")
  {:error, :duplicate} -> json(conn, Daraja.Express.Callback.accept())
end
```

C2B validation example:

```elixir
with :ok <- Daraja.Callback.Security.verify(ip: conn.remote_ip, check_ip: true, ...),
     {:ok, callback} <- Daraja.C2B.Callback.parse_validation(payload),
     :ok <- Daraja.Callback.Guard.ensure_fresh(callback.trans_id) do
  response =
    if valid_account?(callback.bill_ref_number) do
      Daraja.C2B.Callback.accept()
    else
      Daraja.C2B.Callback.reject("C2B00012")
    end

  json(conn, response)
end
```

See `Daraja.Callback.Security`, `Daraja.Callback.Guard`,
`Daraja.Express.Callback`, `Daraja.C2B.Callback`, `Daraja.B2B.Callback`,
and `Daraja.B2C.Callback` for full details.

## Installation

Add `:daraja` and `:finch` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:daraja, "~> 0.1.0"}
   #You replace this with client of your choice
    {:finch, "~> 0.23"}
  ]
end
```


`:finch` is optional in Daraja's own `mix.exs` but required for the default
HTTP adapter. CI tests the Finch adapter against **0.23** (minimum) and the
latest release matching `~> 0.23` so Mint/TLS stack changes are caught early.
Use `{:finch, "~> 0.23"}` in your app unless you provide a custom
`Daraja.HTTPClient`.

Start a Finch pool and optionally enable token caching in your application's
supervision tree:

```elixir
children = [
  {Finch, name: Daraja.Finch},
  {Daraja.Supervisor, []}  # optional — enables OAuth token caching
]
```

The pool name defaults to `Daraja.Finch`. To use an existing Finch pool under a
different name, set the `:finch_name` config key and start the pool under that name:

```elixir
# config/config.exs
config :daraja, :finch_name, MyApp.Finch
```

```elixir
children = [
  {Finch, name: MyApp.Finch}
]
```

Run `mix deps.get` to install.

## Configuration

Configure default credentials in your application config. Obtain keys from the
[Safaricom Daraja developer portal](https://developer.safaricom.co.ke):

```elixir
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
```

`consumer_key` and `consumer_secret` are always required. `business_short_code`,
`passkey`, and `callback_url` are needed for STK Push. The `b2b_*` and `b2c_*`
keys are optional defaults for `Daraja.B2B.request/2` and `Daraja.B2C.payment/2`;
per-call params always take precedence.

## Advanced topics

### Security credentials

B2B and B2C require an encrypted initiator password. Safaricom provides a
certificate via the developer portal. For sandbox and local development, pass
`{password, certificate}` as a tuple and the library encrypts it for you. For
production, call `Daraja.SecurityCredential.encrypt/2` at deploy time and store
only the resulting Base64 string so plaintext passwords never live in application
state.

### Token caching

By default every API call fetches a fresh OAuth token. Add `Daraja.Supervisor`
to your supervision tree (see [Installation](#installation)) to enable ETS-backed
caching — subsequent calls reuse the token until it expires.

In umbrella apps, start one supervisor per credential set with distinct names
and point the library at the right cache via config:

```elixir
# supervision tree
{Daraja.Supervisor, name: :billing_sup, cache_name: :billing_cache}

# config/config.exs
config :daraja, token_cache: :billing_cache
```

### Custom HTTP client

Implement the `Daraja.HTTPClient` behaviour and configure it:

```elixir
config :daraja, :http_client, MyApp.CustomHTTPClient
```

**Note:** If you configure a custom HTTP client, you can remove `{:finch, "~> 0.23"}`
from your `mix.exs` and drop the Finch pool from your supervision tree. Finch is an
optional dependency; leaving the default `Daraja.HTTPClient.Finch` configured while
omitting Finch from deps will raise at runtime with a clear message.

The default Finch adapter validates Safaricom HTTPS endpoints using your OS trust
store. It does not pin certificates. For pinning or a private CA, supply a custom
`Daraja.HTTPClient` with the TLS options your deployment requires.

### Error handling

`:auth_failed` and gateway `:http_error` outcomes return a `%Daraja.APIError{}`
struct (parsed `error_code` / `error_message` when Safaricom sends JSON; otherwise
a short summary without the raw body). Business-level API rejections on HTTP 200/400
still return product-specific `%Response.Error{}` structs. Avoid logging full error
terms at `:info` or above in production — log `error_code` and `error_message` fields
instead.

### Request validation

Payment request structs validate `amount` as a positive integer, Kenyan MSISDNs as
`254XXXXXXXXX`, and (for STK Push) `account_reference` length and `transaction_type`.
Override the MSISDN pattern when needed:

```elixir
config :daraja, :msisdn_regex, ~r/^254\d{9}$/
```

## Documentation

- **Module docs:** run `mix docs` and open `doc/index.html`
- **In IEx:** `h Daraja`, `h Daraja.Express`, etc.
- **Online (after Hex publish):** [https://hexdocs.pm/daraja](https://hexdocs.pm/daraja)

## Development

```
$ mix test
$ mix lint      # compile, format check, credo
$ mix dialyzer
```

## FAQ

### Sandbox vs production?

Set `:environment` in your application config or pass it to `Daraja.Client.new/1`.
The default is `:sandbox`, which targets `https://sandbox.safaricom.co.ke`.
Use `:production` for `https://api.safaricom.co.ke`.

### Can I use this for multiple merchants?

Yes. Pass per-merchant credentials to `Daraja.Client.new/1` — options override
values from the application environment on every call.

## Copyright & License

Copyright (c) Okoth Kongo & Amos Kibet

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
