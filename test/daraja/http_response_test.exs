defmodule Daraja.HTTPResponseTest do
  use ExUnit.Case, async: true

  alias Daraja.Express.Response

  @daraja_error ~s({
    "requestId": "req-001",
    "errorCode": "400.002.02",
    "errorMessage": "Bad Request"
  })

  defp parse(body) do
    case JSON.decode(body) do
      {:ok, map} ->
        case Response.from_map(map) do
          %Response.Success{} = success -> {:ok, success}
          %Response.Error{} = error -> {:error, :request_failed, error}
        end

      {:error, _} ->
        {:error, :request_failed, body}
    end
  end

  test "parses 200 responses" do
    body = ~s({"CheckoutRequestID":"ws_CO_1","MerchantRequestID":"m","ResponseCode":"0"})

    assert {:ok, %Response.Success{checkout_request_id: "ws_CO_1"}} =
             Daraja.HTTPResponse.dispatch(200, body, &parse/1)
  end

  test "parses 400 responses with Daraja error envelope" do
    assert {:error, :request_failed, %Response.Error{error_code: "400.002.02"}} =
             Daraja.HTTPResponse.dispatch(400, @daraja_error, &parse/1)
  end

  test "maps 401 and 403 to auth_failed without parsing" do
    assert {:error, :auth_failed, "Unauthorized"} =
             Daraja.HTTPResponse.dispatch(401, "Unauthorized", &parse/1)

    assert {:error, :auth_failed, "Forbidden"} =
             Daraja.HTTPResponse.dispatch(403, "Forbidden", &parse/1)
  end

  test "maps 5xx to http_error without parsing" do
    assert {:error, :http_error, {502, "<html>"}} =
             Daraja.HTTPResponse.dispatch(502, "<html>", &parse/1)

    assert {:error, :http_error, {500, "Internal Server Error"}} =
             Daraja.HTTPResponse.dispatch(500, "Internal Server Error", &parse/1)
  end

  test "maps other unexpected statuses to http_error" do
    assert {:error, :http_error, {404, "Not Found"}} =
             Daraja.HTTPResponse.dispatch(404, "Not Found", &parse/1)
  end

  test "detects invalid access token in Daraja error envelope" do
    body = ~s({"requestId":"r","errorCode":"400.003.01","errorMessage":"Invalid Access Token"})

    assert Daraja.HTTPResponse.invalid_access_token?(body)
    refute Daraja.HTTPResponse.invalid_access_token?(@daraja_error)
  end
end
