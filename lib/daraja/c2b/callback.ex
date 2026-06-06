defmodule Daraja.C2B.Callback do
  @moduledoc """
  Helpers for parsing inbound C2B callback payloads posted by M-PESA to
  the merchant's registered validation and confirmation URLs.

  Daraja does **not** sign callbacks. Verify requests with
  `Daraja.Callback.Security`, deduplicate on `trans_id` with
  `Daraja.Callback.Guard`, and use `parse_validation/1` or
  `parse_confirmation/1` on untrusted input from the matching route.

  ## Validation flow

  When External Validation is enabled, M-PESA posts a validation request to
  your `ValidationURL` before completing a transaction. You must respond within
  ~8 seconds using `accept/0` or `reject/1`.

      with :ok <- Daraja.Callback.Security.verify(ip: conn.remote_ip, check_ip: true, ...),
           {:ok, callback} <- Daraja.C2B.Callback.parse_validation(payload) do
        response =
          if valid_account?(callback.bill_ref_number) do
            Daraja.C2B.Callback.accept()
          else
            Daraja.C2B.Callback.reject("C2B00012")
          end

        json(conn, response)
      end

  ## Confirmation flow

  After a successful transaction, M-PESA posts a confirmation to your
  `ConfirmationURL`. No response action is required — M-PESA has already
  completed the transaction.

  ## Result codes for rejection

  | Code       | Meaning                  |
  |------------|--------------------------|
  | `C2B00011` | Invalid MSISDN           |
  | `C2B00012` | Invalid Account Number   |
  | `C2B00013` | Invalid Amount           |
  | `C2B00014` | Invalid KYC Details      |
  | `C2B00015` | Invalid Short Code       |
  | `C2B00016` | Other Error              |
  """

  defmodule Validation do
    @moduledoc """
    Payload received at the `ValidationURL` before M-PESA completes a transaction.

    `org_account_balance` is blank for validation requests.
    """

    @type t :: %__MODULE__{
            transaction_type: String.t(),
            trans_id: String.t(),
            trans_time: String.t(),
            trans_amount: String.t(),
            business_short_code: String.t(),
            bill_ref_number: String.t(),
            invoice_number: String.t(),
            org_account_balance: String.t(),
            third_party_trans_id: String.t(),
            msisdn: String.t(),
            first_name: String.t(),
            middle_name: String.t(),
            last_name: String.t()
          }

    defstruct [
      :transaction_type,
      :trans_id,
      :trans_time,
      :trans_amount,
      :business_short_code,
      :bill_ref_number,
      :invoice_number,
      :org_account_balance,
      :third_party_trans_id,
      :msisdn,
      :first_name,
      :middle_name,
      :last_name
    ]
  end

  defmodule Confirmation do
    @moduledoc """
    Payload received at the `ConfirmationURL` after M-PESA completes a transaction.

    `org_account_balance` contains the new balance after payment.
    """

    @type t :: %__MODULE__{
            transaction_type: String.t(),
            trans_id: String.t(),
            trans_time: String.t(),
            trans_amount: String.t(),
            business_short_code: String.t(),
            bill_ref_number: String.t(),
            invoice_number: String.t(),
            org_account_balance: String.t(),
            third_party_trans_id: String.t(),
            msisdn: String.t(),
            first_name: String.t(),
            middle_name: String.t(),
            last_name: String.t()
          }

    defstruct [
      :transaction_type,
      :trans_id,
      :trans_time,
      :trans_amount,
      :business_short_code,
      :bill_ref_number,
      :invoice_number,
      :org_account_balance,
      :third_party_trans_id,
      :msisdn,
      :first_name,
      :middle_name,
      :last_name
    ]
  end

  @reject_descriptions %{
    "C2B00011" => "Invalid MSISDN",
    "C2B00012" => "Invalid Account Number",
    "C2B00013" => "Invalid Amount",
    "C2B00014" => "Invalid KYC Details",
    "C2B00015" => "Invalid Short Code",
    "C2B00016" => "Other Error"
  }

  @doc """
  Parses a raw callback map into a `%Validation{}` or `%Confirmation{}` struct.

  Pass `:validation` or `:confirmation` to match the HTTP route that received
  the callback. Do not infer message type from payload fields such as
  `OrgAccountBalance`.
  """
  @spec from_map(map(), :validation | :confirmation) :: Validation.t() | Confirmation.t()
  def from_map(map, :validation) when is_map(map), do: struct(Validation, build_fields(map))
  def from_map(map, :confirmation) when is_map(map), do: struct(Confirmation, build_fields(map))

  @doc """
  Parses a C2B validation callback map into a `%Validation{}` struct.

  Use on your `ValidationURL` route; do not infer validation vs confirmation
  from payload fields alone.
  """
  @spec from_validation_map(map()) :: Validation.t()
  def from_validation_map(map) when is_map(map), do: struct(Validation, build_fields(map))

  @doc """
  Parses a C2B confirmation callback map into a `%Confirmation{}` struct.

  Use on your `ConfirmationURL` route.
  """
  @spec from_confirmation_map(map()) :: Confirmation.t()
  def from_confirmation_map(map) when is_map(map), do: struct(Confirmation, build_fields(map))

  @doc """
  Parses a C2B callback map from an untrusted HTTP request.

  Returns `{:error, :ambiguous_callback, reason}` because validation and
  confirmation payloads share the same shape. Use `parse_validation/1` on your
  validation URL and `parse_confirmation/1` on your confirmation URL instead.
  """
  @spec parse(map()) ::
          {:error, :ambiguous_callback, String.t()} | {:error, :invalid_callback, String.t()}
  def parse(map) when is_map(map) do
    if c2b_callback?(map),
      do: {:error, :ambiguous_callback, ambiguous_callback_message()},
      else: parse_error(map)
  end

  def parse(_), do: {:error, :invalid_callback, "expected a map"}

  @doc """
  Parses a C2B validation callback from an untrusted HTTP request.

  Call from your `ValidationURL` route handler.
  """
  @spec parse_validation(map()) :: {:ok, Validation.t()} | {:error, :invalid_callback, String.t()}
  def parse_validation(map) when is_map(map) do
    if c2b_callback?(map), do: {:ok, from_validation_map(map)}, else: parse_error(map)
  end

  def parse_validation(_), do: {:error, :invalid_callback, "expected a map"}

  @doc """
  Parses a C2B confirmation callback from an untrusted HTTP request.

  Call from your `ConfirmationURL` route handler.
  """
  @spec parse_confirmation(map()) ::
          {:ok, Confirmation.t()} | {:error, :invalid_callback, String.t()}
  def parse_confirmation(map) when is_map(map) do
    if c2b_callback?(map), do: {:ok, from_confirmation_map(map)}, else: parse_error(map)
  end

  def parse_confirmation(_), do: {:error, :invalid_callback, "expected a map"}

  @doc """
  Returns `:validation` or `:confirmation` for a parsed C2B callback.
  """
  @spec kind(Validation.t() | Confirmation.t()) :: :validation | :confirmation
  def kind(%Validation{}), do: :validation
  def kind(%Confirmation{}), do: :confirmation

  @doc """
  Builds the JSON response body to accept a validation request.

      Daraja.C2B.Callback.accept()
      #=> %{"ResultCode" => "0", "ResultDesc" => "Accepted"}
  """
  @spec accept() :: %{String.t() => String.t()}
  def accept, do: %{"ResultCode" => "0", "ResultDesc" => "Accepted"}

  @doc """
  Builds the JSON response body to reject a validation request.

  `result_code` must be one of: `"C2B00011"`, `"C2B00012"`, `"C2B00013"`,
  `"C2B00014"`, `"C2B00015"`, `"C2B00016"`. Defaults to `"C2B00016"` ("Other
  Error") if an unrecognised code is supplied.

      Daraja.C2B.Callback.reject("C2B00012")
      #=> %{"ResultCode" => "C2B00012", "ResultDesc" => "Invalid Account Number"}
  """
  @spec reject(String.t()) :: %{String.t() => String.t()}
  def reject(result_code) when is_map_key(@reject_descriptions, result_code) do
    %{"ResultCode" => result_code, "ResultDesc" => Map.fetch!(@reject_descriptions, result_code)}
  end

  def reject(_), do: %{"ResultCode" => "C2B00016", "ResultDesc" => "Other Error"}

  defp c2b_callback?(map) do
    Map.has_key?(map, "TransID") and Map.has_key?(map, "TransAmount")
  end

  defp ambiguous_callback_message do
    "use parse_validation/1 or parse_confirmation/1 on the matching route"
  end

  defp parse_error(map) do
    missing =
      Enum.reject(
        ["TransID", "TransAmount", "BusinessShortCode", "MSISDN"],
        &Map.has_key?(map, &1)
      )

    {:error, :invalid_callback, "missing C2B fields: #{Enum.join(missing, ", ")}"}
  end

  defp build_fields(map) do
    [
      transaction_type: map["TransactionType"],
      trans_id: map["TransID"],
      trans_time: map["TransTime"],
      trans_amount: map["TransAmount"],
      business_short_code: map["BusinessShortCode"],
      bill_ref_number: map["BillRefNumber"],
      invoice_number: map["InvoiceNumber"],
      org_account_balance: map["OrgAccountBalance"],
      third_party_trans_id: map["ThirdPartyTransID"],
      msisdn: map["MSISDN"],
      first_name: map["FirstName"],
      middle_name: map["MiddleName"],
      last_name: map["LastName"]
    ]
  end
end
