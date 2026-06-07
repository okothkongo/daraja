defmodule Daraja.HTTPClient.Compliance do
  @moduledoc """
  Security checklist for custom `Daraja.HTTPClient` implementations.

  The behaviour defines only the `request/4` callback shape. When you provide
  your own adapter, ensure it meets these minimum requirements before using it
  with live M-PESA credentials:

    * **TLS** — Verify server certificates against a trusted CA store (or your
      pinned trust store). Never disable peer verification in production.
    * **Credential safety** — Do not log request or response bodies, headers
      such as `Authorization`, or STK `Password` fields.
    * **Timeouts** — Use bounded connect and receive timeouts so hung requests
      cannot accumulate indefinitely.
    * **Redirects** — Do not follow redirects to hosts outside Safaricom's
      documented API domains (`sandbox.safaricom.co.ke`, `api.safaricom.co.ke`).

  Use `checklist/0` in onboarding docs or CI smoke tests for custom clients.
  """

  @spec checklist() :: [String.t()]
  def checklist do
    [
      "TLS peer verification enabled",
      "No logging of Authorization headers or request/response bodies",
      "Bounded connect and receive timeouts configured",
      "Redirects restricted to Safaricom API hosts"
    ]
  end
end
