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

  test "validate_msisdn/2 rejects local or malformed numbers" do
    assert {:error, {:phone_number, _}} = RequestValidation.validate_msisdn("0712345678")
    assert {:error, {:msisdn, _}} = RequestValidation.validate_msisdn("25471", :msisdn)
  end

  test "validate_msisdn/2 respects :msisdn_regex config" do
    Application.put_env(:daraja, :msisdn_regex, ~r/^\+254\d{9}$/)

    on_exit(fn -> Application.delete_env(:daraja, :msisdn_regex) end)

    assert :ok = RequestValidation.validate_msisdn("+254712345678")
    assert {:error, {:phone_number, _}} = RequestValidation.validate_msisdn("254712345678")
  end
end
