defmodule Daraja.HTTPClient.Finch do
  @moduledoc """
  Default HTTP client implementation using Finch.

  To use this adapter, start a Finch pool named `Daraja.Finch` in your
  application's supervision tree:

      children = [
        {Finch, name: Daraja.Finch}
      ]

  Then configure Daraja to use it (this is the default, so the config is optional):

      config :daraja, :http_client, Daraja.HTTPClient.Finch
  """

  @behaviour Daraja.HTTPClient

  @impl Daraja.HTTPClient
  def request(method, url, headers, body) do
    method
    |> Finch.build(url, headers, body)
    |> Finch.request(Daraja.Finch)
    |> case do
      {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
        {:ok, status, headers, body}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
