defmodule Daraja.B2B do
  @moduledoc """
  Business to Business (B2B) payments.

  Initiate transfers between organization shortcodes or till numbers.

  ## Example

      client = Daraja.Client.new()

      Daraja.B2B.request(client, %{
        initiator: "testapi",
        security_credential: "base64-credential",
        command_id: "BusinessPayBill",
        sender_identifier_type: 4,
        receiver_identifier_type: 4,
        amount: 10500,
        party_a: "600992",
        party_b: "600000",
        account_reference: "INV-001",
        remarks: "B2B Payment",
        queue_timeout_url: "https://example.com/b2b/timeout",
        result_url: "https://example.com/b2b/result"
      })
  """

  alias Daraja.Client
  alias Daraja.B2B.{PaymentRequest, Response}

  @payment_request_path "/mpesa/b2b/v1/paymentrequest"

  @type result ::
          {:ok, Response.Success.t()}
          | {:error, :invalid_request, list()}
          | {:error, :auth_failed, Daraja.APIError.t()}
          | {:error, :http_error, Daraja.APIError.t() | term()}
          | {:error, :request_failed, Response.Error.t() | Daraja.APIError.t()}

  @doc """
  Sends a B2B payment request.

  Required params:
  - `initiator`
  - `security_credential` — pre-encrypted Base64 string or `{password, pem}` tuple (auto-encrypted)
  - `command_id`
  - `sender_identifier_type`
  - `receiver_identifier_type`
  - `amount`
  - `party_a`
  - `party_b`
  - `remarks`
  - `queue_timeout_url`
  - `result_url`

  Optional params:
  - `account_reference`
  """
  @spec request(Client.t(), map() | PaymentRequest.t()) :: result()
  def request(%Client{} = client, %PaymentRequest{} = request), do: do_request(client, request)

  def request(%Client{} = client, params) when is_map(params) do
    case PaymentRequest.new(params) do
      {:ok, request} -> do_request(client, request)
      error -> error
    end
  end

  defp do_request(%Client{} = client, %PaymentRequest{} = request) do
    body =
      %{
        "Initiator" => request.initiator,
        "SecurityCredential" => request.security_credential,
        "CommandID" => request.command_id,
        "SenderIdentifierType" => request.sender_identifier_type,
        # Safaricom API typo — must not be "ReceiverIdentifierType"
        "RecieverIdentifierType" => request.receiver_identifier_type,
        "Amount" => request.amount,
        "PartyA" => request.party_a,
        "PartyB" => request.party_b,
        "AccountReference" => request.account_reference,
        "Remarks" => request.remarks,
        "QueueTimeOutURL" => request.queue_timeout_url,
        "ResultURL" => request.result_url
      }
      |> maybe_drop_nil_account_reference()
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
        Daraja.HTTPResponse.dispatch(status, response_body, &parse_response/1)

      {:error, reason} ->
        {:error, :http_error, reason}
    end
  end

  defp parse_response(body) do
    case JSON.decode(body) do
      {:ok, map} -> map |> Response.from_map() |> wrap_response()
      {:error, _} -> {:error, :request_failed, Daraja.APIError.from_body(body)}
    end
  end

  defp wrap_response(%Response.Success{} = success), do: {:ok, success}
  defp wrap_response(%Response.Error{} = error), do: {:error, :request_failed, error}

  defp maybe_drop_nil_account_reference(payload) do
    if is_nil(payload["AccountReference"]) do
      Map.delete(payload, "AccountReference")
    else
      payload
    end
  end
end
