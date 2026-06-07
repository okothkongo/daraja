defmodule Daraja.ResponseCode do
  @moduledoc false

  @success "0"

  @spec success?(map()) :: boolean()
  def success?(map) when is_map(map), do: map["ResponseCode"] == @success

  @spec error_fields(map()) :: %{error_code: String.t() | nil, error_message: String.t() | nil}
  def error_fields(map) when is_map(map) do
    %{
      error_code: map["ResponseCode"],
      error_message: map["ResponseDescription"]
    }
  end
end
