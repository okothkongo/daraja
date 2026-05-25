defmodule Daraja.B2CTest do
  use ExUnit.Case, async: false

  alias Daraja.B2C.Response
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
    originator_conversation_id: "600997_Test_32et3241ed8yu",
    initiator_name: "testapi",
    security_credential: "RC6E9WDxXR4b9X2c6z3gp0oC5Th==",
    command_id: "BusinessPayment",
    amount: 10,
    party_a: "600992",
    party_b: "254705912645",
    remarks: "remarked",
    queue_timeout_url: "https://example.com/b2c/timedout",
    result_url: "https://example.com/b2c/result",
    occasion: "ChristmasPay"
  }

  setup do
    Daraja.Auth.reset_token()
    Mock.reset()

    Application.put_env(:daraja, :http_client, Mock)
    Application.put_env(:daraja, :consumer_key, "test_key")
    Application.put_env(:daraja, :consumer_secret, "test_secret")
    Application.put_env(:daraja, :business_short_code, "600984")
    Application.put_env(:daraja, :passkey, "test_passkey")
    Application.put_env(:daraja, :callback_url, "https://example.com/callback")
    Application.put_env(:daraja, :environment, :sandbox)

    on_exit(fn ->
      Enum.each(
        ~w[http_client consumer_key consumer_secret business_short_code passkey callback_url environment]a,
        &Application.delete_env(:daraja, &1)
      )
    end)
  end

  describe "b2c_payment/1 with valid params" do
    test "returns Success struct on happy path" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      assert {:ok, %Response.Success{} = result} = Daraja.b2c_payment(@valid_params)
      assert result.response_code == "0"
      assert result.conversation_id == "AG_20240706_20106e9209f64bebd05b"
    end

    test "accepts string-keyed params" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      string_params = Map.new(@valid_params, fn {k, v} -> {Atom.to_string(k), v} end)
      assert {:ok, %Response.Success{}} = Daraja.b2c_payment(string_params)
    end

    test "returns request_failed with Error struct on API error body" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 400, [], @api_error})

      assert {:error, :request_failed, %Response.Error{} = err} =
               Daraja.b2c_payment(@valid_params)

      assert err.error_code == "500.002.1001"
    end

    test "returns http_error on transport failure" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:error, :timeout})

      assert {:error, :http_error, :timeout} = Daraja.b2c_payment(@valid_params)
    end
  end

  describe "b2c_payment/1 auth failure" do
    test "returns auth_failed without making API call" do
      Mock.push_response({:ok, 401, [], "Unauthorized"})
      assert {:error, :auth_failed, "Unauthorized"} = Daraja.b2c_payment(@valid_params)
    end
  end

  describe "b2c_payment/1 with invalid params" do
    test "returns invalid_request when a required field is missing" do
      assert {:error, :invalid_request, missing} =
               Daraja.b2c_payment(Map.delete(@valid_params, :party_b))

      assert :party_b in missing
    end

    test "returns invalid_request when command_id is invalid" do
      assert {:error, :invalid_request, [{:command_id, msg}]} =
               Daraja.b2c_payment(%{@valid_params | command_id: "InvalidCommand"})

      assert msg =~ "BusinessPayment"
    end
  end
end
