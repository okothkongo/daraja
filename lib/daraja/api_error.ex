defmodule Daraja.APIError do
  @moduledoc """
  Structured error for `:auth_failed`, `:http_error`, and unparsed `:request_failed`
  outcomes.

  Safaricom JSON error envelopes are parsed into `request_id`, `error_code`, and
  `error_message`. Non-JSON bodies are summarized without including the raw
  response, so callers can log `inspect(error)` safely at `:info` or above.
  """

  @enforce_keys []
  defstruct [:request_id, :error_code, :error_message, :status]

  @type t :: %__MODULE__{
          request_id: String.t() | nil,
          error_code: String.t() | nil,
          error_message: String.t() | nil,
          status: pos_integer() | nil
        }

  @spec from_body(binary(), keyword()) :: t()
  def from_body(body, opts \\ []) when is_binary(body) do
    status = Keyword.get(opts, :status)

    case JSON.decode(body) do
      {:ok, map} when is_map(map) ->
        %__MODULE__{
          request_id: map["requestId"],
          error_code: map["errorCode"] || map["error"],
          error_message: map["errorMessage"] || map["error_description"],
          status: status
        }

      _ ->
        %__MODULE__{
          error_message: summarize(body),
          status: status
        }
    end
  end

  defp summarize(body) do
    case String.trim(body) do
      "" -> "empty response"
      _ -> "non-JSON error response"
    end
  end
end
