defmodule Daraja.HTTPResponse do
  @moduledoc """
  Maps HTTP status codes from Safaricom Daraja API responses before JSON parsing.

  Daraja signals most application errors in the response body (`errorCode`,
  `errorMessage`, or `ResponseCode`) and commonly uses HTTP **200** or **400** for
  those payloads. Auth and infrastructure failures use other status codes and
  should not be parsed as business-level success or error structs.

  ## Status handling

    * **2xx** and **400** — parse the body with the caller's parser (Daraja error
      envelope or success fields).
    * **401** / **403** — `{:error, :auth_failed, body}` (expired or invalid token).
    * **5xx** and other statuses — `{:error, :http_error, {status, body}}` for
      gateway or unexpected HTTP failures.
  """

  @spec dispatch(Daraja.HTTPClient.status(), binary(), (binary() -> term())) :: term()
  def dispatch(status, body, parse) when status in 200..299, do: parse.(body)
  def dispatch(400, body, parse), do: parse.(body)

  def dispatch(status, body, _parse) when status in [401, 403] do
    {:error, :auth_failed, body}
  end

  def dispatch(status, body, _parse) when status >= 500 do
    {:error, :http_error, {status, body}}
  end

  def dispatch(status, body, _parse) do
    {:error, :http_error, {status, body}}
  end
end
