defmodule Daraja.ExpressTest do
  use ExUnit.Case, async: false

  alias Daraja.Client
  alias Daraja.Express.Response
  alias Daraja.HTTPClient.Mock

  @valid_params %{
    amount: 100,
    phone_number: "254712345678",
    account_reference: "Order-001"
  }

  @auth_success ~s({"access_token":"tok123","expires_in":"3600"})

  @stk_success ~s({
    "MerchantRequestID": "2654-4b64-97ff",
    "CheckoutRequestID": "ws_CO_100720",
    "ResponseCode": "0",
    "ResponseDescription": "Success. Request accepted for processing",
    "CustomerMessage": "Success. Request accepted for processing"
  })

  @stk_error ~s({
    "requestId": "req-001",
    "errorCode": "400.002.02",
    "errorMessage": "Bad Request - Invalid BusinessShortCode"
  })

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
        business_short_code: "174379",
        passkey: "bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919",
        callback_url: "https://example.com/callback",
        environment: :sandbox
      )

    {:ok, client: client}
  end

  describe "request/2 with valid params" do
    test "returns Success struct on happy path", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @stk_success})

      assert {:ok, %Response.Success{} = result} = Daraja.Express.request(client, @valid_params)
      assert result.checkout_request_id == "ws_CO_100720"
      assert result.response_code == "0"
    end

    test "returns request_failed with Error struct on API error body", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 400, [], @stk_error})

      assert {:error, :request_failed, %Response.Error{} = err} =
               Daraja.Express.request(client, @valid_params)

      assert err.error_code == "400.002.02"
    end

    test "returns http_error on transport failure during STK push", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:error, :timeout})

      assert {:error, :http_error, :timeout} = Daraja.Express.request(client, @valid_params)
    end
  end

  describe "request/2 auth failure" do
    test "returns auth_failed without making STK push call", %{client: client} do
      Mock.push_response({:ok, 401, [], "Unauthorized"})

      assert {:error, :auth_failed, "Unauthorized"} =
               Daraja.Express.request(client, @valid_params)
    end
  end

  describe "request/2 with invalid params" do
    test "returns invalid_request when amount is missing", %{client: client} do
      assert {:error, :invalid_request, missing} =
               Daraja.Express.request(client, %{
                 phone_number: "254712345678",
                 account_reference: "ref"
               })

      assert :amount in missing
    end

    test "returns invalid_request listing all missing required fields", %{client: client} do
      assert {:error, :invalid_request, missing} = Daraja.Express.request(client, %{})
      assert Enum.sort(missing) == [:account_reference, :amount, :phone_number]
    end
  end

  describe "request/2 with an incomplete client" do
    test "returns invalid_client when business_short_code is missing" do
      client =
        Client.new(
          consumer_key: "test_key",
          consumer_secret: "test_secret",
          passkey: "test_passkey",
          callback_url: "https://example.com/callback"
        )

      assert {:error, :invalid_client, missing} = Daraja.Express.request(client, @valid_params)
      assert :business_short_code in missing
    end

    test "lists every missing STK field" do
      client = Client.new(consumer_key: "test_key", consumer_secret: "test_secret")

      assert {:error, :invalid_client, missing} = Daraja.Express.request(client, @valid_params)
      assert Enum.sort(missing) == [:business_short_code, :callback_url, :passkey]
    end
  end
end
