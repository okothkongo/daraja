defmodule Daraja.CallbackSecurityTest do
  use ExUnit.Case, async: true

  alias Daraja.Callback.Security

  defp restore_env(key, original) do
    if original,
      do: Application.put_env(:daraja, key, original),
      else: Application.delete_env(:daraja, key)
  end

  describe "allowlist defaults" do
    test "default_cidrs/0 includes 212, 213, and 214 subnets" do
      assert "196.201.212.0/24" in Security.default_cidrs()
      assert "196.201.213.0/24" in Security.default_cidrs()
      assert "196.201.214.0/24" in Security.default_cidrs()
    end

    test "known_callback_hosts/0 includes commonly published production IPs" do
      assert "196.201.212.127" in Security.known_callback_hosts()
      assert "196.201.214.200" in Security.known_callback_hosts()
    end

    test "allowlist/0 merges configured cidrs and hosts" do
      assert %{cidrs: cidrs, hosts: hosts} = Security.allowlist()
      assert is_list(cidrs)
      assert is_list(hosts)
      assert length(cidrs) >= 3
      assert length(hosts) >= 10
    end
  end

  describe "safaricom_ip?/2" do
    test "accepts addresses inside the default Safaricom ranges" do
      assert Security.safaricom_ip?({196, 201, 214, 10})
      assert Security.safaricom_ip?({196, 201, 213, 255})
      assert Security.safaricom_ip?({196, 201, 212, 127})
      assert Security.safaricom_ip?("196.201.214.1")
    end

    test "accepts explicit known callback hosts" do
      assert Security.safaricom_ip?("196.201.214.200")
      assert Security.safaricom_ip?({196, 201, 212, 69})
    end

    test "rejects addresses outside the default Safaricom ranges" do
      refute Security.safaricom_ip?({203, 0, 113, 1})
      refute Security.safaricom_ip?("203.0.113.1")
    end

    test "supports a plain CIDR list override" do
      assert Security.safaricom_ip?({10, 0, 0, 5}, ["10.0.0.0/8"])
      refute Security.safaricom_ip?({10, 0, 1, 5}, ["10.0.0.0/24"])
    end

    test "supports keyword overrides for cidrs and hosts" do
      assert Security.safaricom_ip?({192, 168, 1, 10}, hosts: ["192.168.1.10"])
      refute Security.safaricom_ip?({192, 168, 1, 11}, hosts: ["192.168.1.10"])
    end

    test "reads callback_cidrs from application config" do
      original_cidrs = Application.get_env(:daraja, :callback_cidrs)
      original_hosts = Application.get_env(:daraja, :callback_hosts)

      try do
        Application.put_env(:daraja, :callback_cidrs, ["10.0.0.0/8"])
        Application.put_env(:daraja, :callback_hosts, [])
        assert Security.safaricom_ip?({10, 1, 2, 3})
        refute Security.safaricom_ip?({196, 201, 214, 1})
      after
        restore_env(:callback_cidrs, original_cidrs)
        restore_env(:callback_hosts, original_hosts)
      end
    end

    test "reads callback_hosts from application config" do
      original_hosts = Application.get_env(:daraja, :callback_hosts)
      original_cidrs = Application.get_env(:daraja, :callback_cidrs)

      try do
        Application.put_env(:daraja, :callback_cidrs, [])
        Application.put_env(:daraja, :callback_hosts, ["203.0.113.50"])
        refute Security.safaricom_ip?({196, 201, 214, 200})
        assert Security.safaricom_ip?({203, 0, 113, 50})
      after
        restore_env(:callback_hosts, original_hosts)
        restore_env(:callback_cidrs, original_cidrs)
      end
    end
  end

  describe "shared_secret_valid?/2" do
    test "returns true for equal secrets" do
      assert Security.shared_secret_valid?("top-secret", "top-secret")
    end

    test "returns false for mismatched or empty secrets" do
      refute Security.shared_secret_valid?("top-secret", "other-secret")
      refute Security.shared_secret_valid?("", "top-secret")
      refute Security.shared_secret_valid?(nil, "top-secret")
    end
  end

  describe "verify/1" do
    test "skips checks when options are omitted" do
      assert :ok = Security.verify([])
    end

    test "enforces IP allowlisting when check_ip is true" do
      assert :ok =
               Security.verify(ip: {196, 201, 214, 1}, check_ip: true)

      assert :ok =
               Security.verify(ip: {196, 201, 212, 127}, check_ip: true)

      assert {:error, :untrusted_ip} =
               Security.verify(ip: {203, 0, 113, 1}, check_ip: true)
    end

    test "enforces shared secrets when configured" do
      assert :ok =
               Security.verify(shared_secret: "secret", provided_secret: "secret")

      assert {:error, :invalid_secret} =
               Security.verify(shared_secret: "secret", provided_secret: "wrong")
    end

    test "combines IP and shared-secret checks" do
      assert :ok =
               Security.verify(
                 ip: {196, 201, 214, 2},
                 check_ip: true,
                 shared_secret: "secret",
                 provided_secret: "secret"
               )

      assert {:error, :invalid_secret} =
               Security.verify(
                 ip: {196, 201, 214, 2},
                 check_ip: true,
                 shared_secret: "secret",
                 provided_secret: "wrong"
               )
    end

    test "honours per-request cidrs and hosts overrides" do
      assert :ok =
               Security.verify(
                 ip: {203, 0, 113, 9},
                 check_ip: true,
                 hosts: ["203.0.113.9"]
               )

      assert {:error, :untrusted_ip} =
               Security.verify(
                 ip: {203, 0, 113, 9},
                 check_ip: true,
                 cidrs: ["10.0.0.0/8"]
               )
    end

    test "returns invalid_ip for unparseable addresses when check_ip is true" do
      assert {:error, :invalid_ip} = Security.verify(ip: :not_an_ip, check_ip: true)
      refute Security.safaricom_ip?(:not_an_ip)
    end

    test "handles edge-case CIDR inputs" do
      assert Security.safaricom_ip?({10, 0, 0, 5}, ["10.0.0.0/0"])
      refute Security.safaricom_ip?({10, 0, 0, 5}, ["not-a-cidr"])
      refute Security.safaricom_ip?({10, 0, 0, 5}, ["999.999.999.999/24"])
      refute Security.safaricom_ip?({10, 0, 0, 5}, [nil])
      refute Security.safaricom_ip?("::1")
    end
  end
end
