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

  ## Application env fallbacks

  `initiator_name`, `security_credential`, `queue_timeout_url`, and `result_url`
  fall back to the `:daraja` application env when not supplied in params:

      config :daraja,
        b2c_initiator_name: "testapi",
        b2c_security_credential: "base64-credential",
        b2c_queue_timeout_url: "https://example.com/b2c/timeout",
        b2c_result_url: "https://example.com/b2c/result"

  Per-call params always take precedence over env values, which is handy for
  multi-tenant callers that need to override defaults per request.
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
  @env_fallbacks %{
    initiator_name: :b2c_initiator_name,
    security_credential: :b2c_security_credential,
    queue_timeout_url: :b2c_queue_timeout_url,
    result_url: :b2c_result_url
  }

  @spec new(map()) ::
          {:ok, t()} | {:error, :invalid_request, [atom() | {:command_id, String.t()}]}
  def new(params) when is_map(params) do
    params =
      params
      |> normalize_keys()
      |> apply_env_fallbacks()

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

  defp apply_env_fallbacks(params) do
    Enum.reduce(@env_fallbacks, params, fn {field, env_key}, acc ->
      Map.update(acc, field, Daraja.Config.get(env_key, nil), fn
        nil -> Daraja.Config.get(env_key, nil)
        value -> value
      end)
    end)
  end
end
