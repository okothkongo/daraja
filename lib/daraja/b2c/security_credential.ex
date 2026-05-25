defmodule Daraja.B2C.SecurityCredential do
  @moduledoc """
  Utilities for building B2C security credentials.

  Safaricom expects the initiator password encrypted with the portal-provided
  certificate/public key and Base64 encoded.
  """

  @type encrypt_error :: :invalid_public_key | :encryption_failed

  @doc """
  Encrypts a plaintext initiator password using the provided PEM certificate or
  PEM public key and returns a Base64 encoded security credential.
  """
  @spec encrypt(String.t(), String.t()) :: {:ok, String.t()} | {:error, encrypt_error()}
  def encrypt(password, pem) when is_binary(password) and is_binary(pem) do
    with {:ok, public_key} <- extract_public_key(pem),
         encrypted when is_binary(encrypted) <-
           :public_key.encrypt_public(password, public_key, rsa_padding: :rsa_pkcs1_padding) do
      {:ok, Base.encode64(encrypted)}
    else
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :encryption_failed}
  end

  defp extract_public_key(pem) do
    case :public_key.pem_decode(pem) do
      [] ->
        {:error, :invalid_public_key}

      [entry | _] ->
        decode_public_key_entry(entry)
    end
  rescue
    _ -> {:error, :invalid_public_key}
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
