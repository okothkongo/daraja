defmodule Daraja.CallbackGuardTest do
  use ExUnit.Case, async: false

  alias Daraja.Callback.Guard

  setup do
    start_supervised!({Guard, name: :callback_guard_test, ttl: 60})
    :ok
  end

  test "ensure_fresh/2 accepts the first sighting of an id" do
    assert :ok = Guard.ensure_fresh("ws_CO_123", server: :callback_guard_test)
  end

  test "ensure_fresh/2 rejects duplicate ids within the ttl window" do
    assert :ok = Guard.ensure_fresh("ws_CO_456", server: :callback_guard_test)
    assert {:error, :duplicate} = Guard.ensure_fresh("ws_CO_456", server: :callback_guard_test)
  end

  test "ensure_fresh/2 accepts the same id after ttl expiry" do
    start_supervised!({Guard, name: :short_guard, ttl: 1})

    assert :ok = Guard.ensure_fresh("ws_CO_789", server: :short_guard)
    assert {:error, :duplicate} = Guard.ensure_fresh("ws_CO_789", server: :short_guard)

    Process.sleep(1_100)

    assert :ok = Guard.ensure_fresh("ws_CO_789", server: :short_guard)
  end
end
