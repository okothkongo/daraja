defmodule Daraja.AuthTest do
  use ExUnit.Case, async: false

  alias Daraja.HTTPClient.Mock

  setup do
    Daraja.Auth.reset_token()
    Mock.reset()

    Application.put_env(:daraja, :http_client, Mock)
    Application.put_env(:daraja, :consumer_key, "test_key")
    Application.put_env(:daraja, :consumer_secret, "test_secret")
    Application.put_env(:daraja, :environment, :sandbox)

    on_exit(fn ->
      Application.delete_env(:daraja, :http_client)
      Application.delete_env(:daraja, :consumer_key)
      Application.delete_env(:daraja, :consumer_secret)
      Application.delete_env(:daraja, :environment)
    end)
  end

  test "returns token on successful 200 response" do
    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok123","expires_in":"3600"})})
    assert {:ok, "tok123"} = Daraja.Auth.fetch_token()
  end

  test "returns auth_failed on non-200 response" do
    Mock.push_response({:ok, 401, [], "Unauthorized"})
    assert {:error, :auth_failed, "Unauthorized"} = Daraja.Auth.fetch_token()
  end

  test "returns auth_failed when JSON is missing access_token" do
    Mock.push_response({:ok, 200, [], ~s({"foo":"bar"})})
    assert {:error, :auth_failed, _} = Daraja.Auth.fetch_token()
  end

  test "returns http_error on transport failure" do
    Mock.push_response({:error, :timeout})
    assert {:error, :http_error, :timeout} = Daraja.Auth.fetch_token()
  end
end
