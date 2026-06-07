defmodule Daraja.B2C.Response do
  @moduledoc """
  Response structs for the B2C Payment Request API.
  """

  alias Daraja.ResponseCode

  defmodule Success do
    @moduledoc "Returned when Safaricom accepts a B2C payment request."

    @type t :: %__MODULE__{
            conversation_id: String.t(),
            originator_conversation_id: String.t(),
            response_code: String.t(),
            response_description: String.t()
          }

    defstruct [
      :conversation_id,
      :originator_conversation_id,
      :response_code,
      :response_description
    ]
  end

  defmodule Error do
    @moduledoc "Returned when Safaricom rejects a B2C payment request."

    @type t :: %__MODULE__{
            request_id: String.t(),
            error_code: String.t(),
            error_message: String.t()
          }

    defstruct [:request_id, :error_code, :error_message]
  end

  @doc """
  Parses a raw response map into a `Success` or `Error` struct.

  Note: Safaricom may return the misspelled key `OriginatorCoversationID`
  (missing the second 'n'). Both spellings are handled for resilience.
  """
  @spec from_map(map()) :: Success.t() | Error.t()
  def from_map(%{"ConversationID" => _} = map) do
    if ResponseCode.success?(map) do
      %Success{
        conversation_id: map["ConversationID"],
        originator_conversation_id:
          map["OriginatorCoversationID"] || map["OriginatorConversationID"],
        response_code: map["ResponseCode"],
        response_description: map["ResponseDescription"]
      }
    else
      response_code_error(map)
    end
  end

  def from_map(map) do
    %Error{
      request_id: map["requestId"],
      error_code: map["errorCode"],
      error_message: map["errorMessage"]
    }
  end

  defp response_code_error(map) do
    fields = ResponseCode.error_fields(map)

    %Error{
      request_id: map["requestId"],
      error_code: fields.error_code,
      error_message: fields.error_message
    }
  end
end
