defmodule Daraja.B2BTest do
  use ExUnit.Case, async: false

  alias Daraja.B2B.{Callback, Response}
  alias Daraja.Client
  alias Daraja.HTTPClient.Mock

  @auth_success ~s({"access_token":"tok123","expires_in":"3600"})

  @payment_success ~s({
    "ConversationID": "AG_20240706_20106e9209f64bebd05b",
    "OriginatorConversationID": "600997_Test_32et3241ed8yu",
    "ResponseCode": "0",
    "ResponseDescription": "Accept the service request successfully."
  })

  @api_error ~s({
    "requestId": "req-001",
    "errorCode": "500.002.1001",
    "errorMessage": "Duplicate OriginatorConversationID."
  })

  @valid_params %{
    initiator: "testapi",
    security_credential: "RC6E9WDxXR4b9X2c6z3gp0oC5Th==",
    command_id: "BusinessPayBill",
    sender_identifier_type: 4,
    receiver_identifier_type: 4,
    amount: 10,
    party_a: "600992",
    party_b: "600000",
    remarks: "remarked",
    account_reference: "INV-001",
    queue_timeout_url: "https://example.com/b2b/timedout",
    result_url: "https://example.com/b2b/result"
  }

  @successful_callback_payload %{
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
          %{"Key" => "ReceiverPartyPublicName", "Value" => "600000 - Receiver Business"}
        ]
      },
      "ReferenceData" => %{
        "ReferenceItem" => %{
          "Key" => "QueueTimeoutURL",
          "Value" => "https://example.com/b2b/timeout"
        }
      }
    }
  }

  @failed_callback_payload %{
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
          "Value" => "https://example.com/b2b/timeout"
        }
      }
    }
  }

  setup do
    Mock.reset()

    Application.put_env(:daraja, :http_client, Mock)

    on_exit(fn ->
      Application.delete_env(:daraja, :http_client)
    end)

    client =
      Client.new(
        consumer_key: "test_key",
        consumer_secret: "test_secret",
        environment: :sandbox
      )

    {:ok, client: client}
  end

  describe "request/2 with valid params" do
    test "returns Success struct on happy path", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      assert {:ok, %Response.Success{} = result} = Daraja.B2B.request(client, @valid_params)
      assert result.response_code == "0"
      assert result.conversation_id == "AG_20240706_20106e9209f64bebd05b"
    end

    test "accepts string-keyed params", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      string_params = Map.new(@valid_params, fn {k, v} -> {Atom.to_string(k), v} end)
      assert {:ok, %Response.Success{}} = Daraja.B2B.request(client, string_params)
    end

    test "returns request_failed with Error struct on API error body", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 400, [], @api_error})

      assert {:error, :request_failed, %Response.Error{} = err} =
               Daraja.B2B.request(client, @valid_params)

      assert err.error_code == "500.002.1001"
    end

    test "returns http_error on transport failure", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:error, :timeout})

      assert {:error, :http_error, :timeout} = Daraja.B2B.request(client, @valid_params)
    end
  end

  describe "request/2 auth failure" do
    test "returns auth_failed without making API call", %{client: client} do
      Mock.push_response({:ok, 401, [], "Unauthorized"})
      assert {:error, :auth_failed, "Unauthorized"} = Daraja.B2B.request(client, @valid_params)
    end
  end

  describe "request/2 with invalid params" do
    test "returns invalid_request when a required field is missing", %{client: client} do
      assert {:error, :invalid_request, missing} =
               Daraja.B2B.request(client, Map.delete(@valid_params, :initiator))

      assert :initiator in missing
    end

    test "returns invalid_request when command_id is invalid", %{client: client} do
      assert {:error, :invalid_request, [{:command_id, msg}]} =
               Daraja.B2B.request(client, %{@valid_params | command_id: "InvalidCommand"})

      assert msg =~ "BusinessPayBill"
    end

    test "returns invalid_request when sender_identifier_type is invalid", %{client: client} do
      assert {:error, :invalid_request, [{:sender_identifier_type, "must be 2 or 4"}]} =
               Daraja.B2B.request(client, %{@valid_params | sender_identifier_type: 1})
    end

    test "returns invalid_request when receiver_identifier_type is invalid", %{client: client} do
      assert {:error, :invalid_request, [{:receiver_identifier_type, "must be 2 or 4"}]} =
               Daraja.B2B.request(client, %{@valid_params | receiver_identifier_type: 1})
    end
  end

  describe "Callback" do
    test "parses a successful callback payload" do
      result = Callback.from_map(@successful_callback_payload)

      assert result.result_code == 0
      assert result.transaction_id == "SG632NMUAB"

      assert result.reference_item == %{
               key: "QueueTimeoutURL",
               value: "https://example.com/b2b/timeout"
             }

      assert result.result_parameters_map["TransactionReceipt"] == "SG632NMUAB"
      assert result.result_parameters_map["TransactionAmount"] == 10
    end

    test "parses an unsuccessful callback payload" do
      result = Callback.from_map(@failed_callback_payload)

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
  end
end
