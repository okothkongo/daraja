defmodule Daraja.AuthTest do
  use ExUnit.Case, async: false

  alias Daraja.Client
  alias Daraja.HTTPClient.Mock

  setup do
    Mock.reset()

    Application.put_env(:daraja, :http_client, Mock)

    on_exit(fn ->
      Application.delete_env(:daraja, :http_client)
    end)

    client = Client.new(consumer_key: "test_key", consumer_secret: "test_secret")
    {:ok, client: client}
  end

  test "returns token on successful 200 response", %{client: client} do
    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok123","expires_in":"3600"})})
    assert {:ok, "tok123"} = Daraja.Auth.fetch_token(client)
  end

  test "returns auth_failed on non-200 response", %{client: client} do
    Mock.push_response({:ok, 401, [], "Unauthorized"})
    assert {:error, :auth_failed, "Unauthorized"} = Daraja.Auth.fetch_token(client)
  end

  test "returns auth_failed when JSON is missing access_token", %{client: client} do
    Mock.push_response({:ok, 200, [], ~s({"foo":"bar"})})
    assert {:error, :auth_failed, _} = Daraja.Auth.fetch_token(client)
  end

  test "returns http_error on transport failure", %{client: client} do
    Mock.push_response({:error, :timeout})
    assert {:error, :http_error, :timeout} = Daraja.Auth.fetch_token(client)
  end

  test "fetches a fresh token on every call (no caching)", %{client: client} do
    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-1","expires_in":"3600"})})
    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-2","expires_in":"3600"})})

    assert {:ok, "tok-1"} = Daraja.Auth.fetch_token(client)
    assert {:ok, "tok-2"} = Daraja.Auth.fetch_token(client)
  end

  test "get_token/1 hits the network when no cache is running", %{client: client} do
    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-no-cache","expires_in":"3600"})})

    assert {:ok, "tok-no-cache"} = Daraja.Auth.get_token(client)
  end

  describe "get_token/1 with default-named cache" do
    setup do
      start_supervised!(Daraja.TokenCache)
      :ok
    end

    test "serves second call from cache without hitting network", %{client: client} do
      Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-default","expires_in":"3600"})})

      assert {:ok, "tok-default"} = Daraja.Auth.get_token(client)
      assert {:ok, "tok-default"} = Daraja.Auth.get_token(client)
      assert {:error, :no_response_queued} = Mock.request(:get, "", [], "")
    end
  end

  describe "get_token/1 with config-named cache" do
    setup do
      Application.put_env(:daraja, :token_cache, :auth_test_cache)
      start_supervised!({Daraja.TokenCache, name: :auth_test_cache})
      on_exit(fn -> Application.delete_env(:daraja, :token_cache) end)
      :ok
    end

    test "routes through custom-named cache via application config", %{client: client} do
      Mock.push_response({:ok, 200, [], ~s({"access_token":"tok-config","expires_in":"3600"})})

      assert {:ok, "tok-config"} = Daraja.Auth.get_token(client)
      assert {:ok, "tok-config"} = Daraja.Auth.get_token(client)
      assert {:error, :no_response_queued} = Mock.request(:get, "", [], "")
    end
  end
end
