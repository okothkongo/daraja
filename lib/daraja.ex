defmodule Daraja do
  @moduledoc """
  Documentation for `Daraja`.
  """

  @doc false
  def http_client do
    Application.get_env(:daraja, :http_client, Daraja.HTTPClient.Finch)
  end
end
