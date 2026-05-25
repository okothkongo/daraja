defmodule Daraja.C2B do
  @moduledoc """
  Customer to Business (C2B) — receive payment notifications for Paybill or Till numbers.

  ## Register URLs

  Register your confirmation and (optional) validation callback URLs:

      Daraja.register_url(%{
        short_code: "600984",
        response_type: "Completed",
        confirmation_url: "https://example.com/c2b/confirmation",
        validation_url: "https://example.com/c2b/validation"
      })

  `response_type` controls what M-PESA does when your validation URL is unreachable:
  - `"Completed"` — M-PESA completes the transaction automatically.
  - `"Cancelled"` — M-PESA cancels the transaction automatically.

  ## Simulate (sandbox only)

  Simulate a C2B payment in the sandbox environment:

      Daraja.simulate(%{
        short_code: "600984",
        command_id: "CustomerPayBillOnline",
        amount: 100,
        msisdn: "254708374149",
        bill_ref_number: "INV-001"
      })

  ## Handle Callbacks

  Parse inbound validation and confirmation payloads posted by M-PESA to your registered URLs.
  See `Daraja.C2B.Callback` for details.
  """

  alias Daraja.C2B.{RegisterUrlRequest, SimulateRequest, Response}

  @register_url_path "/mpesa/c2b/v2/registerurl"
  @simulate_path "/mpesa/c2b/v2/simulate"

  @type result ::
          {:ok, Response.Success.t()}
          | {:error, :invalid_request, list()}
          | {:error, :auth_failed, term()}
          | {:error, :http_error, term()}
          | {:error, :request_failed, Response.Error.t()}

  @doc """
  Registers callback URLs for C2B payment notifications.

  Required params: `short_code`, `response_type`, `confirmation_url`, `validation_url`.

  `response_type` must be `"Completed"` or `"Cancelled"` (sentence case).

  Note: In production this is a one-time registration. To change URLs, delete
  them via the M-PESA Org portal and re-register.
  """
  @spec register_url(map() | RegisterUrlRequest.t()) :: result()
  def register_url(%RegisterUrlRequest{} = request), do: do_register_url(request)

  def register_url(params) when is_map(params) do
    case RegisterUrlRequest.new(params) do
      {:ok, request} -> do_register_url(request)
      error -> error
    end
  end

  @doc """
  Simulates a C2B payment transaction. Sandbox only — not supported in production.

  Required params: `short_code`, `command_id`, `amount`, `msisdn`.
  Optional params: `bill_ref_number`.

  `command_id` must be `"CustomerPayBillOnline"` or `"CustomerBuyGoodsOnline"`.
  """
  @spec simulate(map() | SimulateRequest.t()) :: result()
  def simulate(%SimulateRequest{} = request), do: do_simulate(request)

  def simulate(params) when is_map(params) do
    case SimulateRequest.new(params) do
      {:ok, request} -> do_simulate(request)
      error -> error
    end
  end

  defp do_register_url(%RegisterUrlRequest{} = request) do
    with {:ok, token} <- Daraja.Auth.fetch_token() do
      body =
        %{
          "ShortCode" => request.short_code,
          "ResponseType" => request.response_type,
          "ConfirmationURL" => request.confirmation_url,
          "ValidationURL" => request.validation_url
        }
        |> JSON.encode!()

      url = Daraja.Config.base_url() <> @register_url_path
      headers = [{"Authorization", "Bearer " <> token}, {"Content-Type", "application/json"}]
      make_request(url, headers, body)
    end
  end

  defp do_simulate(%SimulateRequest{} = request) do
    with {:ok, token} <- Daraja.Auth.fetch_token() do
      body =
        %{
          "ShortCode" => request.short_code,
          "CommandID" => request.command_id,
          "Amount" => request.amount,
          "Msisdn" => request.msisdn,
          "BillRefNumber" => request.bill_ref_number || ""
        }
        |> JSON.encode!()

      url = Daraja.Config.base_url() <> @simulate_path
      headers = [{"Authorization", "Bearer " <> token}, {"Content-Type", "application/json"}]
      make_request(url, headers, body)
    end
  end

  defp make_request(url, headers, body) do
    case Daraja.http_client().request(:post, url, headers, body) do
      {:ok, _status, _headers, response_body} -> parse_response(response_body)
      {:error, reason} -> {:error, :http_error, reason}
    end
  end

  defp parse_response(body) do
    case JSON.decode(body) do
      {:ok, map} -> map |> Response.from_map() |> wrap_response()
      {:error, _} -> {:error, :request_failed, body}
    end
  end

  defp wrap_response(%Response.Success{} = success), do: {:ok, success}
  defp wrap_response(%Response.Error{} = error), do: {:error, :request_failed, error}
end
