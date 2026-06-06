defmodule Daraja.HTTPClientConfigTest do
  use ExUnit.Case, async: false

  setup do
    on_exit(fn -> Application.delete_env(:daraja, :http_client) end)
  end

  test "raises when Finch adapter is default but Finch is not available" do
    Application.delete_env(:daraja, :http_client)

    assert_raise RuntimeError, ~r/Finch is not available/, fn ->
      Daraja.http_client(fn
        Finch -> false
        mod -> Code.ensure_loaded?(mod)
      end)
    end
  end

  test "raises when :http_client is configured as nil" do
    Application.put_env(:daraja, :http_client, nil)

    assert_raise RuntimeError, ~r/configured as nil/, fn ->
      Daraja.http_client()
    end
  end

  test "raises when :http_client module does not exist" do
    Application.put_env(:daraja, :http_client, Daraja.NonExistent.Client)

    assert_raise RuntimeError, ~r/not available/, fn ->
      Daraja.http_client()
    end
  end

  test "raises when :http_client module exists but does not implement request/4" do
    Application.put_env(:daraja, :http_client, String)

    assert_raise RuntimeError, ~r/does not implement/, fn ->
      Daraja.http_client()
    end
  end

  test "returns the configured module when it implements request/4" do
    Application.put_env(:daraja, :http_client, Daraja.HTTPClient.Mock)

    assert Daraja.http_client() == Daraja.HTTPClient.Mock
  end
end
