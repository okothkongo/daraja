defmodule Daraja.C2B.RegisterUrlRequest do
  @moduledoc """
  Input struct for a C2B Register URL request.

  Required fields: `short_code`, `response_type`, `confirmation_url`, `validation_url`.

  `response_type` must be either `"Completed"` or `"Cancelled"` (sentence case).
  This determines what M-PESA does when the validation URL is unreachable:
  - `"Completed"` — M-PESA automatically completes the transaction.
  - `"Cancelled"` — M-PESA automatically cancels the transaction.
  """

  @type t :: %__MODULE__{
          short_code: String.t(),
          response_type: String.t(),
          confirmation_url: String.t(),
          validation_url: String.t()
        }

  defstruct [:short_code, :response_type, :confirmation_url, :validation_url]

  @required [:short_code, :response_type, :confirmation_url, :validation_url]
  @valid_response_types ~w[Completed Cancelled]

  @spec new(map()) ::
          {:ok, t()}
          | {:error, :invalid_request,
             [atom() | {:response_type, String.t()} | {atom(), String.t()}]}
  def new(params) when is_map(params) do
    params = normalize_keys(params)
    missing = Enum.filter(@required, fn key -> is_nil(params[key]) end)

    cond do
      missing != [] ->
        {:error, :invalid_request, missing}

      params[:response_type] not in @valid_response_types ->
        {:error, :invalid_request, [{:response_type, "must be \"Completed\" or \"Cancelled\""}]}

      true ->
        case Daraja.CallbackURL.validate_all(params, [:confirmation_url, :validation_url]) do
          :ok ->
            {:ok,
             %__MODULE__{
               short_code: params[:short_code],
               response_type: params[:response_type],
               confirmation_url: params[:confirmation_url],
               validation_url: params[:validation_url]
             }}

          {:error, errors} ->
            {:error, :invalid_request, errors}
        end
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
