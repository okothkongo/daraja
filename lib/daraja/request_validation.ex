defmodule Daraja.RequestValidation do
  @moduledoc false

  @default_msisdn_regex ~r/^254\d{9}$/

  @spec validate_amount(term()) :: :ok | {:error, {:amount, String.t()}}
  def validate_amount(amount) when is_integer(amount) and amount > 0, do: :ok

  def validate_amount(_amount) do
    {:error, {:amount, "must be a positive integer"}}
  end

  @max_transaction_desc_length 13

  @spec normalize_msisdn(term()) :: term()
  def normalize_msisdn(msisdn) when is_binary(msisdn) do
    msisdn
    |> String.trim()
    |> String.trim_leading("+")
    |> case do
      "0" <> rest when byte_size(rest) == 9 -> "254" <> rest
      other -> other
    end
  end

  def normalize_msisdn(other), do: other

  @spec validate_msisdn(term(), atom()) :: :ok | {:error, {atom(), String.t()}}
  def validate_msisdn(msisdn, field \\ :phone_number) do
    regex = Application.get_env(:daraja, :msisdn_regex, @default_msisdn_regex)
    msisdn = if regex == @default_msisdn_regex, do: normalize_msisdn(msisdn), else: msisdn

    if is_binary(msisdn) and Regex.match?(regex, msisdn) do
      :ok
    else
      {:error,
       {field,
        "must be a Kenyan MSISDN in 254XXXXXXXXX format (override with :msisdn_regex config)"}}
    end
  end

  @spec coerce_msisdn(term(), atom()) :: {:ok, String.t()} | {:error, {atom(), String.t()}}
  def coerce_msisdn(msisdn, field \\ :phone_number) do
    regex = Application.get_env(:daraja, :msisdn_regex, @default_msisdn_regex)
    msisdn = if regex == @default_msisdn_regex, do: normalize_msisdn(msisdn), else: msisdn

    if is_binary(msisdn) and Regex.match?(regex, msisdn) do
      {:ok, msisdn}
    else
      {:error,
       {field,
        "must be a Kenyan MSISDN in 254XXXXXXXXX format (override with :msisdn_regex config)"}}
    end
  end

  @spec validate_transaction_desc(term()) :: :ok | {:error, {:transaction_desc, String.t()}}
  def validate_transaction_desc(nil), do: :ok

  def validate_transaction_desc(desc) when is_binary(desc) do
    if byte_size(desc) <= @max_transaction_desc_length do
      :ok
    else
      {:error, {:transaction_desc, "must be at most #{@max_transaction_desc_length} characters"}}
    end
  end

  def validate_transaction_desc(_desc) do
    {:error,
     {:transaction_desc, "must be a string of at most #{@max_transaction_desc_length} characters"}}
  end
end
