defmodule Daraja.CallbackItemsTest do
  use ExUnit.Case, async: true

  alias Daraja.Callback.Items

  test "extract_key_value/1 skips malformed list entries" do
    raw = [
      %{"Key" => "TransactionReceipt", "Value" => "SG632NMUAB"},
      "oops",
      %{"unexpected" => true}
    ]

    assert Items.extract_key_value(raw) == [
             %{key: "TransactionReceipt", value: "SG632NMUAB"}
           ]
  end

  test "extract_name_value/1 skips malformed list entries" do
    raw = [
      %{"Name" => "Amount", "Value" => 1},
      "oops",
      %{"unexpected" => true}
    ]

    assert Items.extract_name_value(raw) == [%{name: "Amount", value: 1}]
  end

  test "normalize_list/1 handles nil, scalar map, and invalid values" do
    assert Items.normalize_list(nil) == []
    assert Items.normalize_list(%{"Key" => "A"}) == [%{"Key" => "A"}]
    assert Items.normalize_list("oops") == []
  end
end
