defmodule Daraja.APIErrorTest do
  use ExUnit.Case, async: true

  alias Daraja.APIError

  test "from_body/2 parses Daraja JSON error envelopes" do
    body = ~s({"requestId":"r1","errorCode":"400.003.01","errorMessage":"Invalid Access Token"})

    assert %APIError{
             request_id: "r1",
             error_code: "400.003.01",
             error_message: "Invalid Access Token",
             status: 401,
             raw_body: nil
           } = APIError.from_body(body, status: 401)
  end

  test "from_body/2 parses OAuth-style error keys" do
    body = ~s({"error":"invalid_client","error_description":"Bad credentials"})

    assert %APIError{
             error_code: "invalid_client",
             error_message: "Bad credentials",
             status: 401
           } = APIError.from_body(body, status: 401)
  end

  test "from_body/2 accepts requestid key variant" do
    body = ~s({"requestid":"r2","errorCode":"400.003.01","errorMessage":"Invalid Access Token"})

    assert %APIError{request_id: "r2"} = APIError.from_body(body, status: 401)
  end

  test "from_body/2 rejects falsy field values" do
    body =
      ~s({"requestId":false,"errorCode":"","errorMessage":0,"error":"fallback","error_description":"ok"})

    assert %APIError{
             request_id: nil,
             error_code: "fallback",
             error_message: "ok"
           } = APIError.from_body(body, status: 400)
  end

  test "from_body/1 defaults status to :unknown" do
    assert %APIError{status: :unknown} = APIError.from_body("{}")
  end

  test "from_body/1 summarizes non-JSON bodies and captures raw_body" do
    assert %APIError{
             error_message: "non-JSON error response",
             status: :unknown,
             raw_body: "Unauthorized"
           } = APIError.from_body("Unauthorized")

    assert %APIError{error_message: "empty response", raw_body: "   "} =
             APIError.from_body("   ")
  end

  test "from_body/1 rejects unrecognized JSON without expected keys" do
    assert %APIError{
             request_id: nil,
             error_code: nil,
             error_message: "unrecognized JSON error response",
             status: :unknown,
             raw_body: ~s({"foo":"bar"})
           } = APIError.from_body(~s({"foo":"bar"}))
  end

  test "inspect/1 omits raw_body for safe logging" do
    error = APIError.from_body("Unauthorized")

    assert inspect(error) =~ "non-JSON error response"
    refute inspect(error) =~ "Unauthorized"
    assert APIError.raw_body(error) == "Unauthorized"
  end

  test "from_body/1 truncates raw_body longer than 512 bytes" do
    body = String.duplicate("x", 600)

    assert %APIError{raw_body: truncated} = APIError.from_body(body)
    assert byte_size(truncated) == 515
    assert String.ends_with?(truncated, "...")
  end
end
