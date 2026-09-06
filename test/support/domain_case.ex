defmodule RobineWake.DomainCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias RobineWake.Hue.Driver.Test, as: HueDriver

  using do
    quote do
      alias RobineWake.{Alarm, Audio, Camera, Clock, Hue, Scheduler, Settings, WakeSession}
    end
  end

  setup context do
    original_remote_dismiss = Application.fetch_env!(:robine_wake, :remote_dismiss_enabled)

    Application.put_env(
      :robine_wake,
      :remote_dismiss_enabled,
      Map.get(context, :remote_dismiss_enabled, true)
    )

    original_clock = Application.fetch_env!(:robine_wake, :clock)

    if pid = Process.whereis(RobineWake.Clock.Manual), do: Agent.stop(pid)

    {:ok, manual_clock} =
      Agent.start(fn -> %{utc: ~U[2026-01-15 06:00:00Z], monotonic_ms: 0} end,
        name: RobineWake.Clock.Manual
      )

    Application.put_env(:robine_wake, :clock, RobineWake.Clock.Manual)
    {:ok, _clock} = RobineWake.ClockQuality.confirm()
    :ok = RobineWake.Auth.clear_rate_limits()
    :ok = RobineWake.RemoteButton.reset()

    if RobineWake.WakeSession.active(), do: RobineWake.WakeSession.dismiss(:test_cleanup)
    :ok = RobineWake.Settings.reset()
    :ok = RobineWake.Hue.reset()
    :ok = HueDriver.reset()
    _ = RobineWake.Scheduler.refresh()

    if RobineWake.WakeSession.active() do
      RobineWake.WakeSession.dismiss(:test_cleanup)
    end

    :ok = RobineWake.Settings.reset()
    :ok = RobineWake.Hue.reset()
    _ = RobineWake.Scheduler.refresh()

    :ok = RobineWake.Camera.reset()
    :ok = RobineWake.EventLog.clear()

    on_exit(fn ->
      if RobineWake.WakeSession.active(), do: RobineWake.WakeSession.dismiss(:test_cleanup)
      Application.put_env(:robine_wake, :clock, original_clock)
      Application.put_env(:robine_wake, :remote_dismiss_enabled, original_remote_dismiss)
      if Process.alive?(manual_clock), do: Agent.stop(manual_clock)
    end)

    :ok
  end
end
