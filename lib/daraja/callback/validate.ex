defmodule Daraja.Callback.Validate do
  @moduledoc false

  @spec present_string(term()) :: :ok | {:error, String.t()}
  def present_string(value) when is_binary(value) and value != "", do: :ok
  def present_string(_), do: {:error, "must be a non-empty string"}
end
