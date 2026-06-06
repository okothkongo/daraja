defmodule Daraja.TokenCacheTest do
  use ExUnit.Case, async: false

  alias Daraja.Client
  alias Daraja.HTTPClient.Mock
  alias Daraja.TokenCache

  # async: false is required because Daraja.HTTPClient.Mock is a shared global
  # Agent; tests would race on the response queue. The cache itself is isolated
  # per test via unique names.

  setup do
    Mock.reset()
    Application.put_env(:daraja, :http_client, Mock)

    on_exit(fn ->
      Application.delete_env(:daraja, :http_client)
    end)

    client = Client.new(consumer_key: "test_key", consumer_secret: "test_secret")
    {:ok, client: client}
  end

  test "returns cached token on second call without hitting network", %{client: client} do
    name = unique_name()
    start_supervised!({TokenCache, name: name})

    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-cached","expires_in":"3600"})})

    assert {:ok, "tok-cached"} = TokenCache.get_token(client, name)
    assert {:ok, "tok-cached"} = TokenCache.get_token(client, name)
    assert {:error, :no_response_queued} = Mock.request(:get, "", [], "")
  end

  test "fetches from network on cold miss", %{client: client} do
    name = unique_name()
    start_supervised!({TokenCache, name: name})

    Mock.push_response({:ok, 200, [], ~s({"access_token":"fresh-tok","expires_in":"3600"})})

    assert {:ok, "fresh-tok"} = TokenCache.get_token(client, name)
  end

  test "does not cache error responses", %{client: client} do
    name = unique_name()
    start_supervised!({TokenCache, name: name})

    Mock.push_response({:ok, 401, [], "Unauthorized"})
    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-after-error","expires_in":"3600"})})

    assert {:error, :auth_failed, _} = TokenCache.get_token(client, name)
    assert {:ok, "tok-after-error"} = TokenCache.get_token(client, name)
  end

  test "isolates tokens by client credentials", %{client: client} do
    name = unique_name()
    start_supervised!({TokenCache, name: name})

    client2 = Client.new(consumer_key: "other_key", consumer_secret: "other_secret")

    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-1","expires_in":"3600"})})
    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-2","expires_in":"3600"})})

    assert {:ok, "tok-1"} = TokenCache.get_token(client, name)
    assert {:ok, "tok-2"} = TokenCache.get_token(client2, name)

    assert {:ok, "tok-1"} = TokenCache.get_token(client, name)
    assert {:ok, "tok-2"} = TokenCache.get_token(client2, name)
  end

  test "proactively refreshes token before expiry", %{client: client} do
    name = unique_name()
    ttl = 2
    refresh_before = 1
    start_supervised!({TokenCache, name: name, ttl: ttl, refresh_before: refresh_before})

    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-initial","expires_in":"2"})})
    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-refreshed","expires_in":"2"})})

    assert {:ok, "tok-initial"} = TokenCache.get_token(client, name)

    Process.sleep((ttl - refresh_before) * 1_000 + 150)

    assert {:ok, "tok-refreshed"} = TokenCache.get_token(client, name)
  end

  test "respects custom server name", %{client: client} do
    name = unique_name()
    start_supervised!({TokenCache, name: name})

    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-custom","expires_in":"3600"})})

    assert {:ok, "tok-custom"} = TokenCache.get_token(client, name)
    assert {:ok, "tok-custom"} = TokenCache.get_token(client, name)
  end

  test "fetches fresh token when cached token is expired", %{client: client} do
    name = unique_name()
    ttl = 1
    start_supervised!({TokenCache, name: name, ttl: ttl, refresh_before: 0})

    Mock.push_response({:ok, 200, [], ~s({"access_token":"old-tok","expires_in":"1"})})
    Mock.push_response({:ok, 200, [], ~s({"access_token":"fresh","expires_in":"1"})})
    Mock.push_response({:ok, 200, [], ~s({"access_token":"fresh","expires_in":"1"})})

    assert {:ok, "old-tok"} = TokenCache.get_token(client, name)
    Process.sleep(ttl * 1_000 + 100)

    assert {:ok, "fresh"} = TokenCache.get_token(client, name)
  end

  test "fetches fresh token when consumer_secret rotates", %{client: client} do
    name = unique_name()
    start_supervised!({TokenCache, name: name})

    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-old","expires_in":"3600"})})
    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-new","expires_in":"3600"})})

    assert {:ok, "tok-old"} = TokenCache.get_token(client, name)

    rotated =
      Client.new(consumer_key: client.consumer_key, consumer_secret: "rotated_secret")

    assert {:ok, "tok-new"} = TokenCache.get_token(rotated, name)
  end

  test "invalidate/1 evicts cached token for client", %{client: client} do
    name = unique_name()
    start_supervised!({TokenCache, name: name})

    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok","expires_in":"3600"})})
    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-fresh","expires_in":"3600"})})

    assert {:ok, "tok"} = TokenCache.get_token(client, name)
    assert :ok = TokenCache.invalidate(client, name)
    assert {:ok, "tok-fresh"} = TokenCache.get_token(client, name)
  end

  test "rejects external ETS writes", %{client: client} do
    name = unique_name()
    start_supervised!({TokenCache, name: name})
    key = cache_key(client)

    assert_raise ArgumentError, fn ->
      :ets.insert(name, {key, {"evil", System.monotonic_time(:second) + 3600, 3600}})
    end
  end

  test "uses OAuth expires_in instead of configured ttl", %{client: client} do
    name = unique_name()
    start_supervised!({TokenCache, name: name, ttl: 3600, refresh_before: 0})

    Mock.push_response({:ok, 200, [], ~s({"access_token":"short-lived","expires_in":"1"})})
    Mock.push_response({:ok, 200, [], ~s({"access_token":"refetched","expires_in":"1"})})

    assert {:ok, "short-lived"} = TokenCache.get_token(client, name)
    Process.sleep(1_100)

    assert {:ok, "refetched"} = TokenCache.get_token(client, name)
  end

  test "falls back to configured ttl when expires_in is missing", %{client: client} do
    name = unique_name()
    ttl = 1
    start_supervised!({TokenCache, name: name, ttl: ttl, refresh_before: 0})

    Mock.push_response({:ok, 200, [], ~s({"access_token":"no-expiry"})})
    Mock.push_response({:ok, 200, [], ~s({"access_token":"refetched"})})

    assert {:ok, "no-expiry"} = TokenCache.get_token(client, name)
    Process.sleep(ttl * 1_000 + 100)

    assert {:ok, "refetched"} = TokenCache.get_token(client, name)
  end

  test "handles ETS ArgumentError during startup race", %{client: client} do
    name = unique_name()
    pid = start_supervised!({TokenCache, name: name})

    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok","expires_in":"3600"})})

    # Passing the PID instead of the atom makes :ets.lookup(pid, key) raise
    # ArgumentError (PID is not an ETS table name), exercising the rescue path.
    # GenServer.call still reaches the process via PID.
    assert {:ok, "tok"} = TokenCache.get_token(client, pid)
  end

  test "returns already-cached token when re-checked under GenServer lock", %{client: client} do
    name = unique_name()
    start_supervised!({TokenCache, name: name})

    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok","expires_in":"3600"})})

    assert {:ok, "tok"} = TokenCache.get_token(client, name)

    # Directly invoke handle_call, simulating a caller queued behind the first.
    # It re-checks under the lock, finds a valid token, and returns without fetching.
    assert {:ok, "tok"} = GenServer.call(name, {:fetch_and_cache, client})
    assert {:error, :no_response_queued} = Mock.request(:get, "", [], "")
  end

  test "cleans up token and timer when background refresh fails", %{client: client} do
    name = unique_name()
    start_supervised!({TokenCache, name: name})

    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok","expires_in":"3600"})})
    assert {:ok, "tok"} = TokenCache.get_token(client, name)

    key = cache_key(client)
    assert [{^key, _}] = :ets.lookup(name, key)

    Mock.push_response({:ok, 401, [], "Unauthorized"})
    send(GenServer.whereis(name), {:refresh, key})
    :sys.get_state(name)

    assert [] = :ets.lookup(name, key)
  end

  defp unique_name, do: :"test_cache_#{System.unique_integer([:positive])}"

  defp cache_key(%Client{} = client) do
    {client.consumer_key, client.environment, :crypto.hash(:sha256, client.consumer_secret)}
  end
end
