defmodule Daraja.ConfigTest do
  use ExUnit.Case, async: false

  alias Daraja.Config

  setup do
    on_exit(fn ->
      Application.delete_env(:daraja, :consumer_key)
      Application.delete_env(:daraja, :some_optional_key)
    end)
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

  describe "get/2" do
    test "returns the value when the key is set" do
      Application.put_env(:daraja, :some_optional_key, :present)
      assert Config.get(:some_optional_key, :fallback) == :present
    end

    test "returns the default when the key is missing" do
      Application.delete_env(:daraja, :some_optional_key)
      assert Config.get(:some_optional_key, :fallback) == :fallback
    end
  end
end
