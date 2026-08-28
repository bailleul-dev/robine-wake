defmodule RobineWake.NetworkTest do
  use ExUnit.Case, async: false

  alias RobineWake.{Health, Network}

  test "network loss is visible but does not make the alarm system unhealthy" do
    previous = Application.get_env(:robine_wake, :host_network_state, :available)
    Application.put_env(:robine_wake, :host_network_state, :unavailable)
    on_exit(fn -> Application.put_env(:robine_wake, :host_network_state, previous) end)

    assert %{state: :degraded, reason: :network_unavailable} = Network.status()
    assert %{state: :degraded, network: %{reason: :network_unavailable}} = Health.snapshot()
  end
end
