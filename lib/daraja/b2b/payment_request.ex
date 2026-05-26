defmodule Daraja.B2B.PaymentRequest do
  @moduledoc """
  Input struct for a B2B payment request.

  Required fields:
  - `initiator`
  - `security_credential`
  - `command_id`
  - `sender_identifier_type`
  - `receiver_identifier_type`
  - `amount`
  - `party_a`
  - `party_b`
  - `remarks`
  - `queue_timeout_url`
  - `result_url`

  Optional fields:
  - `account_reference`
  """

  @type command_id :: String.t()
  @type identifier_type :: 2 | 4

  @type t :: %__MODULE__{
          initiator: String.t(),
          security_credential: String.t(),
          command_id: command_id(),
          sender_identifier_type: identifier_type(),
          receiver_identifier_type: identifier_type(),
          amount: pos_integer(),
          party_a: String.t(),
          party_b: String.t(),
          remarks: String.t(),
          account_reference: String.t() | nil,
          queue_timeout_url: String.t(),
          result_url: String.t()
        }

  defstruct [
    :initiator,
    :security_credential,
    :command_id,
    :sender_identifier_type,
    :receiver_identifier_type,
    :amount,
    :party_a,
    :party_b,
    :remarks,
    :queue_timeout_url,
    :result_url,
    account_reference: nil
  ]

  @required [
    :initiator,
    :security_credential,
    :command_id,
    :sender_identifier_type,
    :receiver_identifier_type,
    :amount,
    :party_a,
    :party_b,
    :remarks,
    :queue_timeout_url,
    :result_url
  ]

  @valid_command_ids ~w[
    BusinessPayBill
    BusinessBuyGoods
    DisburseFundsToBusiness
    BusinessToBusinessTransfer
    BusinessTransferFromMMFToUtility
    BusinessTransferFromUtilityToMMF
    MerchantToMerchantTransfer
    MerchantTransferFromMerchantToWorking
    MerchantServicesMMFAccountTransfer
    AgencyFloatAdvance
  ]
  @valid_identifier_types [2, 4]

  @spec new(map()) ::
          {:ok, t()}
          | {:error, :invalid_request,
             [
               atom()
               | {:command_id, String.t()}
               | {:sender_identifier_type, String.t()}
               | {:receiver_identifier_type, String.t()}
             ]}
  def new(params) when is_map(params) do
    params = normalize_keys(params)
    missing = Enum.filter(@required, fn key -> is_nil(params[key]) end)

    cond do
      missing != [] ->
        {:error, :invalid_request, missing}

      params[:command_id] not in @valid_command_ids ->
        {:error, :invalid_request,
         [
           {:command_id,
            "must be one of: BusinessPayBill, BusinessBuyGoods, DisburseFundsToBusiness, BusinessToBusinessTransfer, BusinessTransferFromMMFToUtility, BusinessTransferFromUtilityToMMF, MerchantToMerchantTransfer, MerchantTransferFromMerchantToWorking, MerchantServicesMMFAccountTransfer or AgencyFloatAdvance"}
         ]}

      params[:sender_identifier_type] not in @valid_identifier_types ->
        {:error, :invalid_request, [{:sender_identifier_type, "must be 2 or 4"}]}

      params[:receiver_identifier_type] not in @valid_identifier_types ->
        {:error, :invalid_request, [{:receiver_identifier_type, "must be 2 or 4"}]}

      true ->
        {:ok,
         %__MODULE__{
           initiator: params[:initiator],
           security_credential: params[:security_credential],
           command_id: params[:command_id],
           sender_identifier_type: params[:sender_identifier_type],
           receiver_identifier_type: params[:receiver_identifier_type],
           amount: params[:amount],
           party_a: params[:party_a],
           party_b: params[:party_b],
           remarks: params[:remarks],
           account_reference: params[:account_reference],
           queue_timeout_url: params[:queue_timeout_url],
           result_url: params[:result_url]
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
