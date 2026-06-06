defmodule Daraja.ResponseCodeTest do
  use ExUnit.Case, async: true

  alias Daraja.B2B.Response, as: B2BResponse
  alias Daraja.B2C.Response, as: B2CResponse
  alias Daraja.C2B.Response, as: C2BResponse
  alias Daraja.Express.Response, as: ExpressResponse
  alias Daraja.ResponseCode

  describe "success?/1" do
    test "returns true only for ResponseCode 0" do
      assert ResponseCode.success?(%{"ResponseCode" => "0"})
      refute ResponseCode.success?(%{"ResponseCode" => "1"})
      refute ResponseCode.success?(%{"ResponseCode" => nil})
      refute ResponseCode.success?(%{})
    end
  end

  describe "from_map/1 rejects non-zero ResponseCode" do
    test "B2B" do
      map = %{
        "ConversationID" => "AG_123",
        "OriginatorConversationID" => "orig-1",
        "ResponseCode" => "1",
        "ResponseDescription" => "Rejected"
      }

      assert %B2BResponse.Error{
               error_code: "1",
               error_message: "Rejected"
             } = B2BResponse.from_map(map)
    end

    test "B2C" do
      map = %{
        "ConversationID" => "AG_123",
        "OriginatorConversationID" => "orig-1",
        "ResponseCode" => "1",
        "ResponseDescription" => "Rejected"
      }

      assert %B2CResponse.Error{
               error_code: "1",
               error_message: "Rejected"
             } = B2CResponse.from_map(map)
    end

    test "Express" do
      map = %{
        "MerchantRequestID" => "m-1",
        "CheckoutRequestID" => "ws_CO_1",
        "ResponseCode" => "1",
        "ResponseDescription" => "Rejected"
      }

      assert %ExpressResponse.Error{
               error_code: "1",
               error_message: "Rejected"
             } = ExpressResponse.from_map(map)
    end

    test "C2B" do
      map = %{
        "OriginatorCoversationID" => "orig-1",
        "ResponseCode" => "1",
        "ResponseDescription" => "Rejected"
      }

      assert %C2BResponse.Error{
               error_code: "1",
               error_message: "Rejected"
             } = C2BResponse.from_map(map)
    end
  end

  describe "from_map/1 accepts Safaricom OriginatorCoversationID typo" do
    test "B2B" do
      map = %{
        "ConversationID" => "AG_123",
        "OriginatorCoversationID" => "orig-typo",
        "ResponseCode" => "0",
        "ResponseDescription" => "Accepted"
      }

      assert %B2BResponse.Success{originator_conversation_id: "orig-typo"} =
               B2BResponse.from_map(map)
    end

    test "B2C" do
      map = %{
        "ConversationID" => "AG_123",
        "OriginatorCoversationID" => "orig-typo",
        "ResponseCode" => "0",
        "ResponseDescription" => "Accepted"
      }

      assert %B2CResponse.Success{originator_conversation_id: "orig-typo"} =
               B2CResponse.from_map(map)
    end
  end
end
