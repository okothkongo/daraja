defmodule Daraja.B2B.Response do
  @moduledoc """
  Response structs for the B2B Payment Request API.
  """

  defmodule Success do
    @moduledoc "Returned when Safaricom accepts a B2B payment request."

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
    @moduledoc "Returned when Safaricom rejects a B2B payment request."

    @type t :: %__MODULE__{
            request_id: String.t(),
            error_code: String.t(),
            error_message: String.t()
          }

    defstruct [:request_id, :error_code, :error_message]
  end

  @spec from_map(map()) :: Success.t() | Error.t()
  def from_map(%{"ConversationID" => _} = map) do
    %Success{
      conversation_id: map["ConversationID"],
      originator_conversation_id: map["OriginatorConversationID"],
      response_code: map["ResponseCode"],
      response_description: map["ResponseDescription"]
    }
  end

  def from_map(map) do
    %Error{
      request_id: map["requestId"],
      error_code: map["errorCode"],
      error_message: map["errorMessage"]
    }
  end
end
