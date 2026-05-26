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
end
