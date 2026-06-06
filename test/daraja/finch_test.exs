defmodule Daraja.HTTPClient.FinchTest do
  use ExUnit.Case, async: false

  alias Daraja.HTTPClient.Finch, as: FinchClient
  alias Daraja.HTTPClient.Mock

  setup_all do
    start_supervised!({Finch, name: Daraja.Finch})
    :ok
  end

  test "request/4 returns the status, headers and body on success" do
    port = one_shot("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nx-test: yes\r\n\r\nhi")

    assert {:ok, 200, headers, "hi"} =
             FinchClient.request(:get, "http://127.0.0.1:#{port}/", [], "")

    assert {"x-test", "yes"} in headers
  end

  test "request/4 returns an error tuple when the connection fails" do
    port = free_port()

    assert {:error, _reason} =
             FinchClient.request(:get, "http://127.0.0.1:#{port}/", [], "")
  end

  test "Mock.request/4 returns :no_response_queued when the queue is empty" do
    Mock.reset()
    assert {:error, :no_response_queued} = Mock.request(:get, "http://example.com", [], "")
  end

  test "request/4 returns an error when the configured Finch pool is not running" do
    Application.put_env(:daraja, :finch_name, Daraja.FinchMissing)
    on_exit(fn -> Application.delete_env(:daraja, :finch_name) end)

    assert {:error, {:finch_pool_not_started, Daraja.FinchMissing}} =
             FinchClient.request(:get, "http://127.0.0.1/", [], "")
  end

  test "request/4 uses a custom :finch_name pool" do
    Application.put_env(:daraja, :finch_name, Daraja.FinchCustom)
    on_exit(fn -> Application.delete_env(:daraja, :finch_name) end)
    start_supervised!({Finch, name: Daraja.FinchCustom})

    port = one_shot("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi")

    assert {:ok, 200, _headers, "hi"} =
             FinchClient.request(:get, "http://127.0.0.1:#{port}/", [], "")
  end

  # Starts a one-shot TCP server that accepts a single connection, reads the
  # request, writes back `response`, and shuts down. Returns the bound port.
  defp one_shot(response) do
    {:ok, lsock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(lsock)

    spawn(fn ->
      {:ok, sock} = :gen_tcp.accept(lsock)
      _ = :gen_tcp.recv(sock, 0, 1000)
      :gen_tcp.send(sock, response)
      :gen_tcp.close(sock)
      :gen_tcp.close(lsock)
    end)

    port
  end

  # Binds a port and immediately releases it, so connecting to it is refused.
  defp free_port do
    {:ok, lsock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(lsock)
    :gen_tcp.close(lsock)
    port
  end
end
