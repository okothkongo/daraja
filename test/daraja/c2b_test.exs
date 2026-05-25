defmodule Daraja.C2BTest do
  use ExUnit.Case, async: false

  alias Daraja.HTTPClient.Mock
  alias Daraja.C2B.{Response, Callback}

  @auth_success ~s({"access_token":"tok123","expires_in":"3600"})

  @register_success ~s({
    "OriginatorCoversationID": "6e86-45dd-91ac-fd5d4178ab523408729",
    "ResponseCode": "0",
    "ResponseDescription": "Success"
  })

  @simulate_success ~s({
    "OriginatorCoversationID": "53e3-4aa8-9fe0-8fb5e4092cdd3405976",
    "ResponseCode": "0",
    "ResponseDescription": "Accept the service request successfully."
  })

  @api_error ~s({
    "requestId": "req-001",
    "errorCode": "400.003.01",
    "errorMessage": "Invalid Access Token"
  })

  @valid_register_params %{
    short_code: "600984",
    response_type: "Completed",
    confirmation_url: "https://example.com/c2b/confirmation",
    validation_url: "https://example.com/c2b/validation"
  }

  @valid_simulate_params %{
    short_code: "600984",
    command_id: "CustomerPayBillOnline",
    amount: 100,
    msisdn: "254708374149",
    bill_ref_number: "INV-001"
  }

  setup do
    Daraja.Auth.reset_token()
    Mock.reset()

    Application.put_env(:daraja, :http_client, Mock)
    Application.put_env(:daraja, :consumer_key, "test_key")
    Application.put_env(:daraja, :consumer_secret, "test_secret")
    Application.put_env(:daraja, :business_short_code, "600984")

    Application.put_env(
      :daraja,
      :passkey,
      "bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919"
    )

    Application.put_env(:daraja, :callback_url, "https://example.com/callback")
    Application.put_env(:daraja, :environment, :sandbox)

    on_exit(fn ->
      Enum.each(
        ~w[http_client consumer_key consumer_secret business_short_code passkey callback_url environment]a,
        &Application.delete_env(:daraja, &1)
      )
    end)
  end

  # ---------------------------------------------------------------------------
  # register_url/1
  # ---------------------------------------------------------------------------

  describe "register_url/1 with valid params" do
    test "returns Success struct on happy path" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @register_success})

      assert {:ok, %Response.Success{} = result} = Daraja.register_url(@valid_register_params)
      assert result.response_code == "0"
      assert result.response_description == "Success"
      assert result.originator_conversation_id == "6e86-45dd-91ac-fd5d4178ab523408729"
    end

    test "accepts string-keyed params" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @register_success})

      string_params = Map.new(@valid_register_params, fn {k, v} -> {Atom.to_string(k), v} end)
      assert {:ok, %Response.Success{}} = Daraja.register_url(string_params)
    end

    test "accepts Cancelled as response_type" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @register_success})

      assert {:ok, %Response.Success{}} =
               Daraja.register_url(%{@valid_register_params | response_type: "Cancelled"})
    end

    test "returns request_failed with Error struct on API error body" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 400, [], @api_error})

      assert {:error, :request_failed, %Response.Error{} = err} =
               Daraja.register_url(@valid_register_params)

      assert err.error_code == "400.003.01"
    end

    test "returns http_error on transport failure" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:error, :timeout})

      assert {:error, :http_error, :timeout} = Daraja.register_url(@valid_register_params)
    end
  end

  describe "register_url/1 auth failure" do
    test "returns auth_failed without making API call" do
      Mock.push_response({:ok, 401, [], "Unauthorized"})

      assert {:error, :auth_failed, "Unauthorized"} = Daraja.register_url(@valid_register_params)
    end
  end

  describe "register_url/1 with invalid params" do
    test "returns invalid_request when short_code is missing" do
      assert {:error, :invalid_request, missing} =
               Daraja.register_url(Map.delete(@valid_register_params, :short_code))

      assert :short_code in missing
    end

    test "returns invalid_request listing all missing required fields" do
      assert {:error, :invalid_request, missing} = Daraja.register_url(%{})

      assert Enum.sort(missing) ==
               [:confirmation_url, :response_type, :short_code, :validation_url]
    end

    test "returns invalid_request when response_type is not Completed or Cancelled" do
      assert {:error, :invalid_request, [{:response_type, msg}]} =
               Daraja.register_url(%{@valid_register_params | response_type: "completed"})

      assert msg =~ "Completed"
    end
  end

  # ---------------------------------------------------------------------------
  # simulate/1
  # ---------------------------------------------------------------------------

  describe "simulate/1 with valid params" do
    test "returns Success struct on happy path" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @simulate_success})

      assert {:ok, %Response.Success{} = result} = Daraja.simulate(@valid_simulate_params)
      assert result.response_code == "0"

      assert result.originator_conversation_id ==
               "53e3-4aa8-9fe0-8fb5e4092cdd3405976"
    end

    test "accepts CustomerBuyGoodsOnline command_id without bill_ref_number" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @simulate_success})

      params =
        @valid_simulate_params
        |> Map.put(:command_id, "CustomerBuyGoodsOnline")
        |> Map.delete(:bill_ref_number)

      assert {:ok, %Response.Success{}} = Daraja.simulate(params)
    end

    test "returns request_failed with Error struct on API error body" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 400, [], @api_error})

      assert {:error, :request_failed, %Response.Error{} = err} =
               Daraja.simulate(@valid_simulate_params)

      assert err.error_code == "400.003.01"
    end

    test "returns http_error on transport failure" do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:error, :closed})

      assert {:error, :http_error, :closed} = Daraja.simulate(@valid_simulate_params)
    end
  end

  describe "simulate/1 auth failure" do
    test "returns auth_failed without making API call" do
      Mock.push_response({:ok, 401, [], "Unauthorized"})

      assert {:error, :auth_failed, "Unauthorized"} = Daraja.simulate(@valid_simulate_params)
    end
  end

  describe "simulate/1 with invalid params" do
    test "returns invalid_request when amount is missing" do
      assert {:error, :invalid_request, missing} =
               Daraja.simulate(Map.delete(@valid_simulate_params, :amount))

      assert :amount in missing
    end

    test "returns invalid_request listing all missing required fields" do
      assert {:error, :invalid_request, missing} = Daraja.simulate(%{})
      assert Enum.sort(missing) == [:amount, :command_id, :msisdn, :short_code]
    end

    test "returns invalid_request when command_id is not a valid value" do
      assert {:error, :invalid_request, [{:command_id, msg}]} =
               Daraja.simulate(%{@valid_simulate_params | command_id: "InvalidCommand"})

      assert msg =~ "CustomerPayBillOnline"
    end
  end

  # ---------------------------------------------------------------------------
  # Callback helpers
  # ---------------------------------------------------------------------------

  describe "Callback.from_map/1" do
    @validation_payload %{
      "TransactionType" => "Pay Bill",
      "TransID" => "RKL51ZDR4F",
      "TransTime" => "20231121121325",
      "TransAmount" => "5.00",
      "BusinessShortCode" => "600966",
      "BillRefNumber" => "Sample Transaction",
      "InvoiceNumber" => "",
      "OrgAccountBalance" => "",
      "ThirdPartyTransID" => "",
      "MSISDN" => "2547 ***** 126",
      "FirstName" => "NICHOLAS",
      "MiddleName" => "",
      "LastName" => ""
    }

    @confirmation_payload Map.put(@validation_payload, "OrgAccountBalance", "25.00")

    test "parses a validation payload into a Validation struct" do
      assert %Callback.Validation{} = result = Callback.from_map(@validation_payload)
      assert result.trans_id == "RKL51ZDR4F"
      assert result.trans_amount == "5.00"
      assert result.bill_ref_number == "Sample Transaction"
      assert result.first_name == "NICHOLAS"
      assert result.org_account_balance == ""
    end

    test "parses a confirmation payload into a Confirmation struct" do
      assert %Callback.Confirmation{} = result = Callback.from_map(@confirmation_payload)
      assert result.trans_id == "RKL51ZDR4F"
      assert result.org_account_balance == "25.00"
    end
  end

  describe "Callback.accept/0" do
    test "returns the accepted result map" do
      assert %{"ResultCode" => "0", "ResultDesc" => "Accepted"} = Callback.accept()
    end
  end

  describe "Callback.reject/1" do
    test "returns rejected map with valid result code" do
      assert %{"ResultCode" => "C2B00012", "ResultDesc" => "Rejected"} =
               Callback.reject("C2B00012")
    end

    test "falls back to C2B00016 for unknown result codes" do
      assert %{"ResultCode" => "C2B00016", "ResultDesc" => "Rejected"} =
               Callback.reject("UNKNOWN")
    end

    test "supports all defined result codes" do
      for code <- ~w[C2B00011 C2B00012 C2B00013 C2B00014 C2B00015 C2B00016] do
        assert %{"ResultCode" => ^code} = Callback.reject(code)
      end
    end
  end
end
