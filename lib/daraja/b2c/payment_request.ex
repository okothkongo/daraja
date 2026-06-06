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

  ## security_credential

  `security_credential` accepts either a pre-encrypted Base64 string or a
  `{initiator_password, pem}` tuple. When a tuple is provided, encryption is
  handled internally via `Daraja.SecurityCredential.encrypt/2`:

      # Pre-encrypted (useful when you encrypt once at deploy time):
      %{security_credential: "base64-encoded-credential", ...}

      # Auto-encrypt (convenient for sandbox/dev):
      %{security_credential: {"my-initiator-password", File.read!("sandbox.cer")}, ...}

  The tuple form is sugar over calling `Daraja.SecurityCredential.encrypt/2`
  inside `PaymentRequest.new/1`. In production, prefer pre-encrypting with
  `Daraja.SecurityCredential.encrypt/2` and storing only the resulting Base64
  string — so plaintext passwords never live in application state at runtime.
  When a tuple is supplied via application env, it is encrypted as soon as
  the env fallback is read; the tuple nevertheless remains in
  `Application` env until you replace it with a pre-encrypted string.

  ## Application env fallbacks

  `initiator_name`, `security_credential`, `queue_timeout_url`, and `result_url`
  fall back to the `:daraja` application env when not supplied in params.
  `security_credential` can be a pre-encrypted string or a `{password, pem}` tuple
  in config; per-call params always take precedence:

      config :daraja,
        b2c_initiator_name: "testapi",
        b2c_security_credential: "base64-credential",
        b2c_queue_timeout_url: "https://example.com/b2c/timeout",
        b2c_result_url: "https://example.com/b2c/result"

      # Or in runtime.exs to read the cert file at boot:
      config :daraja,
        b2c_security_credential: {"my-initiator-password", File.read!("priv/sandbox.cer")}

  Per-call params always take precedence over env values, which is handy for
  multi-tenant callers that need to override defaults per request.
  """

  @type command_id :: String.t()
  @type security_credential_input :: String.t() | {String.t(), String.t()}

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
          {:ok, t()}
          | {:error, :invalid_request,
             [
               atom()
               | {:command_id, String.t()}
               | {:security_credential,
                  Daraja.SecurityCredential.encrypt_error() | :invalid_format}
             ]}
  def new(params) when is_map(params) do
    params =
      params
      |> normalize_keys()
      |> apply_env_fallbacks()

    with {:ok, params} <- resolve_security_credential(params),
         :ok <- validate_callback_urls(params) do
      missing = Enum.filter(@required, fn key -> is_nil(params[key]) end)

      cond do
        missing != [] ->
          {:error, :invalid_request, missing}

        params[:command_id] not in @valid_command_ids ->
          {:error, :invalid_request,
           [
             {:command_id,
              "must be \"SalaryPayment\", \"BusinessPayment\" or \"PromotionPayment\""}
           ]}

        match?({:error, _}, Daraja.RequestValidation.validate_amount(params[:amount])) ->
          {:error, :invalid_request,
           [elem(Daraja.RequestValidation.validate_amount(params[:amount]), 1)]}

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
  end

  defp resolve_security_credential(params) do
    case Daraja.SecurityCredential.resolve(params[:security_credential]) do
      {:ok, credential} -> {:ok, %{params | security_credential: credential}}
      {:error, reason} -> {:error, :invalid_request, [{:security_credential, reason}]}
    end
  end

  defp validate_callback_urls(params) do
    case Daraja.CallbackURL.validate_all(params, [:queue_timeout_url, :result_url]) do
      :ok -> :ok
      {:error, errors} -> {:error, :invalid_request, errors}
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
      env_value = env_value(field, env_key)

      Map.update(acc, field, env_value, fn
        nil -> env_value
        value -> value
      end)
    end)
  end

  defp env_value(:security_credential, env_key), do: resolve_env_credential(env_key)
  defp env_value(_field, env_key), do: Daraja.Config.get(env_key, nil)

  defp resolve_env_credential(env_key) do
    case Daraja.Config.get(env_key, nil) do
      {_password, _pem} = tuple ->
        case Daraja.SecurityCredential.resolve(tuple) do
          {:ok, credential} -> credential
          {:error, _} -> tuple
        end

      value ->
        value
    end
  end
end
