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
  @valid_transaction_types ~w[CustomerPayBillOnline CustomerBuyGoodsOnline]
  @max_account_reference_length 12

  @spec new(map()) ::
          {:ok, t()}
          | {:error, :invalid_request,
             [
               atom()
               | {:amount, String.t()}
               | {:phone_number, String.t()}
               | {:account_reference, String.t()}
               | {:transaction_type, String.t()}
             ]}
  def new(params) when is_map(params) do
    params = normalize_keys(params)
    missing = Enum.filter(@required, fn key -> is_nil(params[key]) end)
    transaction_type = params[:transaction_type] || "CustomerPayBillOnline"

    cond do
      missing != [] ->
        {:error, :invalid_request, missing}

      match?({:error, _}, Daraja.RequestValidation.validate_amount(params[:amount])) ->
        {:error, :invalid_request,
         [elem(Daraja.RequestValidation.validate_amount(params[:amount]), 1)]}

      match?({:error, _}, Daraja.RequestValidation.validate_msisdn(params[:phone_number])) ->
        {:error, :invalid_request,
         [elem(Daraja.RequestValidation.validate_msisdn(params[:phone_number]), 1)]}

      not is_binary(params[:account_reference]) ->
        {:error, :invalid_request,
         [
           {:account_reference,
            "must be a string of at most #{@max_account_reference_length} characters"}
         ]}

      byte_size(params[:account_reference]) > @max_account_reference_length ->
        {:error, :invalid_request,
         [{:account_reference, "must be at most #{@max_account_reference_length} characters"}]}

      transaction_type not in @valid_transaction_types ->
        {:error, :invalid_request,
         [
           {:transaction_type, "must be \"CustomerPayBillOnline\" or \"CustomerBuyGoodsOnline\""}
         ]}

      true ->
        {:ok,
         %__MODULE__{
           amount: params[:amount],
           phone_number: params[:phone_number],
           account_reference: params[:account_reference],
           transaction_desc: params[:transaction_desc],
           transaction_type: transaction_type
         }}
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
