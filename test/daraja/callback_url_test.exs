defmodule Daraja.CallbackURLTest do
  use ExUnit.Case, async: true

  alias Daraja.CallbackURL

  setup do
    on_exit(fn ->
      Application.delete_env(:daraja, :environment)
      Application.delete_env(:daraja, :validate_callback_urls)
      Application.delete_env(:daraja, :allowed_callback_hosts)
    end)

    :ok
  end

  test "accepts https URLs with a public host" do
    assert :ok = CallbackURL.validate("https://example.com/callback")
  end

  test "allows http in sandbox" do
    Application.put_env(:daraja, :environment, :sandbox)

    assert :ok = CallbackURL.validate("http://example.com/callback")
  end

  test "requires https in production" do
    Application.put_env(:daraja, :environment, :production)

    assert {:error, "must use https in production"} =
             CallbackURL.validate("http://example.com/callback")
  end

  test "rejects private IPv4 addresses" do
    assert {:error, "host must not be a private or metadata address"} =
             CallbackURL.validate("https://192.168.1.10/callback")

    assert {:error, "host must not be a private or metadata address"} =
             CallbackURL.validate("https://10.0.0.5/callback")

    assert {:error, "host must not be a private or metadata address"} =
             CallbackURL.validate("https://169.254.169.254/latest/meta-data")
  end

  test "rejects blocked hostnames" do
    assert {:error, "host is not allowed"} =
             CallbackURL.validate("https://localhost/callback")

    assert {:error, "host is not allowed"} =
             CallbackURL.validate("https://metadata.google.internal/computeMetadata/v1")
  end

  test "enforces allowed_callback_hosts when configured" do
    Application.put_env(:daraja, :allowed_callback_hosts, ["myapp.com"])

    assert :ok = CallbackURL.validate("https://api.myapp.com/callback")
    assert :ok = CallbackURL.validate("https://myapp.com/callback")

    assert {:error, "host is not in the allowed callback hosts list"} =
             CallbackURL.validate("https://evil.com/callback")
  end

  test "skips validation in sandbox when validate_callback_urls is false" do
    Application.put_env(:daraja, :environment, :sandbox)
    Application.put_env(:daraja, :validate_callback_urls, false)

    assert :ok = CallbackURL.validate("http://192.168.0.1/callback")
  end

  test "still validates in production when validate_callback_urls is false" do
    Application.put_env(:daraja, :environment, :production)
    Application.put_env(:daraja, :validate_callback_urls, false)

    assert {:error, "must use https in production"} =
             CallbackURL.validate("http://example.com/callback")
  end

  test "validate_all returns field-specific errors" do
    params = %{
      queue_timeout_url: "https://192.168.0.1/timeout",
      result_url: "https://example.com/result"
    }

    assert {:error, [{:queue_timeout_url, "host must not be a private or metadata address"}]} =
             CallbackURL.validate_all(params, [:queue_timeout_url, :result_url])
  end
end
