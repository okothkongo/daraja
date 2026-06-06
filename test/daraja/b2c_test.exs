defmodule Daraja.B2CTest do
  use ExUnit.Case, async: false

  alias Daraja.B2C.{PaymentRequest, Response}
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

  @payment_rejected ~s({
    "ConversationID": "AG_20240706_20106e9209f64bebd05b",
    "OriginatorConversationID": "600997_Test_32et3241ed8yu",
    "ResponseCode": "1",
    "ResponseDescription": "Rejected by Safaricom."
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

    test "returns request_failed when ResponseCode is non-zero", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_rejected})

      assert {:error, :request_failed, %Response.Error{} = err} =
               Daraja.B2C.payment(client, @valid_params)

      assert err.error_code == "1"
      assert err.error_message == "Rejected by Safaricom."
    end

    test "returns http_error on transport failure", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:error, :timeout})

      assert {:error, :http_error, :timeout} = Daraja.B2C.payment(client, @valid_params)
    end

    test "returns request_failed with the raw body when the response is not JSON", %{
      client: client
    } do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], "not json <<<"})

      assert {:error, :request_failed, %APIError{error_message: "non-JSON error response"}} =
               Daraja.B2C.payment(client, @valid_params)
    end

    test "accepts a prebuilt PaymentRequest struct", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      {:ok, request} = PaymentRequest.new(@valid_params)
      assert {:ok, %Response.Success{}} = Daraja.B2C.payment(client, request)
    end

    test "auto-encrypts security_credential tuple before sending", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      params = %{@valid_params | security_credential: {"my-initiator-password", @cert_pem}}
      assert {:ok, %Response.Success{}} = Daraja.B2C.payment(client, params)
    end

    test "omits Occasion when it is not provided", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      params = Map.delete(@valid_params, :occasion)
      assert {:ok, %Response.Success{}} = Daraja.B2C.payment(client, params)
    end
  end

  describe "PaymentRequest.new/1 security_credential resolution" do
    setup do
      Application.delete_env(:daraja, :b2c_security_credential)
      on_exit(fn -> Application.delete_env(:daraja, :b2c_security_credential) end)
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

    test "returns invalid_request when env security_credential tuple cannot be encrypted" do
      Application.put_env(:daraja, :b2c_security_credential, {"password", "bad-pem"})
      params = Map.delete(@valid_params, :security_credential)

      assert {:error, :invalid_request, [{:security_credential, :invalid_public_key}]} =
               PaymentRequest.new(params)
    end
  end

  describe "payment/2 auth failure" do
    test "returns auth_failed without making API call", %{client: client} do
      Mock.push_response({:ok, 401, [], "Unauthorized"})

      assert {:error, :auth_failed, %APIError{status: 401}} =
               Daraja.B2C.payment(client, @valid_params)
    end

    test "invalidates cache and retries after payment 401", %{client: client} do
      name = :"b2c_cache_#{System.unique_integer([:positive])}"
      start_supervised!({Daraja.TokenCache, name: name})
      Application.put_env(:daraja, :token_cache, name)
      on_exit(fn -> Application.delete_env(:daraja, :token_cache) end)

      Mock.push_response({:ok, 200, [], ~s({"access_token":"stale","expires_in":"3600"})})
      Mock.push_response({:ok, 401, [], "Unauthorized"})
      Mock.push_response({:ok, 200, [], ~s({"access_token":"fresh","expires_in":"3600"})})
      Mock.push_response({:ok, 200, [], @payment_success})

      assert {:ok, %Response.Success{}} = Daraja.B2C.payment(client, @valid_params)
      assert {:error, :no_response_queued} = Mock.request(:get, "", [], "")
    end
  end

  describe "payment/2 with invalid params" do
    test "returns invalid_request for unsafe callback URLs", %{client: client} do
      params =
        Map.put(@valid_params, :queue_timeout_url, "https://10.0.0.1/timeout")

      assert {:error, :invalid_request, [{:queue_timeout_url, _}]} =
               Daraja.B2C.payment(client, params)
    end

    test "returns invalid_request for non-positive amount", %{client: client} do
      assert {:error, :invalid_request, [{:amount, _}]} =
               Daraja.B2C.payment(client, %{@valid_params | amount: "100"})
    end

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

    test "tolerates string keys that are not known atoms", %{client: client} do
      assert {:error, :invalid_request, _missing} =
               Daraja.B2C.payment(client, %{"definitely_not_an_atom_zzz" => 1})
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

    test "auto-encrypts a {password, pem} tuple configured in the env", %{client: client} do
      Application.put_env(:daraja, :b2c_security_credential, {"env-password", @cert_pem})

      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @payment_success})

      params = Map.delete(@valid_params, :security_credential)
      assert {:ok, %Response.Success{}} = Daraja.B2C.payment(client, params)
    end
  end
end
