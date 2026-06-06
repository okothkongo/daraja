defmodule Daraja.B2CCallbackTest do
  use ExUnit.Case, async: true

  alias Daraja.B2C.Callback

  @successful_payload %{
    "Result" => %{
      "ResultType" => 0,
      "ResultCode" => 0,
      "ResultDesc" => "The service request is processed successfully.",
      "OriginatorConversationID" => "53e3-4aa8-9fe0-8fb5e4092cdd3533373",
      "ConversationID" => "AG_20240706_2010364430d9bbdaf872",
      "TransactionID" => "SG632NMUAB",
      "ResultParameters" => %{
        "ResultParameter" => [
          %{"Key" => "TransactionAmount", "Value" => 10},
          %{"Key" => "TransactionReceipt", "Value" => "SG632NMUAB"},
          %{"Key" => "ReceiverPartyPublicName", "Value" => "254705912645 - TEST USER"}
        ]
      },
      "ReferenceData" => %{
        "ReferenceItem" => %{
          "Key" => "QueueTimeoutURL",
          "Value" => "https://internalsandbox.safaricom.co.ke/mpesa/b2cresults/v1/submit"
        }
      }
    }
  }

  @failed_payload %{
    "Result" => %{
      "ResultType" => 0,
      "ResultCode" => 2001,
      "ResultDesc" => "The initiator information is invalid.",
      "OriginatorConversationID" => "53e3-4aa8-9fe0-8fb5e4092cdd3544366",
      "ConversationID" => "AG_20240707_201062f6f6f5804f7a33",
      "TransactionID" => "SG722NMVXQ",
      "ReferenceData" => %{
        "ReferenceItem" => %{
          "Key" => "QueueTimeoutURL",
          "Value" => "https://internalsandbox.safaricom.co.ke/mpesa/b2cresults/v1/submit"
        }
      }
    }
  }

  test "parses a successful callback payload" do
    result = Callback.from_map(@successful_payload)

    assert result.result_code == 0
    assert result.transaction_id == "SG632NMUAB"

    assert result.reference_item == %{
             key: "QueueTimeoutURL",
             value: "https://internalsandbox.safaricom.co.ke/mpesa/b2cresults/v1/submit"
           }

    assert result.result_parameters_map["TransactionReceipt"] == "SG632NMUAB"
    assert result.result_parameters_map["TransactionAmount"] == 10
  end

  test "parses an unsuccessful callback payload" do
    result = Callback.from_map(@failed_payload)

    assert result.result_code == 2001
    assert result.result_desc == "The initiator information is invalid."
    assert result.result_parameters == []
    assert result.result_parameters_map == %{}
    assert result.transaction_id == "SG722NMVXQ"
  end

  test "flattens result parameters from list payloads" do
    params = [
      %{key: "TransactionAmount", value: 10},
      %{"Key" => "TransactionReceipt", "Value" => "SG632NMUAB"}
    ]

    assert Callback.result_parameters_map(params) == %{
             "TransactionAmount" => 10,
             "TransactionReceipt" => "SG632NMUAB"
           }
  end

  test "accept/0 returns the success acknowledgement map" do
    assert %{"ResultCode" => 0, "ResultDesc" => "Success"} = Callback.accept()
  end

  test "from_map/1 returns an empty Result for unrecognised payloads" do
    assert %Callback.Result{result_code: nil} = Callback.from_map(%{})

    assert {:ok, %Callback.Result{}} = Callback.parse(@successful_payload)
    assert {:error, :invalid_callback, _} = Callback.parse(%{})

    assert {:error, :invalid_callback, "missing OriginatorConversationID"} =
             Callback.parse(%{"Result" => %{}})
  end

  test "sets reference_item to nil when ReferenceData is absent" do
    payload = %{"Result" => %{"ResultCode" => 0, "TransactionID" => "X1"}}

    result = Callback.from_map(payload)
    assert result.reference_item == nil
  end

  test "flattens a single ResultParameter object (not wrapped in a list)" do
    payload = %{
      "Result" => %{
        "ResultParameters" => %{
          "ResultParameter" => %{"Key" => "TransactionReceipt", "Value" => "SG632NMUAB"}
        }
      }
    }

    result = Callback.from_map(payload)
    assert result.result_parameters_map == %{"TransactionReceipt" => "SG632NMUAB"}
  end

  test "ignores a malformed ResultParameter value" do
    payload = %{"Result" => %{"ResultParameters" => %{"ResultParameter" => "oops"}}}

    result = Callback.from_map(payload)
    assert result.result_parameters == []
  end

  test "result_parameters_map/1 returns an empty map for nil" do
    assert Callback.result_parameters_map(nil) == %{}
  end

  test "result_parameters_map/1 accepts a full payload map" do
    assert Callback.result_parameters_map(@successful_payload) == %{
             "TransactionAmount" => 10,
             "TransactionReceipt" => "SG632NMUAB",
             "ReceiverPartyPublicName" => "254705912645 - TEST USER"
           }
  end

  test "result_parameters_map/1 ignores entries it cannot flatten" do
    assert Callback.result_parameters_map([%{"unexpected" => 1}, "junk"]) == %{}
  end
end
