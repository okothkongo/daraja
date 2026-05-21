defmodule Daraja.ConfigTest do
  use ExUnit.Case, async: false

  alias Daraja.Config

  setup do
    on_exit(fn ->
      Application.delete_env(:daraja, :environment)
      Application.delete_env(:daraja, :consumer_key)
    end)
  end

  describe "base_url/0" do
    test "returns sandbox URL by default" do
      Application.delete_env(:daraja, :environment)
      assert Config.base_url() == "https://sandbox.safaricom.co.ke"
    end

    test "returns sandbox URL when environment is :sandbox" do
      Application.put_env(:daraja, :environment, :sandbox)
      assert Config.base_url() == "https://sandbox.safaricom.co.ke"
    end

    test "returns production URL when environment is :production" do
      Application.put_env(:daraja, :environment, :production)
      assert Config.base_url() == "https://api.safaricom.co.ke"
    end
  end

  describe "get!/1" do
    test "returns value when key is set" do
      Application.put_env(:daraja, :consumer_key, "my_key")
      assert Config.get!(:consumer_key) == "my_key"
    end

    test "raises when key is missing" do
      Application.delete_env(:daraja, :consumer_key)
      assert_raise RuntimeError, ~r/:consumer_key/, fn -> Config.get!(:consumer_key) end
    end
  end
end
