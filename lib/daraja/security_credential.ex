defmodule Daraja.SecurityCredential do
  @moduledoc """
  Utilities for building Daraja security credentials.

  Safaricom expects the initiator password encrypted with the portal-provided
  certificate/public key and Base64 encoded. Used by B2B and B2C `PaymentRequest`
  modules; also callable directly.

  Download the encryption certificate from the
  [Daraja developer portal](https://developer.safaricom.co.ke) only.

  ## Pinning trusted certificates

  When `:security_credential_pins` is set, PEM inputs must match a configured
  SPKI SHA-256 fingerprint before encryption:

      config :daraja,
        environment: :production,
        security_credential_pins: ["yGsAE85gJh3satQK/3DRqZCjovsVGOqmUQ22wXvoIko"]

  Generate a pin from a portal certificate with `spki_fingerprint/1`.

  Pinning is skipped when the list is empty. In `:sandbox`, set
  `:enforce_security_credential_pins` to `false` to disable pinning during
  local development. Production always enforces when pins are configured.
  """

  @type encrypt_error :: :invalid_public_key | :encryption_failed | :untrusted_public_key

  @doc """
  Resolves a `security_credential` input to an encrypted Base64 string.

  Accepts:
  - A pre-encrypted Base64 string — returned as-is.
  - A `{password, pem}` tuple — encrypts using `encrypt/2`.
  - `nil` — returned as `{:ok, nil}` so the missing-field check in
    `PaymentRequest.new/1` can report it normally.
  - Any other value — returns `{:error, :invalid_format}`.
  """
  @spec resolve(String.t() | {String.t(), String.t()} | nil | term()) ::
          {:ok, String.t() | nil} | {:error, encrypt_error() | :invalid_format}
  def resolve(nil), do: {:ok, nil}
  def resolve(credential) when is_binary(credential), do: {:ok, credential}

  def resolve({password, pem}) when is_binary(password) and is_binary(pem),
    do: encrypt(password, pem)

  def resolve(_), do: {:error, :invalid_format}

  @doc """
  Encrypts a plaintext initiator password using the provided PEM certificate or
  PEM public key and returns a Base64 encoded security credential.
  """
  @spec encrypt(String.t(), String.t()) :: {:ok, String.t()} | {:error, encrypt_error()}
  def encrypt(password, pem) when is_binary(password) and is_binary(pem) do
    with {:ok, entry} <- extract_pem_entry(pem),
         :ok <- verify_trusted_pem(entry),
         {:ok, public_key} <- decode_public_key_entry(entry),
         encrypted when is_binary(encrypted) <-
           :public_key.encrypt_public(password, public_key, rsa_padding: :rsa_pkcs1_padding) do
      {:ok, Base.encode64(encrypted)}
    else
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :encryption_failed}
  end

  @doc """
  Returns the SHA-256 SPKI fingerprint (Base64) for a PEM certificate or public key.

  Use the value in `:security_credential_pins`.
  """
  @spec spki_fingerprint(String.t()) :: {:ok, String.t()} | {:error, :invalid_public_key}
  def spki_fingerprint(pem) when is_binary(pem) do
    with {:ok, entry} <- extract_pem_entry(pem),
         hash when is_binary(hash) <- fingerprint(entry) do
      {:ok, hash}
    end
  end

  defp extract_pem_entry(pem) do
    case :public_key.pem_decode(pem) do
      [] -> {:error, :invalid_public_key}
      [entry | _] -> {:ok, entry}
    end
  rescue
    _ -> {:error, :invalid_public_key}
  end

  defp verify_trusted_pem(entry) do
    environment = Daraja.Config.get(:environment, :sandbox)
    pins = configured_pins(environment)

    cond do
      pins == [] ->
        :ok

      skip_pin_validation?(environment) ->
        :ok

      true ->
        case fingerprint(entry) do
          hash when is_binary(hash) ->
            if hash in pins, do: :ok, else: {:error, :untrusted_public_key}

          {:error, _} = error ->
            error
        end
    end
  end

  defp skip_pin_validation?(environment) do
    environment == :sandbox and
      Daraja.Config.get(:enforce_security_credential_pins, true) == false
  end

  defp configured_pins(environment) do
    case Daraja.Config.get(:security_credential_pins, []) do
      pins when is_list(pins) ->
        if Keyword.keyword?(pins) do
          pins |> Keyword.get(environment, []) |> List.wrap()
        else
          pins
        end

      _ ->
        []
    end
  end

  defp fingerprint(entry) do
    with {:ok, public_key} <- decode_public_key_entry(entry) do
      public_key
      |> spki_der_from_public_key()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode64(padding: false)
    end
  end

  defp spki_der_from_public_key(public_key) do
    {:SubjectPublicKeyInfo, der, _} =
      :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)

    der
  end

  defp decode_public_key_entry({:Certificate, der, _}) do
    cert = :public_key.pkix_decode_cert(der, :plain)
    subject_public_key_info = cert |> elem(1) |> elem(7)
    public_key_der = elem(subject_public_key_info, 2)
    {:ok, :public_key.der_decode(:RSAPublicKey, public_key_der)}
  rescue
    _ -> {:error, :invalid_public_key}
  end

  defp decode_public_key_entry({:SubjectPublicKeyInfo, _, _} = entry) do
    {:ok, :public_key.pem_entry_decode(entry)}
  rescue
    _ -> {:error, :invalid_public_key}
  end

  defp decode_public_key_entry({:RSAPublicKey, _, _} = entry) do
    {:ok, :public_key.pem_entry_decode(entry)}
  rescue
    _ -> {:error, :invalid_public_key}
  end

  defp decode_public_key_entry(_), do: {:error, :invalid_public_key}
end
