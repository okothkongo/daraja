defmodule Daraja.RequestValidation do
  @moduledoc false

  @default_msisdn_regex ~r/^254\d{9}$/

  @spec validate_amount(term()) :: :ok | {:error, {:amount, String.t()}}
  def validate_amount(amount) when is_integer(amount) and amount > 0, do: :ok

  def validate_amount(_amount) do
    {:error, {:amount, "must be a positive integer"}}
  end

  @spec validate_msisdn(term(), atom()) :: :ok | {:error, {atom(), String.t()}}
  def validate_msisdn(msisdn, field \\ :phone_number) do
    regex = Application.get_env(:daraja, :msisdn_regex, @default_msisdn_regex)

    if is_binary(msisdn) and Regex.match?(regex, msisdn) do
      :ok
    else
      {:error,
       {field,
        "must be a Kenyan MSISDN in 254XXXXXXXXX format (override with :msisdn_regex config)"}}
    end
  end
end
