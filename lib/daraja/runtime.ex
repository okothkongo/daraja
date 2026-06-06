defmodule Daraja.Runtime do
  @moduledoc false

  require Logger

  @http_client_key {:daraja, :http_client}
  @finch_pool_key {:daraja, :finch_pool}
  @finch_timeout_key {:daraja, :finch_receive_timeout}
  @token_cache_key {:daraja, :token_cache}
  @uncached_warning_key {:daraja, :uncached_token_warning}
  @tuple_credential_warning_key {:daraja, :tuple_security_credential_warning}

  @default_finch_pool Daraja.Finch
  @default_receive_timeout 10_000

  @doc false
  def register_token_cache(name) when is_atom(name) do
    :persistent_term.put(@token_cache_key, name)
  end

  @doc false
  def token_cache_name do
    case :persistent_term.get(@token_cache_key, :unset) do
      :unset -> Application.get_env(:daraja, :token_cache, Daraja.TokenCache)
      name -> name
    end
  end

  @doc false
  def warn_uncached_token_once do
    if uncached_token_warnings_enabled?() and
         :persistent_term.get(@uncached_warning_key, false) == false do
      :persistent_term.put(@uncached_warning_key, true)

      Logger.warning("""
      [Daraja] Token cache is not running — every API call fetches a new OAuth token.

      Add Daraja.Supervisor and a Finch pool to your supervision tree:

          children = [
            {Finch, name: Daraja.Finch},
            {Daraja.Supervisor, []}
          ]

      See https://hexdocs.pm/daraja/Daraja.html#module-token-caching
      """)
    end

    :ok
  end

  @doc false
  def http_client_module(ensure_loaded, cache \\ true) do
    configured = Application.get_env(:daraja, :http_client, Daraja.HTTPClient.Finch)

    if cache do
      case :persistent_term.get(@http_client_key, :unset) do
        {^configured, module} ->
          module

        _ ->
          module = resolve_http_client(configured, ensure_loaded)
          :persistent_term.put(@http_client_key, {configured, module})
          module
      end
    else
      resolve_http_client(configured, ensure_loaded)
    end
  end

  @doc false
  def finch_pool_name do
    configured = Application.get_env(:daraja, :finch_name, @default_finch_pool)

    case :persistent_term.get(@finch_pool_key, :unset) do
      {^configured, pool} ->
        pool

      _ ->
        :persistent_term.put(@finch_pool_key, {configured, configured})
        configured
    end
  end

  @doc false
  def finch_receive_timeout do
    configured = Application.get_env(:daraja, :http_receive_timeout, @default_receive_timeout)

    case :persistent_term.get(@finch_timeout_key, :unset) do
      {^configured, timeout} ->
        timeout

      _ ->
        :persistent_term.put(@finch_timeout_key, {configured, configured})
        configured
    end
  end

  @doc false
  def reset! do
    :persistent_term.erase(@http_client_key)
    :persistent_term.erase(@finch_pool_key)
    :persistent_term.erase(@finch_timeout_key)
    :persistent_term.erase(@token_cache_key)
    :persistent_term.erase(@uncached_warning_key)
    :persistent_term.erase(@tuple_credential_warning_key)
  end

  defp uncached_token_warnings_enabled? do
    Application.get_env(:daraja, :warn_uncached_token, Mix.env() != :test)
  end

  defp resolve_http_client(client, ensure_loaded) do
    cond do
      is_nil(client) ->
        raise "`:http_client` is configured as nil. Set it to a module that implements Daraja.HTTPClient."

      client == Daraja.HTTPClient.Finch and not ensure_loaded.(Finch) ->
        raise """
        Daraja.HTTPClient.Finch is not available. Add {:finch, "~> 0.18"} to \
        your application's dependencies, or configure a custom HTTP client:

            config :daraja, :http_client, MyApp.CustomHTTPClient
        """

      not ensure_loaded.(client) ->
        raise """
        HTTP client #{inspect(client)} is not available. \
        Check that the module name is spelled correctly and its containing \
        application is in your deps.
        """

      not function_exported?(client, :request, 4) ->
        raise """
        #{inspect(client)} does not implement the Daraja.HTTPClient behaviour \
        (missing request/4). \
        Ensure the module calls `@behaviour Daraja.HTTPClient`.
        """

      true ->
        client
    end
  end
end
