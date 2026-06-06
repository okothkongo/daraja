defmodule Daraja.C2B.SimulateRequest do
  @moduledoc """
  Input struct for a C2B Simulate transaction request (sandbox only).

  Required fields: `short_code`, `command_id`, `amount`, `msisdn`.
  Optional fields: `bill_ref_number`.

  `command_id` must be either:
  - `"CustomerPayBillOnline"` — payment to a Paybill number.
  - `"CustomerBuyGoodsOnline"` — payment to a Till number.

  `bill_ref_number` is the account reference for Paybill payments.
  It should be `nil` for Till number payments (`CustomerBuyGoodsOnline`).
  """

  @type t :: %__MODULE__{
          short_code: String.t(),
          command_id: String.t(),
          amount: pos_integer(),
          msisdn: String.t(),
          bill_ref_number: String.t() | nil
        }

  defstruct [:short_code, :command_id, :amount, :msisdn, bill_ref_number: nil]

  @required [:short_code, :command_id, :amount, :msisdn]
  @valid_command_ids ~w[CustomerPayBillOnline CustomerBuyGoodsOnline]

  @spec new(map()) ::
          {:ok, t()} | {:error, :invalid_request, [atom() | {:command_id, String.t()}]}
  def new(params) when is_map(params) do
    params = normalize_keys(params)
    missing = Enum.filter(@required, fn key -> is_nil(params[key]) end)

    cond do
      missing != [] ->
        {:error, :invalid_request, missing}

      params[:command_id] not in @valid_command_ids ->
        {:error, :invalid_request,
         [{:command_id, "must be \"CustomerPayBillOnline\" or \"CustomerBuyGoodsOnline\""}]}

      match?({:error, _}, Daraja.RequestValidation.validate_amount(params[:amount])) ->
        {:error, :invalid_request,
         [elem(Daraja.RequestValidation.validate_amount(params[:amount]), 1)]}

      match?({:error, _}, Daraja.RequestValidation.validate_msisdn(params[:msisdn], :msisdn)) ->
        {:error, :invalid_request,
         [elem(Daraja.RequestValidation.validate_msisdn(params[:msisdn], :msisdn), 1)]}

      true ->
        {:ok,
         %__MODULE__{
           short_code: params[:short_code],
           command_id: params[:command_id],
           amount: params[:amount],
           msisdn: params[:msisdn],
           bill_ref_number: params[:bill_ref_number]
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
