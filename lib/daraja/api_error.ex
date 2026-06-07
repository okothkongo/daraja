defmodule Daraja.APIError do
  @moduledoc """
  Structured error for `:auth_failed`, `:http_error`, and unparsed `:request_failed`
  outcomes.

  Safaricom JSON error envelopes are parsed into `request_id`, `error_code`, and
  `error_message`. Non-JSON bodies are summarized without including the raw
  response in `inspect/1`, so callers can log `inspect(error)` safely at `:info`
  or above. Use `raw_body/1` when the unparsed body is needed for debugging.

  ## Accepted JSON keys

  Fields are read from the first matching key in each group:

    * `request_id` — `"requestId"`, `"requestid"`
    * `error_code` — `"errorCode"`, `"error"` (OAuth-style)
    * `error_message` — `"errorMessage"`, `"error_description"` (OAuth-style)

  Only non-empty binary values are accepted; falsy values (`false`, `0`, `""`) are
  treated as absent. A decoded JSON object must contain at least one of the keys
  above or it is treated as an unrecognized error body.
  """

  @enforce_keys []
  defstruct [:request_id, :error_code, :error_message, :status, :raw_body]

  @type status :: pos_integer() | :unknown

  @type t :: %__MODULE__{
          request_id: String.t() | nil,
          error_code: String.t() | nil,
          error_message: String.t() | nil,
          status: status(),
          raw_body: binary() | nil
        }

  @request_id_keys ~w(requestId requestid)
  @error_code_keys ~w(errorCode error)
  @error_message_keys ~w(errorMessage error_description)
  @shape_keys @request_id_keys ++ @error_code_keys ++ @error_message_keys
  @max_raw_body 512

  @doc """
  Returns the unparsed response body when JSON decoding failed or the payload
  was not a recognized error envelope.
  """
  @spec raw_body(t()) :: binary() | nil
  def raw_body(%__MODULE__{raw_body: raw_body}), do: raw_body

  @spec from_body(binary(), keyword()) :: t()
  def from_body(body, opts \\ []) when is_binary(body) do
    status = normalize_status(opts)

    case JSON.decode(body) do
      {:ok, map} when is_map(map) ->
        if error_shape?(map) do
          %__MODULE__{
            request_id: string_field(map, @request_id_keys),
            error_code: string_field(map, @error_code_keys),
            error_message: string_field(map, @error_message_keys),
            status: status
          }
        else
          %__MODULE__{
            error_message: "unrecognized JSON error response",
            status: status,
            raw_body: capture_raw_body(body)
          }
        end

      _ ->
        %__MODULE__{
          error_message: summarize(body),
          status: status,
          raw_body: capture_raw_body(body)
        }
    end
  end

  defp normalize_status(opts) do
    case Keyword.get(opts, :status) do
      status when is_integer(status) and status > 0 -> status
      _ -> :unknown
    end
  end

  defp error_shape?(map) do
    Enum.any?(@shape_keys, &Map.has_key?(map, &1))
  end

  defp string_field(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(map, key) do
        value when is_binary(value) ->
          case String.trim(value) do
            "" -> nil
            trimmed -> trimmed
          end

        _ ->
          nil
      end
    end)
  end

  defp summarize(body) do
    case String.trim(body) do
      "" -> "empty response"
      _ -> "non-JSON error response"
    end
  end

  defp capture_raw_body(body) do
    if byte_size(body) <= @max_raw_body do
      body
    else
      binary_part(body, 0, @max_raw_body) <> "..."
    end
  end
end

defimpl Inspect, for: Daraja.APIError do
  import Inspect.Algebra

  def inspect(error, opts) do
    fields = [
      request_id: error.request_id,
      error_code: error.error_code,
      error_message: error.error_message,
      status: error.status
    ]

    concat(["#Daraja.APIError<", to_doc(fields, opts), ">"])
  end
end
