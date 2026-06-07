defmodule Daraja.HTTPClient.ComplianceTest do
  use ExUnit.Case, async: true

  alias Daraja.HTTPClient.Compliance

  test "checklist/0 returns the minimum security requirements" do
    checklist = Compliance.checklist()

    assert length(checklist) == 4
    assert Enum.all?(checklist, &is_binary/1)
    assert "TLS peer verification enabled" in checklist
  end
end
