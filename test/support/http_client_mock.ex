defmodule Daraja.HTTPClient.Mock do
  @moduledoc false
  @behaviour Daraja.HTTPClient

  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  @doc "Enqueue a canned response to be returned by the next `request/4` call."
  def push_response(response) do
    Agent.update(__MODULE__, &(&1 ++ [response]))
  end

  @doc "Clear all queued responses."
  def reset do
    Agent.update(__MODULE__, fn _ -> [] end)
  end

  @impl Daraja.HTTPClient
  def request(_method, _url, _headers, _body) do
    Agent.get_and_update(__MODULE__, fn
      [] -> {{:error, :no_response_queued}, []}
      [head | tail] -> {head, tail}
    end)
  end
end
