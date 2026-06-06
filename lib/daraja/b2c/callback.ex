defmodule Daraja.B2C.Callback do
  @moduledoc """
  Helpers for parsing asynchronous B2C callback payloads posted to `ResultURL`.

  B2C transactions are asynchronous; this module parses successful and unsuccessful
  callback payloads into typed structs and provides helpers to extract
  `ResultParameters` values by key.

  Verify inbound requests with `Daraja.Callback.Security`, deduplicate on
  `originator_conversation_id` with `Daraja.Callback.Guard`, and use `parse/1`
  on untrusted input.
  """

  defmodule Result do
    @moduledoc "Parsed B2C callback result payload."

    @type result_parameter :: %{key: String.t(), value: term()}
    @type reference_item :: %{key: String.t(), value: term()} | nil

    @type t :: %__MODULE__{
            result_type: integer() | nil,
            result_code: String.t() | integer() | nil,
            result_desc: String.t() | nil,
            originator_conversation_id: String.t() | nil,
            conversation_id: String.t() | nil,
            transaction_id: String.t() | nil,
            result_parameters: [result_parameter()],
            result_parameters_map: %{optional(String.t()) => term()},
            reference_item: reference_item()
          }

    defstruct [
      :result_type,
      :result_code,
      :result_desc,
      :originator_conversation_id,
      :conversation_id,
      :transaction_id,
      result_parameters: [],
      result_parameters_map: %{},
      reference_item: nil
    ]
  end

  @doc """
  Parses a B2C callback payload map into a `%Result{}` struct.
  """
  @spec from_map(map()) :: Result.t()
  def from_map(%{"Result" => result_map}) when is_map(result_map) do
    parameters = extract_result_parameters(result_map)
    reference_item = extract_reference_item(result_map)

    %Result{
      result_type: result_map["ResultType"],
      result_code: result_map["ResultCode"],
      result_desc: result_map["ResultDesc"],
      originator_conversation_id: result_map["OriginatorConversationID"],
      conversation_id: result_map["ConversationID"],
      transaction_id: result_map["TransactionID"],
      result_parameters: parameters,
      result_parameters_map: result_parameters_map(parameters),
      reference_item: reference_item
    }
  end

  @doc """
  Parses a B2C callback map from an untrusted HTTP request.
  """
  @spec parse(map()) :: {:ok, Result.t()} | {:error, :invalid_callback, String.t()}
  def parse(%{"Result" => result_map} = map) when is_map(result_map) do
    with :ok <- Daraja.Callback.Validate.present_string(result_map["OriginatorConversationID"]) do
      {:ok, from_map(map)}
    else
      {:error, _} -> {:error, :invalid_callback, "missing OriginatorConversationID"}
    end
  end

  def parse(_), do: {:error, :invalid_callback, "missing Result"}

  @doc """
  Builds the JSON response body used to acknowledge a B2C result callback.

  B2C callbacks are one-way notifications; M-PESA only needs the merchant to
  acknowledge receipt with `ResultCode: 0`.

      Daraja.B2C.Callback.accept()
      #=> %{"ResultCode" => 0, "ResultDesc" => "Success"}
  """
  @spec accept() :: %{String.t() => String.t() | non_neg_integer()}
  def accept, do: %{"ResultCode" => 0, "ResultDesc" => "Success"}

  @doc """
  Flattens `ResultParameters.ResultParameter` into `%{"Key" => value}`.
  """
  @spec result_parameters_map([map()] | map() | nil) :: %{optional(String.t()) => term()}
  def result_parameters_map(nil), do: %{}

  def result_parameters_map(%{"Result" => result_map}) when is_map(result_map) do
    result_map
    |> extract_result_parameters()
    |> result_parameters_map()
  end

  def result_parameters_map(parameters) when is_list(parameters) do
    Enum.reduce(parameters, %{}, fn
      %{key: key, value: value}, acc when is_binary(key) -> Map.put(acc, key, value)
      %{"Key" => key, "Value" => value}, acc when is_binary(key) -> Map.put(acc, key, value)
      _, acc -> acc
    end)
  end

  defp extract_result_parameters(result_map) do
    result_map
    |> get_in(["ResultParameters", "ResultParameter"])
    |> Daraja.Callback.Items.extract_key_value()
  end

  defp extract_reference_item(result_map) do
    result_map
    |> get_in(["ReferenceData", "ReferenceItem"])
    |> Daraja.Callback.Items.extract_key_value()
    |> List.first()
  end
end
