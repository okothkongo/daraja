defmodule Daraja.SecurityCredentialTest do
  use ExUnit.Case, async: true

  alias Daraja.SecurityCredential

  @cert_pem File.read!("test/support/fixtures/security_credential_cert.pem")
  @key_pem File.read!("test/support/fixtures/security_credential_key.pem")
  @fixture_pin "yGsAE85gJh3satQK/3DRqZCjovsVGOqmUQ22wXvoIko"

  setup do
    on_exit(fn ->
      Application.delete_env(:daraja, :security_credential_pins)
      Application.delete_env(:daraja, :enforce_security_credential_pins)
      Application.delete_env(:daraja, :environment)
    end)

    :ok
  end

  defp rsa_keypair(bits \\ 2048) do
    private_key = :public_key.generate_key({:rsa, bits, 65_537})
    public_key = {:RSAPublicKey, elem(private_key, 2), elem(private_key, 3)}
    {private_key, public_key}
  end

  test "encrypts plaintext password with RSA public key PEM" do
    {private_key, public_key} = rsa_keypair()

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

  test "encrypts using a SubjectPublicKeyInfo PEM public key" do
    {_private_key, public_key} = rsa_keypair()

    spki_pem =
      :public_key.pem_encode([
        :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)
      ])

    assert {:ok, credential} = SecurityCredential.encrypt("password", spki_pem)
    assert is_binary(credential)
  end

  test "encrypts using an X.509 certificate PEM" do
    assert {:ok, credential} = SecurityCredential.encrypt("my-initiator-password", @cert_pem)

    [key_entry] = :public_key.pem_decode(@key_pem)
    private_key = :public_key.pem_entry_decode(key_entry)

    decrypted =
      credential
      |> Base.decode64!()
      |> :public_key.decrypt_private(private_key, rsa_padding: :rsa_pkcs1_padding)

    assert decrypted == "my-initiator-password"
  end

  test "returns invalid_public_key for invalid pem" do
    assert {:error, :invalid_public_key} = SecurityCredential.encrypt("password", "not-a-pem")
  end

  test "returns invalid_public_key when PEM decoding raises" do
    # A PEM with a valid header but a non-base64 body makes :public_key.pem_decode/1
    # itself raise, which is caught and reported as :invalid_public_key.
    malformed_pem = "-----BEGIN PUBLIC KEY-----\n!!!notbase64!!!\n-----END PUBLIC KEY-----\n"

    assert {:error, :invalid_public_key} = SecurityCredential.encrypt("password", malformed_pem)
  end

  test "returns invalid_public_key for an unsupported PEM entry type" do
    {private_key, _public_key} = rsa_keypair()

    private_pem =
      :public_key.pem_encode([
        :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
      ])

    assert {:error, :invalid_public_key} = SecurityCredential.encrypt("password", private_pem)
  end

  test "returns invalid_public_key for a malformed certificate entry" do
    bad_cert_pem = :public_key.pem_encode([{:Certificate, <<1, 2, 3, 4>>, :not_encrypted}])

    assert {:error, :invalid_public_key} = SecurityCredential.encrypt("password", bad_cert_pem)
  end

  test "returns invalid_public_key for a malformed SubjectPublicKeyInfo entry" do
    {_private_key, public_key} = rsa_keypair()

    {:SubjectPublicKeyInfo, der, info} =
      :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)

    bad_pem = :public_key.pem_encode([{:SubjectPublicKeyInfo, binary_part(der, 0, 10), info}])

    assert {:error, :invalid_public_key} = SecurityCredential.encrypt("password", bad_pem)
  end

  test "returns invalid_public_key for a malformed RSAPublicKey entry" do
    {_private_key, public_key} = rsa_keypair()

    {:RSAPublicKey, der, info} = :public_key.pem_entry_encode(:RSAPublicKey, public_key)

    bad_pem = :public_key.pem_encode([{:RSAPublicKey, binary_part(der, 0, 10), info}])

    assert {:error, :invalid_public_key} = SecurityCredential.encrypt("password", bad_pem)
  end

  describe "resolve/1" do
    test "passes a binary credential through unchanged" do
      assert {:ok, "already-encrypted"} = SecurityCredential.resolve("already-encrypted")
    end

    test "rejects an empty binary credential" do
      assert {:error, :invalid_format} = SecurityCredential.resolve("")
    end

    test "passes nil through as {:ok, nil}" do
      assert {:ok, nil} = SecurityCredential.resolve(nil)
    end

    test "encrypts a {password, pem} tuple" do
      {_private_key, public_key} = rsa_keypair()

      public_pem =
        :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPublicKey, public_key)])

      assert {:ok, credential} = SecurityCredential.resolve({"password", public_pem})
      assert is_binary(credential)
      assert credential != "password"
    end

    test "caches encrypted tuple credentials" do
      {_private_key, public_key} = rsa_keypair()

      public_pem =
        :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPublicKey, public_key)])

      assert {:ok, first} = SecurityCredential.resolve({"password", public_pem})
      assert {:ok, second} = SecurityCredential.resolve({"password", public_pem})
      assert first == second
    end

    test "rejects tuple credentials in production when disabled" do
      Application.put_env(:daraja, :environment, :production)
      Application.put_env(:daraja, :allow_tuple_security_credential, false)

      assert {:error, :tuple_credentials_disabled} =
               SecurityCredential.resolve({"password", @cert_pem})
    end

    test "returns :invalid_public_key when pem in tuple is invalid" do
      assert {:error, :invalid_public_key} =
               SecurityCredential.resolve({"password", "not-a-pem"})
    end

    test "returns :invalid_format for an integer" do
      assert {:error, :invalid_format} = SecurityCredential.resolve(12_345)
    end

    test "returns :invalid_format for a bare atom" do
      assert {:error, :invalid_format} = SecurityCredential.resolve(:not_a_credential)
    end

    test "returns :invalid_format for a 3-tuple" do
      assert {:error, :invalid_format} = SecurityCredential.resolve({"a", "b", "c"})
    end
  end

  test "spki_fingerprint/1 returns Base64 SHA-256 of the SPKI" do
    assert {:ok, @fixture_pin} = SecurityCredential.spki_fingerprint(@cert_pem)
  end

  describe "certificate pinning" do
    test "accepts PEM when fingerprint is pinned" do
      Application.put_env(:daraja, :security_credential_pins, [@fixture_pin])

      assert {:ok, _} = SecurityCredential.encrypt("password", @cert_pem)
    end

    test "rejects PEM when fingerprint is not pinned" do
      Application.put_env(:daraja, :security_credential_pins, ["known-but-different-pin"])

      assert {:error, :untrusted_public_key} =
               SecurityCredential.encrypt("password", @cert_pem)
    end

    test "skips pinning when no pins are configured" do
      {_private_key, public_key} = rsa_keypair()

      public_pem =
        :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPublicKey, public_key)])

      assert {:ok, _} = SecurityCredential.encrypt("password", public_pem)
    end

    test "skips pinning in sandbox when enforce_security_credential_pins is false" do
      Application.put_env(:daraja, :environment, :sandbox)
      Application.put_env(:daraja, :enforce_security_credential_pins, false)
      Application.put_env(:daraja, :security_credential_pins, ["known-but-different-pin"])

      assert {:ok, _} = SecurityCredential.encrypt("password", @cert_pem)
    end

    test "enforces pinning in production even when enforce flag is false" do
      Application.put_env(:daraja, :environment, :production)
      Application.put_env(:daraja, :enforce_security_credential_pins, false)
      Application.put_env(:daraja, :security_credential_pins, ["known-but-different-pin"])

      assert {:error, :untrusted_public_key} =
               SecurityCredential.encrypt("password", @cert_pem)
    end

    test "supports environment-specific pin lists" do
      Application.put_env(:daraja, :environment, :sandbox)
      Application.put_env(:daraja, :security_credential_pins, sandbox: [@fixture_pin])

      assert {:ok, _} = SecurityCredential.encrypt("password", @cert_pem)
    end

    test "ignores non-list security_credential_pins config" do
      Application.put_env(:daraja, :security_credential_pins, "not-a-list")

      {_private_key, public_key} = rsa_keypair()

      public_pem =
        :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPublicKey, public_key)])

      assert {:ok, _} = SecurityCredential.encrypt("password", public_pem)
    end

    test "returns invalid_public_key when pinning is enabled and fingerprint fails" do
      Application.put_env(:daraja, :environment, :production)
      Application.put_env(:daraja, :security_credential_pins, [@fixture_pin])

      {_private_key, public_key} = rsa_keypair()

      {:SubjectPublicKeyInfo, der, info} =
        :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)

      bad_pem = :public_key.pem_encode([{:SubjectPublicKeyInfo, binary_part(der, 0, 10), info}])

      assert {:error, :invalid_public_key} = SecurityCredential.encrypt("password", bad_pem)
    end
  end

  test "returns encryption_failed when the password is too large for the key" do
    {_private_key, public_key} = rsa_keypair(512)

    public_pem =
      :public_key.pem_encode([
        :public_key.pem_entry_encode(:RSAPublicKey, public_key)
      ])

    # A 512-bit key cannot PKCS#1-encrypt a 100-byte payload; the underlying
    # :public_key.encrypt_public/3 raises and is converted to :encryption_failed.
    oversized_password = String.duplicate("x", 100)

    assert {:error, :encryption_failed} =
             SecurityCredential.encrypt(oversized_password, public_pem)
  end
end
