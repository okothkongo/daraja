defmodule Daraja.HTTPClient do
  @moduledoc """
  Behaviour for making HTTP requests.

  Library users can implement this behaviour to provide a custom HTTP client,
  or rely on the default `Daraja.HTTPClient.Finch` implementation.

  The default implementation is `Daraja.HTTPClient.Finch`, which requires
  `{:finch, "~> 0.18"}` in your `mix.exs` and a Finch pool (default name
  `Daraja.Finch`) started in your supervision tree. If you configure a custom
  client, both requirements can be dropped.

  Configure the adapter in your application:

      config :daraja, :http_client, MyApp.CustomHTTPClient

  ## TLS

  The default Finch adapter verifies Safaricom endpoints using the host OS
  trust store (standard CA validation). Certificate pinning is not built in;
  use a custom `Daraja.HTTPClient` implementation when your deployment requires
  pinned certificates or other TLS hardening.

  ## Custom client security

  This behaviour specifies only the `request/4` return shape. Custom
  implementations must verify TLS peers, avoid logging credentials or full
  request bodies (especially STK `Password` fields), use bounded timeouts, and
  not follow redirects to unintended hosts. See `Daraja.HTTPClient.Compliance`
  for a checklist you can use when reviewing or testing custom adapters.
  """

  @type status() :: 100..599
  @type headers() :: [{String.t(), String.t()}]
  @type body() :: binary()
  @type method() :: :get | :post | :put | :patch | :delete

  @callback request(method(), url :: String.t(), headers(), body()) ::
              {:ok, status(), headers(), body()} | {:error, term()}
end
