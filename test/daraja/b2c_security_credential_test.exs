defmodule Daraja.B2CSecurityCredentialTest do
  use ExUnit.Case, async: true

  alias Daraja.B2C.SecurityCredential

  test "encrypts plaintext password with RSA public key PEM" do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    public_key = {:RSAPublicKey, elem(private_key, 2), elem(private_key, 3)}

    public_pem =
      :public_key.pem_encode([
        :public_key.pem_entry_encode(:RSAPublicKey, public_key)
      ])

    assert {:ok, credential} = SecurityCredential.encrypt("my-initiator-password", public_pem)
    assert is_binary(credential)

    decrypted =
      credential
      |> Base.decode64!()
      |> :public_key.decrypt_private(private_key, rsa_padding: :rsa_pkcs1_padding)

    assert decrypted == "my-initiator-password"
  end

  test "returns invalid_public_key for invalid pem" do
    assert {:error, :invalid_public_key} = SecurityCredential.encrypt("password", "not-a-pem")
  end
end
