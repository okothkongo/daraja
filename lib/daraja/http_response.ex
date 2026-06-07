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
    * **401** / **403** — `{:error, :auth_failed, %Daraja.APIError{}}` (expired or
      invalid token).
    * **5xx** and other statuses — `{:error, :http_error, %Daraja.APIError{}}` for
      gateway or unexpected HTTP failures.
  """

  alias Daraja.APIError

  @spec dispatch(
          Daraja.HTTPClient.status(),
          binary(),
          (binary(), Daraja.HTTPClient.status() -> term())
        ) :: term()
  def dispatch(status, body, parse) when status in 200..299, do: parse.(body, status)
  def dispatch(400, body, parse), do: parse.(body, 400)

  def dispatch(status, body, _parse) when status in [401, 403] do
    {:error, :auth_failed, APIError.from_body(body, status: status)}
  end

  def dispatch(status, body, _parse) when status >= 500 do
    {:error, :http_error, APIError.from_body(body, status: status)}
  end

  def dispatch(status, body, _parse) do
    {:error, :http_error, APIError.from_body(body, status: status)}
  end

  @invalid_access_token_code "400.003.01"

  @doc false
  @spec invalid_access_token?(term()) :: boolean()
  def invalid_access_token?(%APIError{error_code: @invalid_access_token_code}), do: true

  def invalid_access_token?(%{error_code: @invalid_access_token_code}), do: true

  def invalid_access_token?(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, %{"errorCode" => @invalid_access_token_code}} -> true
      _ -> false
    end
  end

  def invalid_access_token?(_), do: false
end
