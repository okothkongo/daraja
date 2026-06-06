defmodule Daraja.ExpressCallbackTest do
  use ExUnit.Case, async: true

  alias Daraja.Express.Callback

  @successful_payload %{
    "Body" => %{
      "stkCallback" => %{
        "MerchantRequestID" => "29115-34620561-1",
        "CheckoutRequestID" => "ws_CO_191220191020363925",
        "ResultCode" => 0,
        "ResultDesc" => "The service request is processed successfully.",
        "CallbackMetadata" => %{
          "Item" => [
            %{"Name" => "Amount", "Value" => 1},
            %{"Name" => "MpesaReceiptNumber", "Value" => "NLJ7RT61SV"},
            %{"Name" => "TransactionDate", "Value" => 20_191_219_102_115},
            %{"Name" => "PhoneNumber", "Value" => 254_708_374_149}
          ]
        }
      }
    }
  }

  @cancelled_payload %{
    "Body" => %{
      "stkCallback" => %{
        "MerchantRequestID" => "29115-34620561-2",
        "CheckoutRequestID" => "ws_CO_191220191020363926",
        "ResultCode" => 1032,
        "ResultDesc" => "Request cancelled by user"
      }
    }
  }

  test "parses a successful callback payload" do
    result = Callback.from_map(@successful_payload)

    assert result.result_code == 0
    assert result.checkout_request_id == "ws_CO_191220191020363925"
    assert result.callback_metadata_map["MpesaReceiptNumber"] == "NLJ7RT61SV"
    assert result.callback_metadata_map["Amount"] == 1
  end

  test "parses a cancelled callback payload" do
    result = Callback.from_map(@cancelled_payload)

    assert result.result_code == 1032
    assert result.result_desc == "Request cancelled by user"
    assert result.callback_metadata == []
    assert result.callback_metadata_map == %{}
  end

  test "from_map/1 returns an empty Result for unrecognised payloads" do
    assert %Callback.Result{result_code: nil} = Callback.from_map(%{})
  end

  test "parse/1 returns ok for valid payloads and errors for invalid shapes" do
    assert {:ok, %Callback.Result{result_code: 0}} = Callback.parse(@successful_payload)
    assert {:error, :invalid_callback, _} = Callback.parse(%{})

    assert {:error, :invalid_callback, "missing CheckoutRequestID"} =
             Callback.parse(%{"Body" => %{"stkCallback" => %{}}})
  end

  test "accept/0 returns the success acknowledgement map" do
    assert %{"ResultCode" => 0, "ResultDesc" => "Success"} = Callback.accept()
  end

  test "flattens a single CallbackMetadata Item (not wrapped in a list)" do
    payload = %{
      "Body" => %{
        "stkCallback" => %{
          "ResultCode" => 0,
          "CallbackMetadata" => %{"Item" => %{"Name" => "Amount", "Value" => 1}}
        }
      }
    }

    result = Callback.from_map(payload)
    assert result.callback_metadata_map == %{"Amount" => 1}
  end

  test "ignores a malformed CallbackMetadata Item value" do
    payload = %{
      "Body" => %{
        "stkCallback" => %{"ResultCode" => 0, "CallbackMetadata" => %{"Item" => "oops"}}
      }
    }

    result = Callback.from_map(payload)
    assert result.callback_metadata == []
  end

  test "callback_metadata_map/1 returns an empty map for nil" do
    assert Callback.callback_metadata_map(nil) == %{}
  end

  test "callback_metadata_map/1 ignores entries it cannot flatten" do
    assert Callback.callback_metadata_map([%{"unexpected" => 1}, "junk"]) == %{}
  end

  test "callback_metadata_map/1 flattens both atom- and string-keyed items" do
    items = [%{name: "Amount", value: 1}, %{"Name" => "MpesaReceiptNumber", "Value" => "NLJ7"}]

    assert Callback.callback_metadata_map(items) == %{
             "Amount" => 1,
             "MpesaReceiptNumber" => "NLJ7"
           }
  end
end
