defmodule RobineWake.WakeSessionTest do
  use RobineWake.DomainCase

  alias RobineWake.Hue.Driver.Test, as: HueDriver

  setup do
    previous_plateau = Application.fetch_env!(:robine_wake, :gentle_plateau_ms)
    Application.put_env(:robine_wake, :gentle_plateau_ms, 5_000)
    on_exit(fn -> Application.put_env(:robine_wake, :gentle_plateau_ms, previous_plateau) end)

    {:ok, alarm} =
      Settings.create_alarm(%{
        label: "Test",
        local_time: "07:00",
        days_of_week: [1, 2, 3, 4, 5, 6, 7],
        dismiss_policy: :either,
        strong_sound_id: "wake_up_call",
        volume_profile: %{start: 10, ceiling: 20, ramp_seconds: 10},
        snooze: %{enabled: true, duration_seconds: 60, maximum: 1}
      })

    %{alarm: alarm}
  end

  test "persists before audio, ramps volume, and dismisses manually", %{alarm: alarm} do
    assert {:ok, _pid} = WakeSession.start(alarm)
    assert %{state: :ringing, current_gain: 10} = WakeSession.active()
    assert [%{"state" => "ringing"}] = Settings.recent_sessions(1)

    Clock.Manual.advance(5_000)
    assert {:ok, %{current_gain: 15}} = WakeSession.tick_sync()

    assert {:ok, %{state: :dismissed, terminal_reason: :manual}} = WakeSession.dismiss(:manual)
    assert WakeSession.active() == nil
    assert %{active_session: nil} = Audio.status()
  end

  test "starts the sunrise at one percent and spans the full prewake duration", %{alarm: alarm} do
    assert {:ok, _status} = Hue.pair("192.168.1.42")

    assert {:ok, alarm} =
             Settings.update_alarm(alarm.id, %{
               revision: alarm.revision,
               prewake_seconds: 100,
               light_profile: %{
                 enabled: true,
                 target_id: "bedroom-group",
                 target_name: "Chambre",
                 start_brightness: 20,
                 end_brightness: 85,
                 ramp_seconds: 5
               }
             })

    assert {:ok, _pid} = WakeSession.start(alarm)
    assert eventually(fn -> length(HueDriver.commands()) >= 3 end)

    assert [
             {:get, "bedroom-group"},
             {:set, "bedroom-group", %{"dimming" => %{"brightness" => 1}}},
             {:set, "bedroom-group",
              %{
                "dimming" => %{"brightness" => 7.7},
                "dynamics" => %{"duration" => 18_000}
              }}
           ] = HueDriver.commands()

    assert {:ok, %{state: :dismissed}} = WakeSession.dismiss(:test)
  end

  test "switches from the gentle sound to the strong sound after the ramp", %{alarm: alarm} do
    assert {:ok, _pid} = WakeSession.start(alarm)
    assert %{audio_phase: :gentle} = WakeSession.active()

    Clock.Manual.advance(10_001)
    assert {:ok, %{audio_phase: :gentle, current_gain: 20}} = WakeSession.tick_sync()

    Clock.Manual.advance(5_000)
    assert {:ok, %{audio_phase: :strong, current_gain: 20}} = WakeSession.tick_sync()

    assert %{commands: commands} = Audio.status()
    assert Enum.any?(commands, &match?({:play, _, "wake_up_call"}, &1))
  end

  test "reapplies the ceiling after the gentle ramp already rounded up to it", %{alarm: alarm} do
    assert {:ok, _pid} = WakeSession.start(alarm)

    Clock.Manual.advance(9_500)
    assert {:ok, %{audio_phase: :gentle, current_gain: 20}} = WakeSession.tick_sync()

    Clock.Manual.advance(501)
    assert {:ok, %{audio_phase: :gentle, current_gain: 20}} = WakeSession.tick_sync()

    Clock.Manual.advance(5_000)
    assert {:ok, %{audio_phase: :strong, current_gain: 20}} = WakeSession.tick_sync()

    assert %{
             gain: 20,
             commands: [
               {:gain, session_id, 20},
               {:play, session_id, "wake_up_call"} | _commands
             ]
           } = Audio.status()
  end

  test "starts a direct strong-phase test at the configured ceiling", %{alarm: alarm} do
    assert {:ok, _pid} = WakeSession.start_strong_test(alarm, Clock.utc_now())

    assert %{audio_phase: :strong, current_gain: 20, state: :ringing} = WakeSession.active()

    assert %{commands: commands} = Audio.status()
    assert Enum.any?(commands, &match?({:play, _, "wake_up_call"}, &1))

    assert {:ok, %{state: :dismissed}} = WakeSession.dismiss(:test)
  end

  test "confirms only continuous confident vacancy", %{alarm: alarm} do
    assert {:ok, _pid} = WakeSession.start(alarm)
    Camera.observe(:vacant, 0.95)
    assert %{state: :exit_candidate} = WakeSession.active()

    Clock.Manual.advance(50)
    Camera.observe(:occupied, 0.95)
    assert %{state: :ringing, exit_candidate_since: nil} = WakeSession.active()

    Camera.observe(:vacant, 0.95)
    assert %{state: :exit_candidate} = WakeSession.active()
    Clock.Manual.advance(101)

    assert {:completed, %{state: :dismissed, terminal_reason: :bed_exit}} =
             WakeSession.tick_sync()

    assert WakeSession.active() == nil
  end

  test "unknown observations never dismiss", %{alarm: alarm} do
    assert {:ok, _pid} = WakeSession.start(alarm)
    Camera.observe(:unknown, 1.0, %{quality: :unusable})
    Clock.Manual.advance(1_000)
    assert {:ok, %{state: :ringing}} = WakeSession.tick_sync()
  end

  test "ignores vacancy until the startup grace period has elapsed", %{alarm: alarm} do
    previous = Application.fetch_env!(:robine_wake, :exit_grace_ms)
    Application.put_env(:robine_wake, :exit_grace_ms, 5_000)
    on_exit(fn -> Application.put_env(:robine_wake, :exit_grace_ms, previous) end)

    assert {:ok, _pid} = WakeSession.start(alarm)
    Camera.observe(:vacant, 0.95)
    assert %{state: :ringing} = WakeSession.active()

    Clock.Manual.advance(5_000)
    Camera.observe(:vacant, 0.95)
    assert %{state: :exit_candidate} = WakeSession.active()
  end

  test "enforces snooze limit and resumes on monotonic time", %{alarm: alarm} do
    assert {:ok, _pid} = WakeSession.start(alarm)
    assert {:ok, %{state: :snoozed, snooze_count: 1}} = WakeSession.snooze()
    assert {:ok, %{state: :snoozed, snooze_count: 1}} = WakeSession.snooze()

    Clock.Manual.advance(60_000)
    assert {:ok, %{state: :ringing, snooze_count: 1}} = WakeSession.tick_sync()
    assert {:error, :snooze_limit} = WakeSession.snooze()
  end

  test "manual dismissal is idempotent", %{alarm: alarm} do
    assert {:ok, _pid} = WakeSession.start(alarm)
    assert {:ok, %{state: :dismissed}} = WakeSession.dismiss(:manual)

    assert {:ok, %{state: :idle, terminal_reason: :already_inactive}} =
             WakeSession.dismiss(:manual)

    assert length(Settings.recent_sessions()) == 1
  end

  test "a test bypasses the saved smartphone preference and retains its mode after restore", %{
    alarm: alarm
  } do
    assert {:ok, false} = Settings.set_smartphone_dismiss_enabled(false)
    assert {:ok, pid} = WakeSession.start_test(alarm, Clock.utc_now())
    assert %{test_mode: true, smartphone_dismiss_allowed: true} = WakeSession.active()
    [record] = Settings.recent_sessions()
    :ok = GenServer.stop(pid, :normal)

    assert {:ok, _pid} = WakeSession.restore(alarm, record)
    assert %{test_mode: true, smartphone_dismiss_allowed: true} = WakeSession.active()
    assert {:ok, %{state: :dismissed}} = WakeSession.dismiss(:smartphone)
    refute Settings.smartphone_dismiss_enabled()
  end

  test "smartphone dismissal follows the setting captured when the alarm starts", %{
    alarm: alarm
  } do
    assert Settings.smartphone_dismiss_enabled()
    assert {:ok, false} = Settings.set_smartphone_dismiss_enabled(false)
    assert {:ok, _pid} = WakeSession.start(alarm)
    assert %{smartphone_dismiss_allowed: false} = WakeSession.active()

    assert {:error, :smartphone_dismiss_setting_locked} =
             Settings.set_smartphone_dismiss_enabled(true)

    assert {:error, :smartphone_dismiss_disabled} = WakeSession.dismiss(:smartphone)
    assert %{state: :ringing} = WakeSession.active()

    assert {:ok, %{state: :dismissed, terminal_reason: :manual}} =
             WakeSession.dismiss(:manual)

    assert {:ok, true} = Settings.set_smartphone_dismiss_enabled(true)
    assert {:ok, _pid} = WakeSession.start(alarm)
    assert %{smartphone_dismiss_allowed: true} = WakeSession.active()

    assert {:ok, %{state: :dismissed, terminal_reason: :smartphone}} =
             WakeSession.dismiss(:smartphone)
  end

  test "disabling the feature overrides a saved preference and an already running session", %{
    alarm: alarm
  } do
    assert {:ok, true} = Settings.set_smartphone_dismiss_enabled(true)
    assert {:ok, _pid} = WakeSession.start(alarm)
    assert %{smartphone_dismiss_allowed: true} = WakeSession.active()

    Application.put_env(:robine_wake, :remote_dismiss_enabled, false)
    refute Settings.smartphone_dismiss_enabled()
    assert {:error, :smartphone_dismiss_disabled} = WakeSession.dismiss(:smartphone)
    assert {:ok, %{terminal_reason: :remote_button}} = WakeSession.dismiss(:remote_button)

    assert {:ok, _pid} = WakeSession.start(alarm)
    assert %{smartphone_dismiss_allowed: false} = WakeSession.active()
    assert {:ok, _session} = WakeSession.dismiss(:remote_button)

    Application.put_env(:robine_wake, :remote_dismiss_enabled, true)
    assert Settings.smartphone_dismiss_enabled()
  end

  test "records one terminal timeout after the maximum audible duration", %{alarm: alarm} do
    previous = Application.fetch_env!(:robine_wake, :max_session_ms)
    Application.put_env(:robine_wake, :max_session_ms, 1_000)
    on_exit(fn -> Application.put_env(:robine_wake, :max_session_ms, previous) end)

    assert {:ok, _pid} = WakeSession.start(alarm)
    Clock.Manual.advance(1_001)

    assert {:completed, %{state: :timed_out, terminal_reason: :timed_out}} =
             WakeSession.tick_sync()

    assert [%{"state" => "timed_out", "terminal_reason" => "timed_out"}] =
             Settings.recent_sessions(1)
  end

  defp eventually(fun, attempts \\ 50)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(2)
      eventually(fun, attempts - 1)
    end
  end
end
