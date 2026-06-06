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

    Configure Daraja to use this adapter (this is the default, so the config is optional):

        config :daraja, :http_client, Daraja.HTTPClient.Finch

    ## TLS

    Requests use Finch's default SSL settings, which validate server certificates
    against the operating system's CA bundle. For certificate pinning or custom
    trust stores, implement `Daraja.HTTPClient` and configure `:http_client` to
    point at your adapter.
    """

    @behaviour Daraja.HTTPClient

    @impl Daraja.HTTPClient
    def request(method, url, headers, body) do
      pool = Application.get_env(:daraja, :finch_name, Daraja.Finch)

      unless Process.whereis(pool) do
        raise """
        Finch pool #{inspect(pool)} is not running. Add it to your supervision tree:

            children = [
              {Finch, name: #{inspect(pool)}}
            ]

        If you are using a custom pool name, set it in your config:

            config :daraja, :finch_name, #{inspect(pool)}
        """
      end

      method
      |> Finch.build(url, headers, body)
      |> Finch.request(pool)
      |> case do
        {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
          {:ok, status, headers, body}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
