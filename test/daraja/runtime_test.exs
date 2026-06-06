defmodule Daraja.RuntimeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Daraja.Client
  alias Daraja.HTTPClient.Mock
  alias Daraja.Runtime

  setup do
    Mock.reset()
    Application.put_env(:daraja, :http_client, Mock)
    Application.put_env(:daraja, :warn_uncached_token, true)
    Runtime.reset!()

    on_exit(fn ->
      Application.delete_env(:daraja, :http_client)
      Application.delete_env(:daraja, :warn_uncached_token)
      Runtime.reset!()
    end)

    {:ok, client: Client.new(consumer_key: "k", consumer_secret: "s")}
  end

  test "warns once when token cache is not running", %{client: client} do
    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok","expires_in":"3600"})})
    Mock.push_response({:ok, 200, [], ~s({"access_token":"tok2","expires_in":"3600"})})

    log =
      capture_log(fn ->
        assert {:ok, "tok"} = Daraja.Auth.get_token(client)
        assert {:ok, "tok2"} = Daraja.Auth.get_token(client)
      end)

    assert log =~ "Token cache is not running"
    assert length(:binary.matches(log, "Token cache is not running")) == 1
  end

  test "caches resolved http client module" do
    Application.put_env(:daraja, :http_client, Mock)

    first = Daraja.http_client()
    second = Daraja.http_client()

    assert first == Mock
    assert second == Mock
    assert :persistent_term.get({:daraja, :http_client}) == {Mock, Mock}
  end
end
