defmodule Daraja.B2C do
  @moduledoc """
  Business to Customer (B2C) payments.

  Initiate disbursement from an M-PESA organization shortcode to a customer MSISDN.

  ## Example

      client = Daraja.Client.new()

      Daraja.B2C.payment(client, %{
        originator_conversation_id: "my-unique-id-001",
        initiator_name: "testapi",
        security_credential: "base64-credential",
        command_id: "BusinessPayment",
        amount: 10,
        party_a: "600997",
        party_b: "254705912645",
        remarks: "Payment for promotion",
        queue_timeout_url: "https://example.com/b2c/timeout",
        result_url: "https://example.com/b2c/result",
        occasion: "PromoPayout"
      })
  """

  alias Daraja.Client
  alias Daraja.B2C.{PaymentRequest, Response}

  @payment_request_path "/mpesa/b2c/v3/paymentrequest"

  @type result ::
          {:ok, Response.Success.t()}
          | {:error, :invalid_request, list()}
          | {:error, :auth_failed, Daraja.APIError.t()}
          | {:error, :http_error, Daraja.APIError.t() | term()}
          | {:error, :request_failed, Response.Error.t() | Daraja.APIError.t()}

  @doc """
  Sends a B2C payment request.

  Required params:
  - `originator_conversation_id`
  - `initiator_name`
  - `security_credential` — pre-encrypted Base64 string or `{password, pem}` tuple (auto-encrypted)
  - `command_id`
  - `amount`
  - `party_a`
  - `party_b`
  - `remarks`
  - `queue_timeout_url`
  - `result_url`

  Optional params:
  - `occasion`
  """
  @spec payment(Client.t(), map() | PaymentRequest.t()) :: result()
  def payment(%Client{} = client, %PaymentRequest{} = request), do: do_payment(client, request)

  def payment(%Client{} = client, params) when is_map(params) do
    case PaymentRequest.new(params) do
      {:ok, request} -> do_payment(client, request)
      error -> error
    end
  end

  defp do_payment(%Client{} = client, %PaymentRequest{} = request) do
    body =
      %{
        "OriginatorConversationID" => request.originator_conversation_id,
        "InitiatorName" => request.initiator_name,
        "SecurityCredential" => request.security_credential,
        "CommandID" => request.command_id,
        "Amount" => request.amount,
        "PartyA" => request.party_a,
        "PartyB" => request.party_b,
        "Remarks" => request.remarks,
        "QueueTimeOutURL" => request.queue_timeout_url,
        "ResultURL" => request.result_url,
        "Occasion" => request.occasion
      }
      |> maybe_drop_nil_occasion()
      |> JSON.encode!()

    url = Client.base_url(client) <> @payment_request_path

    Daraja.Auth.with_token(client, fn token ->
      headers = [{"Authorization", "Bearer " <> token}, {"Content-Type", "application/json"}]
      make_request(url, headers, body)
    end)
  end

  defp make_request(url, headers, body) do
    case Daraja.http_client().request(:post, url, headers, body) do
      {:ok, status, _headers, response_body} ->
        Daraja.HTTPResponse.dispatch(status, response_body, &parse_response/2)

      {:error, reason} ->
        {:error, :http_error, reason}
    end
  end

  defp parse_response(body, status) do
    case JSON.decode(body) do
      {:ok, map} -> map |> Response.from_map() |> wrap_response()
      {:error, _} -> {:error, :request_failed, Daraja.APIError.from_body(body, status: status)}
    end
  end

  defp wrap_response(%Response.Success{} = success), do: {:ok, success}
  defp wrap_response(%Response.Error{} = error), do: {:error, :request_failed, error}

  defp maybe_drop_nil_occasion(payload) do
    if is_nil(payload["Occasion"]) do
      Map.delete(payload, "Occasion")
    else
      payload
    end
  end
end
