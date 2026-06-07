defmodule Daraja.Express.Callback do
  @moduledoc """
  Helpers for parsing STK Push (M-Pesa Express) callback payloads posted by
  M-PESA to the merchant's `CallBackURL`.

  STK Push callbacks are one-way notifications: M-PESA only needs the merchant
  to acknowledge receipt with `ResultCode: 0`.

  Daraja does **not** sign callbacks.   Verify the request with
  `Daraja.Callback.Security` and deduplicate with `Daraja.Callback.Guard` before
  treating parsed output as proof of payment. Use `parse/1` on untrusted input.

  ## Example

      with :ok <-
             Daraja.Callback.Security.verify(
               ip: conn.remote_ip,
               check_ip: true,
               shared_secret: callback_secret,
               provided_secret: conn.params["token"]
             ),
           {:ok, callback} <- Daraja.Express.Callback.parse(payload),
           :ok <- Daraja.Callback.Guard.ensure_fresh(callback.checkout_request_id) do
        json(conn, Daraja.Express.Callback.accept())
      end
  """

  defmodule Result do
    @moduledoc "Parsed STK Push callback payload."

    @type metadata_item :: %{name: String.t(), value: term()}

    @type t :: %__MODULE__{
            merchant_request_id: String.t() | nil,
            checkout_request_id: String.t() | nil,
            result_code: integer() | String.t() | nil,
            result_desc: String.t() | nil,
            callback_metadata: [metadata_item()],
            callback_metadata_map: %{optional(String.t()) => term()}
          }

    defstruct [
      :merchant_request_id,
      :checkout_request_id,
      :result_code,
      :result_desc,
      callback_metadata: [],
      callback_metadata_map: %{}
    ]
  end

  @doc """
  Parses an STK Push callback payload map into a `%Result{}` struct.

  Successful payloads include a `CallbackMetadata` block with the transaction
  details (Amount, MpesaReceiptNumber, TransactionDate, PhoneNumber). Failed
  payloads omit it.

  Prefer `parse/1` for inbound HTTP requests. `from_map/1` accepts only payloads
  with a `Body.stkCallback` envelope.
  """
  @spec from_map(map()) :: Result.t()
  def from_map(%{"Body" => %{"stkCallback" => stk}}) when is_map(stk) do
    items = extract_metadata_items(stk)

    %Result{
      merchant_request_id: stk["MerchantRequestID"],
      checkout_request_id: stk["CheckoutRequestID"],
      result_code: stk["ResultCode"],
      result_desc: stk["ResultDesc"],
      callback_metadata: items,
      callback_metadata_map: callback_metadata_map(items)
    }
  end

  @doc """
  Parses an STK Push callback map from an untrusted HTTP request.

  Returns `{:error, :invalid_callback, reason}` when the top-level shape does
  not match a Daraja STK callback.
  """
  @spec parse(map()) :: {:ok, Result.t()} | {:error, :invalid_callback, String.t()}
  def parse(%{"Body" => %{"stkCallback" => stk}} = map) when is_map(stk) do
    case Daraja.Callback.Validate.present_string(stk["CheckoutRequestID"]) do
      :ok -> {:ok, from_map(map)}
      {:error, _} -> {:error, :invalid_callback, "missing CheckoutRequestID"}
    end
  end

  def parse(_), do: {:error, :invalid_callback, "missing Body.stkCallback"}

  @doc """
  Builds the JSON response body used to acknowledge an STK Push callback.

      Daraja.Express.Callback.accept()
      #=> %{"ResultCode" => 0, "ResultDesc" => "Success"}
  """
  @spec accept() :: %{String.t() => String.t() | non_neg_integer()}
  def accept, do: %{"ResultCode" => 0, "ResultDesc" => "Success"}

  @doc """
  Flattens the `CallbackMetadata.Item` list into `%{"Name" => value}`.
  """
  @spec callback_metadata_map([map()] | nil) :: %{optional(String.t()) => term()}
  def callback_metadata_map(nil), do: %{}

  def callback_metadata_map(items) when is_list(items) do
    Enum.reduce(items, %{}, fn
      %{name: name, value: value}, acc when is_binary(name) -> Map.put(acc, name, value)
      %{"Name" => name, "Value" => value}, acc when is_binary(name) -> Map.put(acc, name, value)
      _, acc -> acc
    end)
  end

  defp extract_metadata_items(stk) do
    stk
    |> get_in(["CallbackMetadata", "Item"])
    |> Daraja.Callback.Items.extract_name_value()
  end
end
