defmodule Daraja.Express do
  @moduledoc """
  M-Pesa Express (STK Push) — initiates a payment prompt on a customer's phone.

  ## Example

      client = Daraja.Client.new()

      Daraja.Express.request(client, %{
        amount: 100,
        phone_number: "254712345678",
        account_reference: "Order-001",
        transaction_desc: "Payment"
      })

  The client must carry `business_short_code`, `passkey`, and `callback_url`
  (either via options to `Daraja.Client.new/1` or via the `:daraja` application
  environment). Calls return `{:error, :invalid_client, missing}` when any of
  those fields is missing.

  ## Security

  STK requests encode the passkey into the `Password` field
  (`Base64(short_code <> passkey <> timestamp)`). Anyone with a captured request
  body can recover the passkey. Never log STK request bodies; ensure TLS-only
  transport and redact `Password` in any custom HTTP client logging.

  The `Timestamp` field and password must use East Africa Time (EAT, UTC+3),
  not the host machine's local timezone or raw UTC.
  """

  alias Daraja.Client
  alias Daraja.Express.{Request, Response}

  @stk_push_path "/mpesa/stkpush/v1/processrequest"
  @eat_utc_offset_seconds 3 * 60 * 60

  @stk_client_fields [:business_short_code, :passkey, :callback_url]

  @type result ::
          {:ok, Response.Success.t()}
          | {:error, :invalid_request, [atom()]}
          | {:error, :invalid_client, [atom()]}
          | {:error, :auth_failed, Daraja.APIError.t()}
          | {:error, :http_error, Daraja.APIError.t() | term()}
          | {:error, :request_failed, Response.Error.t() | Daraja.APIError.t()}

  @doc """
  Sends an STK Push (M-Pesa Express) request.

  Required params: `amount`, `phone_number`, `account_reference`.
  Optional params: `transaction_desc`, `transaction_type`.
  """
  @spec request(Client.t(), map() | Request.t()) :: result()
  def request(%Client{} = client, %Request{} = request), do: do_request(client, request)

  def request(%Client{} = client, params) when is_map(params) do
    case Request.new(params) do
      {:ok, request} -> do_request(client, request)
      error -> error
    end
  end

  @doc false
  @spec stk_timestamp() :: String.t()
  def stk_timestamp do
    DateTime.utc_now()
    |> DateTime.add(@eat_utc_offset_seconds, :second)
    |> DateTime.to_naive()
    |> Calendar.strftime("%Y%m%d%H%M%S")
  end

  defp do_request(%Client{} = client, %Request{} = request) do
    with :ok <- validate_client(client) do
      timestamp = stk_timestamp()
      short_code = client.business_short_code
      password = Base.encode64(short_code <> client.passkey <> timestamp)

      body =
        JSON.encode!(%{
          "BusinessShortCode" => short_code,
          "Password" => password,
          "Timestamp" => timestamp,
          "TransactionType" => request.transaction_type,
          "Amount" => request.amount,
          "PartyA" => request.phone_number,
          "PartyB" => short_code,
          "PhoneNumber" => request.phone_number,
          "CallBackURL" => client.callback_url,
          "AccountReference" => request.account_reference,
          "TransactionDesc" => request.transaction_desc || ""
        })

      url = Client.base_url(client) <> @stk_push_path

      Daraja.Auth.with_token(client, fn token ->
        headers = [{"Authorization", "Bearer " <> token}, {"Content-Type", "application/json"}]
        make_request(url, headers, body)
      end)
    end
  end

  defp validate_client(%Client{} = client) do
    missing = Enum.filter(@stk_client_fields, fn key -> is_nil(Map.fetch!(client, key)) end)

    cond do
      missing != [] ->
        {:error, :invalid_client, missing}

      true ->
        case Daraja.CallbackURL.validate(client.callback_url, environment: client.environment) do
          :ok -> :ok
          {:error, message} -> {:error, :invalid_client, [{:callback_url, message}]}
        end
    end
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
end
