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
  """

  @type status() :: 100..599
  @type headers() :: [{String.t(), String.t()}]
  @type body() :: binary()
  @type method() :: :get | :post | :put | :patch | :delete

  @callback request(method(), url :: String.t(), headers(), body()) ::
              {:ok, status(), headers(), body()} | {:error, term()}
end
