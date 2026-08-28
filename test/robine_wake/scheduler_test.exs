defmodule RobineWake.SchedulerTest do
  use RobineWake.DomainCase

  test "triggers a due alarm once and advances its schedule" do
    assert {:ok, alarm} =
             Settings.create_alarm(%{
               label: "Due",
               local_time: "07:01",
               timezone: "Europe/Paris",
               days_of_week: [1, 2, 3, 4, 5, 6, 7]
             })

    status = Scheduler.status()
    assert status.next[alarm.id] == "2026-01-15T07:01:00+01:00"

    Clock.Manual.advance(60_000)
    first = Scheduler.tick()
    assert first.triggers >= 1
    assert %{alarm_id: alarm_id} = WakeSession.active()
    assert alarm_id == alarm.id

    WakeSession.dismiss(:test)
    Scheduler.tick()
    assert [_session] = Settings.recent_sessions()
  end

  test "can trigger an alarm immediately" do
    {:ok, alarm} = Settings.create_alarm(%{local_time: "23:00", days_of_week: [1]})
    assert {:ok, _pid} = Scheduler.trigger_now(alarm.id)
    assert %{alarm_id: alarm_id, state: :ringing} = WakeSession.active()
    assert alarm_id == alarm.id
  end

  test "starts the gentle phase at the configured lead time while preserving wake time" do
    {:ok, alarm} =
      Settings.create_alarm(%{
        local_time: "07:20",
        days_of_week: [1, 2, 3, 4, 5, 6, 7],
        prewake_seconds: 1_200
      })

    assert Scheduler.status().next[alarm.id] == "2026-01-15T07:20:00+01:00"
    Scheduler.tick()

    assert %{scheduled_for: scheduled_for, audio_phase: :gentle, current_gain: 15} =
             WakeSession.active()

    assert DateTime.to_iso8601(scheduled_for) == "2026-01-15T07:20:00+01:00"
  end

  test "can trigger the strong phase immediately" do
    {:ok, alarm} =
      Settings.create_alarm(%{
        local_time: "23:00",
        days_of_week: [1],
        strong_sound_id: "wake_up_call",
        volume_profile: %{start: 10, ceiling: 40, ramp_seconds: 300}
      })

    assert {:ok, _pid} = Scheduler.trigger_strong_test(alarm.id)
    assert %{alarm_id: alarm_id, audio_phase: :strong, current_gain: 40} = WakeSession.active()
    assert alarm_id == alarm.id
  end

  test "does not arm automatically until an untrusted clock is confirmed" do
    {:ok, alarm} =
      Settings.create_alarm(%{
        local_time: "07:01",
        days_of_week: [1, 2, 3, 4, 5, 6, 7]
      })

    trigger_count = Scheduler.status().triggers
    :ok = RobineWake.ClockQuality.mark_untrusted(:test)
    Clock.Manual.advance(60_000)

    status = Scheduler.tick()
    refute status.armed
    assert status.triggers == trigger_count
    assert WakeSession.active() == nil

    assert {:ok, %{trusted: true}} = RobineWake.ClockQuality.confirm()
    status = Scheduler.tick()
    assert status.armed
    assert %{alarm_id: alarm_id} = WakeSession.active()
    assert alarm_id == alarm.id
  end

  test "arms automatically when NTP synchronization is acquired" do
    :ok = RobineWake.ClockQuality.mark_untrusted(:boot)
    assert RobineWake.Scheduler.refresh().armed == false

    send(
      RobineWake.ClockQuality,
      {:nerves_time, :sync_acquired, %{offset: 0.002, stratum: 2}}
    )

    assert eventually(fn ->
             %{trusted: true, source: :ntp} = RobineWake.ClockQuality.status()
             RobineWake.Scheduler.status().armed
           end)
  end

  test "records but does not play an occurrence beyond the catch-up window" do
    created_at = DateTime.add(Clock.utc_now(), -3_600, :second)

    {:ok, alarm} =
      Settings.create_alarm(%{
        local_time: "06:50",
        days_of_week: [1, 2, 3, 4, 5, 6, 7],
        created_at: created_at
      })

    send(Scheduler, :settings_changed)
    _ = Scheduler.status()

    assert WakeSession.active() == nil

    assert [%{"alarm_id" => alarm_id, "state" => "missed", "terminal_reason" => reason}] =
             Settings.recent_sessions(1)

    assert alarm_id == alarm.id
    assert reason == "catch_up_expired"
  end

  test "a ten-minute forward clock jump marks the scheduled occurrence missed" do
    {:ok, alarm} =
      Settings.create_alarm(%{
        local_time: "07:01",
        days_of_week: [1, 2, 3, 4, 5, 6, 7]
      })

    assert Scheduler.status().next[alarm.id] == "2026-01-15T07:01:00+01:00"
    Clock.Manual.advance(11 * 60_000)
    Scheduler.tick()

    assert WakeSession.active() == nil

    assert [%{"alarm_id" => alarm_id, "state" => "missed", "terminal_reason" => reason}] =
             Settings.recent_sessions(1)

    assert alarm_id == alarm.id
    assert reason == "catch_up_expired"
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
