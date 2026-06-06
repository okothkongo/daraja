if Code.ensure_loaded?(Finch) do
  defmodule Daraja.HTTPClient.Finch do
    @moduledoc """
    Default HTTP client implementation using Finch.

    To use this adapter, start a Finch pool in your application's supervision tree.
    The pool name defaults to `Daraja.Finch` but can be overridden via config:

        # config/config.exs
        config :daraja, :finch_name, MyApp.Finch

    Start the pool under the configured name:

        children = [
          {Finch, name: MyApp.Finch}
        ]

    If the pool is not running, `request/4` returns
    `{:error, {:finch_pool_not_started, pool}}`.

    Configure Daraja to use this adapter (this is the default, so the config is optional):

        config :daraja, :http_client, Daraja.HTTPClient.Finch

    ## Timeouts

    Requests use `receive_timeout` from config (default `10_000` ms):

        config :daraja, :http_receive_timeout, 10_000

    ## TLS

    Requests use Finch's default SSL settings, which validate server certificates
    against the operating system's CA bundle. For certificate pinning or custom
    trust stores, implement `Daraja.HTTPClient` and configure `:http_client` to
    point at your adapter.
    """

    @behaviour Daraja.HTTPClient

    @impl Daraja.HTTPClient
    def request(method, url, headers, body) do
      pool = Daraja.Runtime.finch_pool_name()
      receive_timeout = Daraja.Runtime.finch_receive_timeout()

      if Process.whereis(pool) do
        do_request(method, url, headers, body, pool, receive_timeout)
      else
        {:error, {:finch_pool_not_started, pool}}
      end
    end

    defp do_request(method, url, headers, body, pool, receive_timeout) do
      method
      |> Finch.build(url, headers, body)
      |> Finch.request(pool, receive_timeout: receive_timeout)
      |> case do
        {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
          {:ok, status, headers, body}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
