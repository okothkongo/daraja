defmodule Daraja.Express.Request do
  @moduledoc """
  Input struct for an STK Push request.

  Required fields: `amount`, `phone_number`, `account_reference`.

  Phone number must be in international format without the `+`, e.g. `"254712345678"`.
  Account reference is displayed to the customer in the USSD prompt (max 12 chars).
  """

  @type t :: %__MODULE__{
          amount: pos_integer(),
          phone_number: String.t(),
          account_reference: String.t(),
          transaction_desc: String.t() | nil,
          transaction_type: String.t()
        }

  defstruct [
    :amount,
    :phone_number,
    :account_reference,
    transaction_desc: nil,
    transaction_type: "CustomerPayBillOnline"
  ]

  @required [:amount, :phone_number, :account_reference]

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_request, [atom()]}
  def new(params) when is_map(params) do
    params = normalize_keys(params)
    missing = Enum.filter(@required, fn key -> is_nil(params[key]) end)

    if missing == [] do
      {:ok,
       %__MODULE__{
         amount: params[:amount],
         phone_number: params[:phone_number],
         account_reference: params[:account_reference],
         transaction_desc: params[:transaction_desc],
         transaction_type: params[:transaction_type] || "CustomerPayBillOnline"
       }}
    else
      {:error, :invalid_request, missing}
    end
  end

  defp normalize_keys(params) do
    Map.new(params, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  rescue
    ArgumentError -> Map.new(params, fn {k, v} -> {k, v} end)
  end
end
