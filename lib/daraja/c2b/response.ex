defmodule Daraja.C2B.Response do
  @moduledoc """
  Response structs for the C2B Register URL and Simulate APIs.
  """

  defmodule Success do
    @moduledoc "Returned when Safaricom successfully accepts a C2B request."

    @type t :: %__MODULE__{
            originator_conversation_id: String.t(),
            response_code: String.t(),
            response_description: String.t()
          }

    defstruct [
      :originator_conversation_id,
      :response_code,
      :response_description
    ]
  end

  defmodule Error do
    @moduledoc "Returned when Safaricom rejects a C2B request."

    @type t :: %__MODULE__{
            request_id: String.t(),
            error_code: String.t(),
            error_message: String.t()
          }

    defstruct [:request_id, :error_code, :error_message]
  end

  @doc """
  Parses a raw response map into a `Success` or `Error` struct.

  Note: Safaricom's API uses the misspelled key `OriginatorCoversationID`
  (missing the second 'n'). Both spellings are handled here for resilience.
  """
  alias Daraja.ResponseCode

  @spec from_map(map()) :: Success.t() | Error.t()
  def from_map(%{"ResponseCode" => _} = map) do
    if ResponseCode.success?(map) do
      %Success{
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
