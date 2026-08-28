defmodule RobineWake.AirPlayTest do
  use ExUnit.Case, async: false

  alias RobineWake.AirPlay

  @airplay_child RobineWake.AirPlay

  setup do
    original = %{
      enabled: Application.fetch_env!(:robine_wake, :airplay_enabled),
      network_state: Application.get_env(:robine_wake, :host_network_state, :available),
      restart_delay: Application.fetch_env!(:robine_wake, :airplay_restart_delay_ms)
    }

    on_exit(fn ->
      :ok = Supervisor.terminate_child(RobineWake.Supervisor, @airplay_child)
      Application.put_env(:robine_wake, :airplay_enabled, original.enabled)
      Application.put_env(:robine_wake, :host_network_state, original.network_state)
      Application.put_env(:robine_wake, :airplay_restart_delay_ms, original.restart_delay)
      {:ok, _pid} = Supervisor.restart_child(RobineWake.Supervisor, @airplay_child)
    end)

    :ok = Supervisor.terminate_child(RobineWake.Supervisor, @airplay_child)
    Application.put_env(:robine_wake, :airplay_enabled, true)
    Application.put_env(:robine_wake, :host_network_state, :unavailable)
    Application.put_env(:robine_wake, :airplay_restart_delay_ms, 10)
    {:ok, _pid} = Supervisor.restart_child(RobineWake.Supervisor, @airplay_child)

    :ok
  end

  test "waits for the network before starting the receiver" do
    assert_eventually(fn ->
      match?(%{state: :starting, reason: :network_unavailable}, AirPlay.status())
    end)

    Application.put_env(:robine_wake, :host_network_state, :available)

    assert_eventually(fn ->
      match?(%{state: :starting, reason: :executable_not_found}, AirPlay.status())
    end)
  end

  defp assert_eventually(assertion, attempts \\ 50)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      assert true
    else
      Process.sleep(10)
      assert_eventually(assertion, attempts - 1)
    end
  end

  defp assert_eventually(_assertion, 0), do: flunk("condition was not met before timeout")
end
