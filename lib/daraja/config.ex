defmodule Daraja.Config do
  @moduledoc false

  @spec get!(atom()) :: term()
  def get!(key) do
    case Application.get_env(:daraja, key) do
      nil -> raise "Daraja config key #{inspect(key)} is required but not set"
      value -> value
    end
  end

  @spec get(atom(), term()) :: term()
  def get(key, default), do: Application.get_env(:daraja, key, default)
end
