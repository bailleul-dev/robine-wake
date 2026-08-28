defmodule RobineWake.UpdatePolicyTest do
  use ExUnit.Case, async: true

  alias RobineWake.UpdatePolicy

  test "requires a public key, an idle session, and a safe alarm window" do
    now = ~U[2026-01-15 06:00:00Z]

    assert {:error, :signing_key_unavailable} = UpdatePolicy.allowed?(now, nil, [], false)

    assert {:error, :wake_session_active} =
             UpdatePolicy.allowed?(now, %{id: "active"}, [], true)

    assert {:error, :alarm_critical_window} =
             UpdatePolicy.allowed?(now, nil, [DateTime.add(now, 10, :minute)], true)

    assert :ok = UpdatePolicy.allowed?(now, nil, [DateTime.add(now, 16, :minute)], true)
  end

  test "host reports signed update transport without attempting an installation" do
    assert {:error, :host_target} = UpdatePolicy.precheck()

    assert %{
             state: :available,
             installable: false,
             reason: :host_target,
             signature: :ed25519_required,
             public_key_present: true
           } = UpdatePolicy.status()
  end
end
