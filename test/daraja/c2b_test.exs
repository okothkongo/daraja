defmodule Daraja.C2BTest do
  use ExUnit.Case, async: false

  alias Daraja.C2B.{Callback, RegisterUrlRequest, Response, SimulateRequest}
  alias Daraja.Client
  alias Daraja.HTTPClient.Mock

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

  # ---------------------------------------------------------------------------
  # register_url/2
  # ---------------------------------------------------------------------------

  describe "register_url/2 with valid params" do
    test "returns Success struct on happy path", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @register_success})

      assert {:ok, %Response.Success{} = result} =
               Daraja.C2B.register_url(client, @valid_register_params)

      assert result.response_code == "0"
      assert result.response_description == "Success"
      assert result.originator_conversation_id == "6e86-45dd-91ac-fd5d4178ab523408729"
    end

    test "accepts string-keyed params", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @register_success})

      string_params = Map.new(@valid_register_params, fn {k, v} -> {Atom.to_string(k), v} end)
      assert {:ok, %Response.Success{}} = Daraja.C2B.register_url(client, string_params)
    end

    test "accepts Cancelled as response_type", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @register_success})

      assert {:ok, %Response.Success{}} =
               Daraja.C2B.register_url(client, %{
                 @valid_register_params
                 | response_type: "Cancelled"
               })
    end

    test "returns request_failed with Error struct on API error body", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 400, [], @api_error})

      assert {:error, :request_failed, %Response.Error{} = err} =
               Daraja.C2B.register_url(client, @valid_register_params)

      assert err.error_code == "400.003.01"
    end

    test "returns http_error on transport failure", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:error, :timeout})

      assert {:error, :http_error, :timeout} =
               Daraja.C2B.register_url(client, @valid_register_params)
    end

    test "returns request_failed with the raw body when the response is not JSON", %{
      client: client
    } do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], "not json <<<"})

      assert {:error, :request_failed, "not json <<<"} =
               Daraja.C2B.register_url(client, @valid_register_params)
    end

    test "accepts a prebuilt RegisterUrlRequest struct", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @register_success})

      {:ok, request} = RegisterUrlRequest.new(@valid_register_params)
      assert {:ok, %Response.Success{}} = Daraja.C2B.register_url(client, request)
    end

    test "tolerates string keys that are not known atoms", %{client: client} do
      assert {:error, :invalid_request, _missing} =
               Daraja.C2B.register_url(client, %{"definitely_not_an_atom_zzz" => 1})
    end
  end

  describe "register_url/2 auth failure" do
    test "returns auth_failed without making API call", %{client: client} do
      Mock.push_response({:ok, 401, [], "Unauthorized"})

      assert {:error, :auth_failed, "Unauthorized"} =
               Daraja.C2B.register_url(client, @valid_register_params)
    end
  end

  describe "register_url/2 with invalid params" do
    test "returns invalid_request when short_code is missing", %{client: client} do
      assert {:error, :invalid_request, missing} =
               Daraja.C2B.register_url(client, Map.delete(@valid_register_params, :short_code))

      assert :short_code in missing
    end

    test "returns invalid_request listing all missing required fields", %{client: client} do
      assert {:error, :invalid_request, missing} = Daraja.C2B.register_url(client, %{})

      assert Enum.sort(missing) ==
               [:confirmation_url, :response_type, :short_code, :validation_url]
    end

    test "returns invalid_request when response_type is not Completed or Cancelled", %{
      client: client
    } do
      assert {:error, :invalid_request, [{:response_type, msg}]} =
               Daraja.C2B.register_url(client, %{
                 @valid_register_params
                 | response_type: "completed"
               })

      assert msg =~ "Completed"
    end
  end

  # ---------------------------------------------------------------------------
  # simulate/2
  # ---------------------------------------------------------------------------

  describe "simulate/2 with valid params" do
    test "returns Success struct on happy path", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @simulate_success})

      assert {:ok, %Response.Success{} = result} =
               Daraja.C2B.simulate(client, @valid_simulate_params)

      assert result.response_code == "0"

      assert result.originator_conversation_id ==
               "53e3-4aa8-9fe0-8fb5e4092cdd3405976"
    end

    test "accepts CustomerBuyGoodsOnline command_id without bill_ref_number", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @simulate_success})

      params =
        @valid_simulate_params
        |> Map.put(:command_id, "CustomerBuyGoodsOnline")
        |> Map.delete(:bill_ref_number)

      assert {:ok, %Response.Success{}} = Daraja.C2B.simulate(client, params)
    end

    test "returns request_failed with Error struct on API error body", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 400, [], @api_error})

      assert {:error, :request_failed, %Response.Error{} = err} =
               Daraja.C2B.simulate(client, @valid_simulate_params)

      assert err.error_code == "400.003.01"
    end

    test "returns http_error on transport failure", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:error, :closed})

      assert {:error, :http_error, :closed} =
               Daraja.C2B.simulate(client, @valid_simulate_params)
    end

    test "accepts a prebuilt SimulateRequest struct", %{client: client} do
      Mock.push_response({:ok, 200, [], @auth_success})
      Mock.push_response({:ok, 200, [], @simulate_success})

      {:ok, request} = SimulateRequest.new(@valid_simulate_params)
      assert {:ok, %Response.Success{}} = Daraja.C2B.simulate(client, request)
    end

    test "tolerates string keys that are not known atoms", %{client: client} do
      assert {:error, :invalid_request, _missing} =
               Daraja.C2B.simulate(client, %{"definitely_not_an_atom_zzz" => 1})
    end
  end

  describe "simulate/2 auth failure" do
    test "returns auth_failed without making API call", %{client: client} do
      Mock.push_response({:ok, 401, [], "Unauthorized"})

      assert {:error, :auth_failed, "Unauthorized"} =
               Daraja.C2B.simulate(client, @valid_simulate_params)
    end
  end

  describe "simulate/2 with invalid params" do
    test "returns invalid_request when amount is missing", %{client: client} do
      assert {:error, :invalid_request, missing} =
               Daraja.C2B.simulate(client, Map.delete(@valid_simulate_params, :amount))

      assert :amount in missing
    end

    test "returns invalid_request listing all missing required fields", %{client: client} do
      assert {:error, :invalid_request, missing} = Daraja.C2B.simulate(client, %{})
      assert Enum.sort(missing) == [:amount, :command_id, :msisdn, :short_code]
    end

    test "returns invalid_request when command_id is not a valid value", %{client: client} do
      assert {:error, :invalid_request, [{:command_id, msg}]} =
               Daraja.C2B.simulate(client, %{
                 @valid_simulate_params
                 | command_id: "InvalidCommand"
               })

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

  describe "Callback.parse/1" do
    test "returns ok for valid C2B payloads and errors for invalid shapes" do
      assert {:ok, %Callback.Validation{}} =
               Callback.parse(%{
                 "TransID" => "RKL51ZDR4F",
                 "TransAmount" => "5.00",
                 "BusinessShortCode" => "600966",
                 "MSISDN" => "254700000000"
               })

      assert {:error, :invalid_callback, reason} = Callback.parse(%{})
      assert reason =~ "TransID"
    end

    test "kind/1 distinguishes validation and confirmation structs" do
      validation = %Callback.Validation{}
      confirmation = %Callback.Confirmation{}

      assert Callback.kind(validation) == :validation
      assert Callback.kind(confirmation) == :confirmation
    end
  end

  describe "Callback.accept/0" do
    test "returns the accepted result map" do
      assert %{"ResultCode" => "0", "ResultDesc" => "Accepted"} = Callback.accept()
    end
  end

  describe "Callback.reject/1" do
    @reject_descriptions %{
      "C2B00011" => "Invalid MSISDN",
      "C2B00012" => "Invalid Account Number",
      "C2B00013" => "Invalid Amount",
      "C2B00014" => "Invalid KYC Details",
      "C2B00015" => "Invalid Short Code",
      "C2B00016" => "Other Error"
    }

    test "returns the matching description for a valid result code" do
      assert %{"ResultCode" => "C2B00012", "ResultDesc" => "Invalid Account Number"} =
               Callback.reject("C2B00012")
    end

    test "falls back to C2B00016 / Other Error for unknown codes" do
      assert %{"ResultCode" => "C2B00016", "ResultDesc" => "Other Error"} =
               Callback.reject("UNKNOWN")
    end

    test "supports all defined result codes with the correct description" do
      for {code, desc} <- @reject_descriptions do
        assert %{"ResultCode" => ^code, "ResultDesc" => ^desc} = Callback.reject(code)
      end
    end
  end
end
