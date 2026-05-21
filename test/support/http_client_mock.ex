defmodule Daraja.HTTPClient.Mock do
  @moduledoc false
  @behaviour Daraja.HTTPClient

  @doc "Enqueue a canned response to be returned by the next `request/4` call."
  def push_response(response) do
    queue = Process.get(:mock_http_queue, [])
    Process.put(:mock_http_queue, queue ++ [response])
  end

  @impl Daraja.HTTPClient
  def request(_method, _url, _headers, _body) do
    case Process.get(:mock_http_queue, []) do
      [] ->
        {:error, :no_response_queued}

      [head | tail] ->
        Process.put(:mock_http_queue, tail)
        head
    end
  end
end
