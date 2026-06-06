defmodule Daraja.Supervisor do
  @moduledoc """
  Optional supervisor that starts `Daraja.TokenCache`. Add it to your
  application's supervision tree to enable token caching across all API calls:

      children = [
        {Daraja.Supervisor, []}
      ]

  The library is process-free by default; caching is opt-in.

  ## Custom names (umbrella apps)

  Use `name:` to name the supervisor and `cache_name:` to name the cache
  process and its ETS table. They must be distinct atoms:

      {Daraja.Supervisor, name: :billing_sup, cache_name: :billing_cache}

  Then point `Daraja.Auth.get_token/1` at the custom cache via config:

      # config/config.exs (or the appropriate umbrella child config)
      config :daraja, token_cache: :billing_cache

  Each BEAM node can only register one ETS named table per atom. Starting two
  supervisors with the same `cache_name:` (or both using the default) will
  fail at startup.
  """

  use Supervisor

  def start_link(opts \\ []) do
    sup_name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: sup_name)
  end

  def init(opts) do
    cache_name = Keyword.get(opts, :cache_name, Daraja.TokenCache)
    children = [{Daraja.TokenCache, Keyword.put(opts, :name, cache_name)}]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
