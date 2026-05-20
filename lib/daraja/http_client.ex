defmodule Daraja.HTTPClient do
  @moduledoc """
  Behaviour for making HTTP requests.

  Library users can implement this behaviour to provide a custom HTTP client,
  or rely on the default `Daraja.HTTPClient.Finch` implementation.

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
