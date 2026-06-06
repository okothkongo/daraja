defmodule Daraja.Callback.Guard do
  @moduledoc """
  Optional idempotency guard for inbound M-PESA callbacks.

  Safaricom may deliver the same callback more than once. Track seen transaction
  identifiers (`CheckoutRequestID`, `TransID`, `OriginatorConversationID`, etc.)
  before fulfilling orders or updating balances.

  Add to your supervision tree when you want in-memory deduplication:

      children = [
        {Daraja.Callback.Guard, []}
      ]

  Entries expire after `:ttl` seconds (default 86_400) so the table does not
  grow without bound.
  """

  use GenServer

  @default_ttl 86_400

  @doc """
  Records `id` if it has not been seen within the TTL window.

  Returns `:ok` on first sighting or `{:error, :duplicate}` when the same `id`
  was recorded recently.

  `server` defaults to `Daraja.Callback.Guard`. Pass a custom atom when running
  multiple named guards.
  """
  @spec ensure_fresh(term(), keyword()) :: :ok | {:error, :duplicate}
  def ensure_fresh(id, opts \\ []) when not is_nil(id) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:ensure_fresh, id})
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

  def start_link(opts \\ []) do
    opts = Keyword.take(opts, [:name, :ttl])
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    :ets.new(name, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, %{table: name, ttl: ttl}}
  end

  @impl GenServer
  def handle_call({:ensure_fresh, id}, _from, %{table: table, ttl: ttl} = state) do
    now = System.monotonic_time(:second)
    expires_at = now + ttl

    case :ets.lookup(table, id) do
      [{^id, stored_expires_at}] when stored_expires_at > now ->
        {:reply, {:error, :duplicate}, state}

      _ ->
        :ets.insert(table, {id, expires_at})
        {:reply, :ok, state}
    end
  end
end
