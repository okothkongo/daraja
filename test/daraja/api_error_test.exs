defmodule Daraja.APIErrorTest do
  use ExUnit.Case, async: true

  alias Daraja.APIError

  test "from_body/2 parses Daraja JSON error envelopes" do
    body = ~s({"requestId":"r1","errorCode":"400.003.01","errorMessage":"Invalid Access Token"})

    assert %APIError{
             request_id: "r1",
             error_code: "400.003.01",
             error_message: "Invalid Access Token",
             status: 401
           } = APIError.from_body(body, status: 401)
  end

  test "from_body/1 summarizes non-JSON bodies without including raw content" do
    assert %APIError{error_message: "non-JSON error response", status: nil} =
             APIError.from_body("Unauthorized")

    assert %APIError{error_message: "empty response"} = APIError.from_body("   ")
  end
end
