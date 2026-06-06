defmodule Daraja.SupervisorTest do
  use ExUnit.Case, async: false

  alias Daraja.Client
  alias Daraja.HTTPClient.Mock
  alias Daraja.TokenCache

  setup do
    Mock.reset()
    Application.put_env(:daraja, :http_client, Mock)

    on_exit(fn ->
      Application.delete_env(:daraja, :http_client)
    end)

    client = Client.new(consumer_key: "test_key", consumer_secret: "test_secret")
    {:ok, client: client}
  end

  test "starts TokenCache child under the given cache_name" do
    sup_name = unique_name()
    cache_name = unique_name()
    start_supervised!({Daraja.Supervisor, name: sup_name, cache_name: cache_name})

    assert is_pid(GenServer.whereis(cache_name))
  end

  test "supervised TokenCache serves tokens via cache_name", %{client: client} do
    sup_name = unique_name()
    cache_name = unique_name()
    start_supervised!({Daraja.Supervisor, name: sup_name, cache_name: cache_name})

    Mock.push_response({:ok, 200, [], ~s({"access_token":"sup-tok","expires_in":"3600"})})

    assert {:ok, "sup-tok"} = TokenCache.get_token(client, cache_name)
  end

  defp unique_name, do: :"test_sup_#{System.unique_integer([:positive])}"
end
