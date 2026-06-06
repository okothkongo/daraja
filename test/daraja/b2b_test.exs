defmodule Daraja.B2BTest do
  use ExUnit.Case, async: false

  alias Daraja.B2B.{Callback, PaymentRequest, Response}
  alias Daraja.{APIError, Client}
  alias Daraja.HTTPClient.Mock

  @cert_pem File.read!("test/support/fixtures/security_credential_cert.pem")

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

    test "returns request_failed with the raw body when the response is not JSON", %{
      client: client
    } do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], "not json <<<"})

      assert {:error, :request_failed, %APIError{error_message: "non-JSON error response"}} =
               Daraja.B2B.request(client, @valid_params)
    end

    test "accepts a prebuilt PaymentRequest struct", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      {:ok, request} = PaymentRequest.new(@valid_params)
      assert {:ok, %Response.Success{}} = Daraja.B2B.request(client, request)
    end

    test "auto-encrypts security_credential tuple before sending", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      params = %{@valid_params | security_credential: {"my-initiator-password", @cert_pem}}
      assert {:ok, %Response.Success{}} = Daraja.B2B.request(client, params)
    end

    test "omits AccountReference when it is not provided", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      params = Map.delete(@valid_params, :account_reference)
      assert {:ok, %Response.Success{}} = Daraja.B2B.request(client, params)
    end
  end

  describe "PaymentRequest.new/1 security_credential resolution" do
    setup do
      Application.delete_env(:daraja, :b2b_security_credential)
      on_exit(fn -> Application.delete_env(:daraja, :b2b_security_credential) end)
      :ok
    end

    test "auto-encrypts a {password, pem} tuple" do
      params = %{@valid_params | security_credential: {"my-initiator-password", @cert_pem}}
      assert {:ok, request} = PaymentRequest.new(params)
      assert is_binary(request.security_credential)
      assert request.security_credential != "my-initiator-password"
    end

    test "returns invalid_request when pem in tuple is invalid" do
      params = %{@valid_params | security_credential: {"password", "bad-pem"}}

      assert {:error, :invalid_request, [{:security_credential, :invalid_public_key}]} =
               PaymentRequest.new(params)
    end

    test "returns invalid_request for a malformed security_credential" do
      params = %{@valid_params | security_credential: 12_345}

      assert {:error, :invalid_request, [{:security_credential, :invalid_format}]} =
               PaymentRequest.new(params)
    end

    test "returns invalid_request with :security_credential in missing when omitted and no env" do
      params = Map.delete(@valid_params, :security_credential)
      assert {:error, :invalid_request, missing} = PaymentRequest.new(params)
      assert :security_credential in missing
    end
  end

  describe "request/2 auth failure" do
    test "returns auth_failed without making API call", %{client: client} do
      Mock.push_response({:ok, 401, [], "Unauthorized"})

      assert {:error, :auth_failed, %APIError{status: 401}} =
               Daraja.B2B.request(client, @valid_params)
    end
  end

  describe "request/2 with invalid params" do
    test "returns invalid_request when a required field is missing", %{client: client} do
      assert {:error, :invalid_request, missing} =
               Daraja.B2B.request(client, Map.delete(@valid_params, :initiator))

      assert :initiator in missing
    end

    test "returns invalid_request for non-positive amount", %{client: client} do
      assert {:error, :invalid_request, [{:amount, _}]} =
               Daraja.B2B.request(client, %{@valid_params | amount: -1})
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

    test "tolerates string keys that are not known atoms", %{client: client} do
      assert {:error, :invalid_request, _missing} =
               Daraja.B2B.request(client, %{"definitely_not_an_atom_zzz" => 1})
    end
  end

  describe "request/2 env fallbacks" do
    @env_fields_to_keys %{
      initiator: :b2b_initiator,
      security_credential: :b2b_security_credential,
      queue_timeout_url: :b2b_queue_timeout_url,
      result_url: :b2b_result_url
    }

    setup do
      Application.put_env(:daraja, :b2b_initiator, "env-initiator")
      Application.put_env(:daraja, :b2b_security_credential, "env-credential")
      Application.put_env(:daraja, :b2b_queue_timeout_url, "https://env.example.com/b2b/timeout")
      Application.put_env(:daraja, :b2b_result_url, "https://env.example.com/b2b/result")

      on_exit(fn ->
        Enum.each(Map.values(@env_fields_to_keys), &Application.delete_env(:daraja, &1))
      end)

      :ok
    end

    test "uses env values when params omit the fields", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      params = Map.drop(@valid_params, Map.keys(@env_fields_to_keys))

      assert {:ok, %Response.Success{}} = Daraja.B2B.request(client, params)
    end

    test "uses env values when params set the fields to nil", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      params =
        Enum.reduce(Map.keys(@env_fields_to_keys), @valid_params, fn field, acc ->
          Map.put(acc, field, nil)
        end)

      assert {:ok, %Response.Success{}} = Daraja.B2B.request(client, params)
    end

    test "still returns invalid_request when neither params nor env set the fields", %{
      client: client
    } do
      Enum.each(Map.values(@env_fields_to_keys), &Application.delete_env(:daraja, &1))

      params = Map.drop(@valid_params, Map.keys(@env_fields_to_keys))

      assert {:error, :invalid_request, missing} = Daraja.B2B.request(client, params)
      assert Enum.all?(Map.keys(@env_fields_to_keys), &(&1 in missing))
    end

    test "auto-encrypts a {password, pem} tuple configured in the env", %{client: client} do
      Application.put_env(:daraja, :b2b_security_credential, {"env-password", @cert_pem})

      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      params = Map.delete(@valid_params, :security_credential)
      assert {:ok, %Response.Success{}} = Daraja.B2B.request(client, params)
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

    test "accept/0 returns the success acknowledgement map" do
      assert %{"ResultCode" => 0, "ResultDesc" => "Success"} = Callback.accept()
    end

    test "from_map/1 returns an empty Result for unrecognised payloads" do
      assert %Callback.Result{result_code: nil} = Callback.from_map(%{})
    end

    test "parse/1 returns ok for valid payloads and errors for invalid shapes" do
      assert {:ok, %Callback.Result{}} = Callback.parse(@successful_callback_payload)
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
      assert Callback.result_parameters_map(@successful_callback_payload) == %{
               "TransactionAmount" => 10,
               "TransactionReceipt" => "SG632NMUAB",
               "ReceiverPartyPublicName" => "600000 - Receiver Business"
             }
    end

    test "result_parameters_map/1 ignores entries it cannot flatten" do
      assert Callback.result_parameters_map([%{"unexpected" => 1}, "junk"]) == %{}
    end
  end
end
