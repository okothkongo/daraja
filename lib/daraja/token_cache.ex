defmodule Daraja.TokenCache do
  @moduledoc """
  ETS-backed GenServer that caches Daraja access tokens to eliminate the
  network round-trip on every API call.

  Add `Daraja.Supervisor` to your application's supervision tree to opt in:

      children = [
        {Daraja.Supervisor, []}
      ]

  The library is process-free by default; caching is opt-in.

  ## Cache key

  Tokens are keyed by `{consumer_key, environment, secret_hash}` where
  `secret_hash` is a SHA-256 digest of `consumer_secret`. Rotating the secret
  while keeping the same consumer key produces a cache miss and fetches a fresh
  token. Call `invalidate/1` after rotation to evict any orphaned entry keyed
  under the previous secret.

  ## TTL and refresh

  Token lifetime comes from Safaricom's OAuth `expires_in` field. `:ttl`
  (default 3600 s) is used only when `expires_in` is absent or unparseable.
  `:refresh_before` (default 120 s) controls how many seconds before expiry
  the cache proactively fetches a fresh token in the background.

  `refresh_before` should be less than the configured `:ttl` fallback and the
  effective token lifetime. When `expires_in` is shorter than `refresh_before`,
  refresh is scheduled immediately. `init/1` raises when `refresh_before >= ttl`.

  ## Concurrent fetches

  OAuth network I/O runs in `Task.Supervisor` workers — not inside the
  GenServer mailbox — so cache misses for different credentials fetch in
  parallel. Concurrent misses for the **same** key share one in-flight task.

  ## Crash and restart

  ETS tables are owned by the GenServer process. On crash and supervisor
  restart, the old table is gone and a fresh one is created — all cached tokens
  are lost and the next request per client pays a cold network fetch.

  ## ETS access

  The cache table is `:protected`: any process may read (lock-free happy path
  in `get_token/2`), but only the owning GenServer may insert or delete. This
  prevents local cache poisoning by unrelated processes while preserving read
  concurrency.

  ## Credential retention

  Client credentials are held in the GenServer's `clients` map (keyed like the
  token cache) so proactive refresh timers carry only the cache key—not a full
  `%Daraja.Client{}`—in delayed messages.
  """

  use GenServer

  alias Daraja.Client

  @default_ttl 3600
  @default_refresh_before 120
  @default_task_supervisor Daraja.TokenCache.TaskSupervisor
  @refresh_retry_delay_ms 30_000

  @doc """
  Evicts the cached token for `client`, canceling any scheduled refresh.

  Use after credential rotation to drop a stale entry obtained with the
  previous secret. With the updated cache key, a rotated secret already
  misses the cache; `invalidate/1` cleans up the orphaned entry and timer.

  `server` defaults to `Daraja.TokenCache`.
  """
  @spec invalidate(Client.t(), atom()) :: :ok
  def invalidate(%Client{} = client, server \\ __MODULE__) do
    GenServer.call(server, {:invalidate, client})
  end

  @doc """
  Returns a cached access token for `client`, fetching from the network on a
  miss.

  Reads directly from ETS on the happy path (lock-free). Falls back to a
  `GenServer.call` on a miss or when the ETS table doesn't exist yet (brief
  startup race between supervisor start and `init/1` completing).

  `server` defaults to `Daraja.TokenCache`. Pass a custom atom when using a
  non-default cache name configured via `cache_name:` in `Daraja.Supervisor`.
  """
  @spec get_token(Client.t(), atom()) ::
          {:ok, String.t()} | {:error, :auth_failed, term()} | {:error, :http_error, term()}
  def get_token(%Client{} = client, server \\ __MODULE__) do
    key = cache_key(client)

    try do
      case lookup_valid_token(server, key) do
        {:ok, token} ->
          {:ok, token}

        :miss ->
          GenServer.call(server, {:fetch_and_cache, client})
      end
    rescue
      # ETS raises ArgumentError for a missing named table — expected during
      # the startup race before init/1 has created the table.
      ArgumentError ->
        GenServer.call(server, {:fetch_and_cache, client})
    end
  end

  @doc false
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link(opts) do
    opts = Keyword.take(opts, [:name, :ttl, :refresh_before, :task_supervisor])
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    refresh_before = Keyword.get(opts, :refresh_before, @default_refresh_before)
    task_supervisor = Keyword.get(opts, :task_supervisor, @default_task_supervisor)

    if refresh_before >= ttl do
      raise ArgumentError,
            "invalid TokenCache config: refresh_before (#{refresh_before}) must be less than ttl (#{ttl})"
    end

    :ets.new(name, [:set, :protected, :named_table, read_concurrency: true])
    Daraja.Runtime.register_token_cache(name)

    {:ok,
     %{
       table: name,
       ttl: ttl,
       refresh_before: refresh_before,
       timers: %{},
       clients: %{},
       in_flight: %{},
       task_supervisor: task_supervisor
     }}
  end

  @impl GenServer
  def handle_call({:invalidate, client}, _from, state) do
    {:reply, :ok, evict(state, cache_key(client))}
  end

  @impl GenServer
  def handle_call({:fetch_and_cache, client}, from, state) do
    key = cache_key(client)

    case lookup_valid_token(state.table, key) do
      {:ok, token} ->
        {:reply, {:ok, token}, state}

      :miss ->
        state = store_client(state, key, client)

        case Map.get(state.in_flight, key) do
          {task_ref, waiters, :fetch} ->
            {:noreply, put_in_flight(state, key, task_ref, [from | waiters], :fetch)}

          nil ->
            {state, task_ref} = start_fetch_task(state, key, client)
            {:noreply, put_in_flight(state, key, task_ref, [from], :fetch)}
        end
    end
  end

  @impl GenServer
  def handle_info({ref, result}, state) when is_reference(ref) do
    case pop_in_flight_by_ref(state, ref) do
      {nil, state} ->
        {:noreply, state}

      {{key, waiters, kind}, state} ->
        {replies, state} = apply_fetch_result(state, key, result, waiters, kind)
        Enum.each(replies, fn {from, reply} -> GenServer.reply(from, reply) end)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case pop_in_flight_by_ref(state, ref) do
      {nil, state} ->
        {:noreply, state}

      {{_key, [], _kind}, state} ->
        {:noreply, state}

      {{key, waiters, :fetch}, state} ->
        error = {:error, :http_error, :fetch_crashed}
        Enum.each(waiters, &GenServer.reply(&1, error))
        {:noreply, drop_in_flight(state, key)}

      {{key, _waiters, :refresh}, state} ->
        {:noreply, schedule_refresh_retry(state, key)}
    end
  end

  @impl GenServer
  def handle_info({:refresh, key}, state) do
    case Map.fetch(state.clients, key) do
      {:ok, client} ->
        if Map.has_key?(state.in_flight, key) do
          {:noreply, schedule_refresh_retry(state, key)}
        else
          {state, task_ref} = start_fetch_task(state, key, client)
          {:noreply, put_in_flight(state, key, task_ref, [], :refresh)}
        end

      :error ->
        {:noreply, state}
    end
  end

  defp lookup_valid_token(table, key) do
    case :ets.lookup(table, key) do
      [{^key, {token, expires_at, _ttl}}] ->
        if expires_at > System.monotonic_time(:second) do
          {:ok, token}
        else
          :miss
        end

      _ ->
        :miss
    end
  end

  defp start_fetch_task(state, _key, client) do
    ttl = state.ttl
    task_supervisor = state.task_supervisor

    task =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        Daraja.Auth.fetch_token_info(client, ttl)
      end)

    {state, task.ref}
  end

  defp put_in_flight(state, key, task_ref, waiters, kind) do
    %{state | in_flight: Map.put(state.in_flight, key, {task_ref, waiters, kind})}
  end

  defp pop_in_flight_by_ref(state, ref) do
    case Enum.find(state.in_flight, fn {_key, {task_ref, _waiters, _kind}} -> task_ref == ref end) do
      {key, {^ref, waiters, kind}} ->
        {{key, waiters, kind}, drop_in_flight(state, key)}

      nil ->
        {nil, state}
    end
  end

  defp drop_in_flight(state, key) do
    %{state | in_flight: Map.delete(state.in_flight, key)}
  end

  defp apply_fetch_result(state, key, result, waiters, kind) do
    case result do
      {:ok, %{access_token: token, expires_in: ttl}} ->
        expires_at = System.monotonic_time(:second) + ttl
        :ets.insert(state.table, {key, {token, expires_at, ttl}})

        state =
          state
          |> schedule_refresh(key, ttl)
          |> drop_in_flight(key)

        replies =
          if kind == :fetch, do: Enum.map(waiters, &{&1, {:ok, token}}), else: []

        {replies, state}

      error ->
        state =
          case kind do
            :refresh -> schedule_refresh_retry(state, key)
            :fetch -> drop_in_flight(state, key)
          end

        replies = if kind == :fetch, do: Enum.map(waiters, &{&1, error}), else: []
        {replies, state}
    end
  end

  defp schedule_refresh_retry(state, key) do
    existing = Map.get(state.timers, key)
    if existing, do: Process.cancel_timer(existing)

    ref = Process.send_after(self(), {:refresh, key}, @refresh_retry_delay_ms)
    %{state | timers: Map.put(state.timers, key, ref)}
  end

  defp evict(state, key) do
    existing = Map.get(state.timers, key)
    if existing, do: Process.cancel_timer(existing)

    :ets.delete(state.table, key)

    %{
      state
      | timers: Map.delete(state.timers, key),
        clients: Map.delete(state.clients, key),
        in_flight: Map.delete(state.in_flight, key)
    }
  end

  defp store_client(state, key, client) do
    %{state | clients: Map.put(state.clients, key, client)}
  end

  defp schedule_refresh(state, key, ttl) do
    existing = Map.get(state.timers, key)
    if existing, do: Process.cancel_timer(existing)

    delay = max(0, ttl - state.refresh_before) * 1_000
    ref = Process.send_after(self(), {:refresh, key}, delay)
    %{state | timers: Map.put(state.timers, key, ref)}
  end

  defp cache_key(%Client{} = client) do
    {client.consumer_key, client.environment, secret_hash(client.consumer_secret)}
  end

  defp secret_hash(secret) do
    :crypto.hash(:sha256, secret)
  end
end
