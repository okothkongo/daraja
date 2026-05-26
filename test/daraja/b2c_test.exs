defmodule Daraja.B2CTest do
  use ExUnit.Case, async: false

  alias Daraja.B2C.Response
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

  describe "payment/2 with valid params" do
    test "returns Success struct on happy path", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      assert {:ok, %Response.Success{} = result} = Daraja.B2C.payment(client, @valid_params)
      assert result.response_code == "0"
      assert result.conversation_id == "AG_20240706_20106e9209f64bebd05b"
    end

    test "accepts string-keyed params", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      string_params = Map.new(@valid_params, fn {k, v} -> {Atom.to_string(k), v} end)
      assert {:ok, %Response.Success{}} = Daraja.B2C.payment(client, string_params)
    end

    test "returns request_failed with Error struct on API error body", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 400, [], @api_error})

      assert {:error, :request_failed, %Response.Error{} = err} =
               Daraja.B2C.payment(client, @valid_params)

      assert err.error_code == "500.002.1001"
    end

    test "returns http_error on transport failure", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:error, :timeout})

      assert {:error, :http_error, :timeout} = Daraja.B2C.payment(client, @valid_params)
    end
  end

  describe "payment/2 auth failure" do
    test "returns auth_failed without making API call", %{client: client} do
      Mock.push_response({:ok, 401, [], "Unauthorized"})
      assert {:error, :auth_failed, "Unauthorized"} = Daraja.B2C.payment(client, @valid_params)
    end
  end

  describe "payment/2 with invalid params" do
    test "returns invalid_request when a required field is missing", %{client: client} do
      assert {:error, :invalid_request, missing} =
               Daraja.B2C.payment(client, Map.delete(@valid_params, :party_b))

      assert :party_b in missing
    end

    test "returns invalid_request when command_id is invalid", %{client: client} do
      assert {:error, :invalid_request, [{:command_id, msg}]} =
               Daraja.B2C.payment(client, %{@valid_params | command_id: "InvalidCommand"})

      assert msg =~ "BusinessPayment"
    end
  end

  describe "payment/2 env fallbacks" do
    @env_fields_to_keys %{
      initiator_name: :b2c_initiator_name,
      security_credential: :b2c_security_credential,
      queue_timeout_url: :b2c_queue_timeout_url,
      result_url: :b2c_result_url
    }

    setup do
      Application.put_env(:daraja, :b2c_initiator_name, "env-initiator")
      Application.put_env(:daraja, :b2c_security_credential, "env-credential")
      Application.put_env(:daraja, :b2c_queue_timeout_url, "https://env.example.com/b2c/timeout")
      Application.put_env(:daraja, :b2c_result_url, "https://env.example.com/b2c/result")

      on_exit(fn ->
        Enum.each(Map.values(@env_fields_to_keys), &Application.delete_env(:daraja, &1))
      end)

      :ok
    end

    test "uses env values when params omit the fields", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      params = Map.drop(@valid_params, Map.keys(@env_fields_to_keys))

      assert {:ok, %Response.Success{}} = Daraja.B2C.payment(client, params)
    end

    test "uses env values when params set the fields to nil", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      params =
        Enum.reduce(Map.keys(@env_fields_to_keys), @valid_params, fn field, acc ->
          Map.put(acc, field, nil)
        end)

      assert {:ok, %Response.Success{}} = Daraja.B2C.payment(client, params)
    end

    test "still returns invalid_request when neither params nor env set the fields", %{
      client: client
    } do
      Enum.each(Map.values(@env_fields_to_keys), &Application.delete_env(:daraja, &1))

      params = Map.drop(@valid_params, Map.keys(@env_fields_to_keys))

      assert {:error, :invalid_request, missing} = Daraja.B2C.payment(client, params)
      assert Enum.all?(Map.keys(@env_fields_to_keys), &(&1 in missing))
    end
  end
end
