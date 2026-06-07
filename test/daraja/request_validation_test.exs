defmodule Daraja.RequestValidationTest do
  use ExUnit.Case, async: true

  alias Daraja.RequestValidation

  test "validate_amount/1 accepts positive integers" do
    assert :ok = RequestValidation.validate_amount(1)
    assert :ok = RequestValidation.validate_amount(100)
  end

  test "validate_amount/1 rejects non-positive or non-integer values" do
    assert {:error, {:amount, _}} = RequestValidation.validate_amount(0)
    assert {:error, {:amount, _}} = RequestValidation.validate_amount(-5)
    assert {:error, {:amount, _}} = RequestValidation.validate_amount("100")
  end

  test "validate_msisdn/2 accepts 254XXXXXXXXX by default" do
    assert :ok = RequestValidation.validate_msisdn("254712345678")
  end

  test "validate_msisdn/2 rejects malformed numbers" do
    assert {:error, {:msisdn, _}} = RequestValidation.validate_msisdn("25471", :msisdn)
  end

  test "normalize_msisdn/1 converts local 07XXXXXXXX to 254XXXXXXXXX" do
    assert RequestValidation.normalize_msisdn("0712345678") == "254712345678"
    assert RequestValidation.normalize_msisdn("+254712345678") == "254712345678"
    assert RequestValidation.normalize_msisdn("254712345678") == "254712345678"
  end

  test "validate_msisdn/2 accepts normalized local numbers with default regex" do
    assert :ok = RequestValidation.validate_msisdn("0712345678")
  end

  test "coerce_msisdn/2 returns normalized MSISDN" do
    assert {:ok, "254712345678"} = RequestValidation.coerce_msisdn("0712345678")
  end

  test "validate_transaction_desc/1 accepts nil and strings up to 13 characters" do
    assert :ok = RequestValidation.validate_transaction_desc(nil)
    assert :ok = RequestValidation.validate_transaction_desc("Payment")
    assert :ok = RequestValidation.validate_transaction_desc(String.duplicate("a", 13))
  end

  test "validate_transaction_desc/1 rejects strings longer than 13 characters" do
    assert {:error, {:transaction_desc, _}} =
             RequestValidation.validate_transaction_desc(String.duplicate("a", 14))
  end

  test "normalize_msisdn/1 returns non-binary values unchanged" do
    assert RequestValidation.normalize_msisdn(123) == 123
    assert RequestValidation.normalize_msisdn(nil) == nil
  end

  test "validate_transaction_desc/1 rejects non-string values" do
    assert {:error, {:transaction_desc, msg}} = RequestValidation.validate_transaction_desc(123)
    assert msg =~ "must be a string"
  end

  defp restore_msisdn_regex!(nil), do: Application.delete_env(:daraja, :msisdn_regex)
  defp restore_msisdn_regex!(regex), do: Application.put_env(:daraja, :msisdn_regex, regex)

  test "validate_msisdn_with_regex/4 respects custom regex without normalizing" do
    regex = ~r/^\+254\d{9}$/

    assert :ok =
             RequestValidation.validate_msisdn_with_regex(
               "+254712345678",
               :phone_number,
               regex,
               false
             )

    assert {:error, {:phone_number, _}} =
             RequestValidation.validate_msisdn_with_regex(
               "254712345678",
               :phone_number,
               regex,
               false
             )
  end

  test "validate_msisdn/2 uses configured :msisdn_regex without normalizing" do
    previous = Application.get_env(:daraja, :msisdn_regex)

    try do
      Application.put_env(:daraja, :msisdn_regex, ~r/^\+254\d{9}$/)

      assert :ok = RequestValidation.validate_msisdn("+254712345678")
      assert {:error, {:phone_number, _}} = RequestValidation.validate_msisdn("254712345678")
    after
      restore_msisdn_regex!(previous)
    end
  end
end
