defmodule Daraja.ClientTest do
  use ExUnit.Case, async: false

  alias Daraja.Client

  @app_env_keys [
    :consumer_key,
    :consumer_secret,
    :business_short_code,
    :passkey,
    :callback_url,
    :environment
  ]

  setup do
    saved = Map.new(@app_env_keys, fn key -> {key, Application.get_env(:daraja, key)} end)

    Enum.each(@app_env_keys, &Application.delete_env(:daraja, &1))

    on_exit(fn ->
      Enum.each(@app_env_keys, fn key ->
        case Map.fetch!(saved, key) do
          nil -> Application.delete_env(:daraja, key)
          value -> Application.put_env(:daraja, key, value)
        end
      end)
    end)

    :ok
  end

  describe "new/1" do
    test "raises when consumer_key is missing from both opts and app env" do
      assert_raise RuntimeError, ~r/:consumer_key/, fn ->
        Client.new(consumer_secret: "secret")
      end
    end

    test "raises when consumer_secret is missing from both opts and app env" do
      Application.put_env(:daraja, :consumer_key, "from_env")

      assert_raise RuntimeError, ~r/:consumer_secret/, fn -> Client.new() end
    end

    test "reads required fields from the application environment" do
      Application.put_env(:daraja, :consumer_key, "env_key")
      Application.put_env(:daraja, :consumer_secret, "env_secret")

      client = Client.new()
      assert client.consumer_key == "env_key"
      assert client.consumer_secret == "env_secret"
    end

    test "opts override application environment for every field" do
      Application.put_env(:daraja, :consumer_key, "env_key")
      Application.put_env(:daraja, :consumer_secret, "env_secret")
      Application.put_env(:daraja, :business_short_code, "env_shortcode")
      Application.put_env(:daraja, :passkey, "env_passkey")
      Application.put_env(:daraja, :callback_url, "https://env.example.com/cb")
      Application.put_env(:daraja, :environment, :production)

      client =
        Client.new(
          consumer_key: "opt_key",
          consumer_secret: "opt_secret",
          business_short_code: "opt_shortcode",
          passkey: "opt_passkey",
          callback_url: "https://opt.example.com/cb",
          environment: :sandbox
        )

      assert client.consumer_key == "opt_key"
      assert client.consumer_secret == "opt_secret"
      assert client.business_short_code == "opt_shortcode"
      assert client.passkey == "opt_passkey"
      assert client.callback_url == "https://opt.example.com/cb"
      assert client.environment == :sandbox
    end

    test "leaves optional fields as nil when neither opts nor app env supply them" do
      client = Client.new(consumer_key: "k", consumer_secret: "s")
      assert client.business_short_code == nil
      assert client.passkey == nil
      assert client.callback_url == nil
    end

    test "environment defaults to :sandbox when nothing is supplied" do
      client = Client.new(consumer_key: "k", consumer_secret: "s")
      assert client.environment == :sandbox
    end
  end

  describe "Inspect" do
    test "redacts consumer_secret and passkey" do
      client =
        Client.new(
          consumer_key: "my_consumer_key",
          consumer_secret: "my_consumer_secret",
          passkey: "my_passkey"
        )

      inspected = inspect(client)

      assert inspected =~ "my_consumer_key"
      refute inspected =~ "my_consumer_secret"
      refute inspected =~ "my_passkey"
      assert inspected =~ "consumer_secret: \"[REDACTED]\""
      assert inspected =~ "passkey: \"[REDACTED]\""
    end

    test "shows nil passkey without redaction placeholder" do
      client = Client.new(consumer_key: "k", consumer_secret: "s")

      inspected = inspect(client)

      assert inspected =~ "passkey: nil"
      assert inspected =~ "consumer_secret: \"[REDACTED]\""
    end
  end

  describe "base_url/1" do
    test "returns the sandbox URL for :sandbox" do
      client = Client.new(consumer_key: "k", consumer_secret: "s", environment: :sandbox)
      assert Client.base_url(client) == "https://sandbox.safaricom.co.ke"
    end

    test "returns the production URL for :production" do
      client = Client.new(consumer_key: "k", consumer_secret: "s", environment: :production)
      assert Client.base_url(client) == "https://api.safaricom.co.ke"
    end

    test "defaults to the sandbox URL when environment is unset" do
      client = Client.new(consumer_key: "k", consumer_secret: "s")
      assert Client.base_url(client) == "https://sandbox.safaricom.co.ke"
    end
  end
end
