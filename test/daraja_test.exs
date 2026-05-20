defmodule DarajaTest do
  use ExUnit.Case
  doctest Daraja

  test "greets the world" do
    assert Daraja.hello() == :world
  end
end
