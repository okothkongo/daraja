defmodule Daraja.Express do
  @moduledoc """
  M-Pesa Express (STK Push) — initiates a payment prompt on a customer's phone.

  ## Example

      Daraja.stk_push(%{
        amount: 100,
        phone_number: "254712345678",
        account_reference: "Order-001",
        transaction_desc: "Payment"
      })
  """

  alias Daraja.Express.{Request, Response}

  @stk_push_path "/mpesa/stkpush/v1/processrequest"

  @spec stk_push(map() | Request.t()) ::
          {:ok, Response.Success.t()}
          | {:error, :invalid_request, [atom()]}
          | {:error, :auth_failed, term()}
          | {:error, :http_error, term()}
          | {:error, :request_failed, Response.Error.t()}
  def stk_push(%Request{} = request), do: do_stk_push(request)

  def stk_push(params) when is_map(params) do
    case Request.new(params) do
      {:ok, request} -> do_stk_push(request)
      error -> error
    end
  end

  defp do_stk_push(%Request{} = request) do
    with {:ok, token} <- Daraja.Auth.fetch_token() do
      timestamp = NaiveDateTime.utc_now() |> Calendar.strftime("%Y%m%d%H%M%S")
      short_code = Daraja.Config.business_short_code()
      password = Base.encode64(short_code <> Daraja.Config.passkey() <> timestamp)

      body =
        %{
          "BusinessShortCode" => short_code,
          "Password" => password,
          "Timestamp" => timestamp,
          "TransactionType" => request.transaction_type,
          "Amount" => request.amount,
          "PartyA" => request.phone_number,
          "PartyB" => short_code,
          "PhoneNumber" => request.phone_number,
          "CallBackURL" => Daraja.Config.callback_url(),
          "AccountReference" => request.account_reference,
          "TransactionDesc" => request.transaction_desc || ""
        }
        |> JSON.encode!()

      url = Daraja.Config.base_url() <> @stk_push_path
      headers = [{"Authorization", "Bearer " <> token}, {"Content-Type", "application/json"}]
      make_request(url, headers, body)
    end
  end

  defp make_request(url, headers, body) do
    case Daraja.http_client().request(:post, url, headers, body) do
      {:ok, _status, _headers, response_body} ->
        case JSON.decode(response_body) do
          {:ok, map} ->
            case Response.from_map(map) do
              %Response.Success{} = success -> {:ok, success}
              %Response.Error{} = error -> {:error, :request_failed, error}
            end

          {:error, _} ->
            {:error, :request_failed, response_body}
        end

      {:error, reason} ->
        {:error, :http_error, reason}
    end
  end
end
