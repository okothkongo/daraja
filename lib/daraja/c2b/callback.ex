defmodule Daraja.C2B.Callback do
  @moduledoc """
  Helpers for parsing inbound C2B callback payloads posted by M-PESA to
  the merchant's registered validation and confirmation URLs.

  ## Validation flow

  When External Validation is enabled, M-PESA posts a validation request to
  your `ValidationURL` before completing a transaction. You must respond within
  ~8 seconds using `accept/0` or `reject/1`.

      # In your Phoenix controller or LiveView:
      payload = Jason.decode!(conn.body_params)
      callback = Daraja.C2B.Callback.from_map(payload)

      response =
        if valid_account?(callback.bill_ref_number) do
          Daraja.C2B.Callback.accept()
        else
          Daraja.C2B.Callback.reject("C2B00012")
        end

      json(conn, response)

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

  @valid_reject_codes ~w[C2B00011 C2B00012 C2B00013 C2B00014 C2B00015 C2B00016]

  @doc """
  Parses a raw callback map into a `Validation` or `Confirmation` struct.

  Validation requests have an empty `OrgAccountBalance`; confirmation requests
  carry the updated balance. Both share the same field layout, so they are
  distinguished by the presence or absence of an account balance value.
  """
  @spec from_map(map()) :: Validation.t() | Confirmation.t()
  def from_map(map) do
    fields = build_fields(map)

    if map["OrgAccountBalance"] == "" || is_nil(map["OrgAccountBalance"]) do
      struct(Validation, fields)
    else
      struct(Confirmation, fields)
    end
  end

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
  `"C2B00014"`, `"C2B00015"`, `"C2B00016"`. Defaults to `"C2B00016"` if an
  unrecognised code is supplied.

      Daraja.C2B.Callback.reject("C2B00012")
      #=> %{"ResultCode" => "C2B00012", "ResultDesc" => "Rejected"}
  """
  @spec reject(String.t()) :: %{String.t() => String.t()}
  def reject(result_code) when result_code in @valid_reject_codes do
    %{"ResultCode" => result_code, "ResultDesc" => "Rejected"}
  end

  def reject(_), do: %{"ResultCode" => "C2B00016", "ResultDesc" => "Rejected"}

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
