defmodule Daraja.B2C.PaymentRequest do
  @moduledoc """
  Input struct for a B2C payment request.

  Required fields:
  - `originator_conversation_id`
  - `initiator_name`
  - `security_credential`
  - `command_id`
  - `amount`
  - `party_a`
  - `party_b`
  - `remarks`
  - `queue_timeout_url`
  - `result_url`

  Optional fields:
  - `occasion`
  """

  @type command_id :: String.t()

  @type t :: %__MODULE__{
          originator_conversation_id: String.t(),
          initiator_name: String.t(),
          security_credential: String.t(),
          command_id: command_id(),
          amount: pos_integer(),
          party_a: String.t(),
          party_b: String.t(),
          remarks: String.t(),
          queue_timeout_url: String.t(),
          result_url: String.t(),
          occasion: String.t() | nil
        }

  defstruct [
    :originator_conversation_id,
    :initiator_name,
    :security_credential,
    :command_id,
    :amount,
    :party_a,
    :party_b,
    :remarks,
    :queue_timeout_url,
    :result_url,
    occasion: nil
  ]

  @required [
    :originator_conversation_id,
    :initiator_name,
    :security_credential,
    :command_id,
    :amount,
    :party_a,
    :party_b,
    :remarks,
    :queue_timeout_url,
    :result_url
  ]

  @valid_command_ids ~w[SalaryPayment BusinessPayment PromotionPayment]

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
         [
           {:command_id, "must be \"SalaryPayment\", \"BusinessPayment\" or \"PromotionPayment\""}
         ]}

      true ->
        {:ok,
         %__MODULE__{
           originator_conversation_id: params[:originator_conversation_id],
           initiator_name: params[:initiator_name],
           security_credential: params[:security_credential],
           command_id: params[:command_id],
           amount: params[:amount],
           party_a: params[:party_a],
           party_b: params[:party_b],
           remarks: params[:remarks],
           queue_timeout_url: params[:queue_timeout_url],
           result_url: params[:result_url],
           occasion: params[:occasion]
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
