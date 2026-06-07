defmodule Daraja.Callback.Items do
  @moduledoc false

  @spec normalize_list(term()) :: [map()]
  def normalize_list(nil), do: []
  def normalize_list(list) when is_list(list), do: list
  def normalize_list(single) when is_map(single), do: [single]
  def normalize_list(_), do: []

  @spec extract_key_value(term()) :: [%{key: String.t(), value: term()}]
  def extract_key_value(raw) do
    raw
    |> normalize_list()
    |> Enum.flat_map(fn
      %{"Key" => key, "Value" => value} when is_binary(key) -> [%{key: key, value: value}]
      _ -> []
    end)
  end

  @spec extract_name_value(term()) :: [%{name: String.t(), value: term()}]
  def extract_name_value(raw) do
    raw
    |> normalize_list()
    |> Enum.flat_map(fn
      %{"Name" => name, "Value" => value} when is_binary(name) -> [%{name: name, value: value}]
      _ -> []
    end)
  end
end
