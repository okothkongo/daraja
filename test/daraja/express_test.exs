defmodule Daraja.ExpressTest do
  use ExUnit.Case, async: false

  alias Daraja.HTTPClient.Mock
  alias Daraja.Express.Response

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
    Application.put_env(:daraja, :http_client, Mock)
    Application.put_env(:daraja, :consumer_key, "test_key")
    Application.put_env(:daraja, :consumer_secret, "test_secret")
    Application.put_env(:daraja, :business_short_code, "174379")

    Application.put_env(
      :daraja,
      :passkey,
      "bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919"
    )

    Application.put_env(:daraja, :callback_url, "https://example.com/callback")
    Application.put_env(:daraja, :environment, :sandbox)

    on_exit(fn ->
      Enum.each(
        [
          :http_client,
          :consumer_key,
          :consumer_secret,
          :business_short_code,
          :passkey,
          :callback_url,
          :environment
        ],
        &Application.delete_env(:daraja, &1)
      )
    end)
  end

  describe "stk_push/1 with valid params" do
    test "returns Success struct on happy path" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @stk_success})

      assert {:ok, %Response.Success{} = result} = Daraja.stk_push(@valid_params)
      assert result.checkout_request_id == "ws_CO_100720"
      assert result.response_code == "0"
    end

    test "returns request_failed with Error struct on API error body" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 400, [], @stk_error})

      assert {:error, :request_failed, %Response.Error{} = err} = Daraja.stk_push(@valid_params)
      assert err.error_code == "400.002.02"
    end

    test "returns http_error on transport failure during STK push" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:error, :timeout})

      assert {:error, :http_error, :timeout} = Daraja.stk_push(@valid_params)
    end
  end

  describe "stk_push/1 auth failure" do
    test "returns auth_failed without making STK push call" do
      Mock.push_response({:ok, 401, [], "Unauthorized"})

      assert {:error, :auth_failed, "Unauthorized"} = Daraja.stk_push(@valid_params)
      assert Process.get(:mock_http_queue, []) == []
    end
  end

  describe "stk_push/1 with invalid params" do
    test "returns invalid_request when amount is missing" do
      assert {:error, :invalid_request, missing} =
               Daraja.stk_push(%{phone_number: "254712345678", account_reference: "ref"})

      assert :amount in missing
    end

    test "returns invalid_request listing all missing required fields" do
      assert {:error, :invalid_request, missing} = Daraja.stk_push(%{})
      assert Enum.sort(missing) == [:account_reference, :amount, :phone_number]
    end
  end
end
