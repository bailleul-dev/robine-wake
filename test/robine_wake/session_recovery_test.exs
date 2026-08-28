defmodule RobineWake.SessionRecoveryTest do
  use RobineWake.DomainCase

  test "restores a recent ringing session without creating a duplicate" do
    {:ok, alarm} = Settings.create_alarm(%{local_time: "07:00", days_of_week: [1]})
    session_id = RobineWake.Id.generate()

    {:ok, _} =
      Settings.record_session(%{
        id: session_id,
        alarm_id: alarm.id,
        scheduled_for: Clock.utc_now(),
        started_at: Clock.utc_now(),
        state: :ringing,
        snooze_count: 1
      })

    assert {:ok, _pid} = RobineWake.SessionRecovery.run()
    assert %{id: ^session_id, state: :ringing, snooze_count: 1} = WakeSession.active()
    assert length(Settings.recent_sessions()) == 1
  end

  test "expires a stale active session instead of replaying it" do
    {:ok, alarm} = Settings.create_alarm(%{local_time: "07:00", days_of_week: [1]})
    session_id = RobineWake.Id.generate()
    old = DateTime.add(Clock.utc_now(), -1_000_000, :millisecond)

    {:ok, _} =
      Settings.record_session(%{
        id: session_id,
        alarm_id: alarm.id,
        scheduled_for: old,
        started_at: old,
        state: :ringing
      })

    assert :ok = RobineWake.SessionRecovery.run()
    assert WakeSession.active() == nil

    assert [%{"state" => "timed_out", "terminal_reason" => "expired_during_restart"}] =
             Settings.recent_sessions(1)
  end

  test "restores a snoozed session without restarting audio early" do
    {:ok, alarm} =
      Settings.create_alarm(%{
        local_time: "07:00",
        days_of_week: [1],
        snooze: %{enabled: true, duration_seconds: 480, maximum: 3}
      })

    session_id = RobineWake.Id.generate()
    snooze_until = DateTime.add(Clock.utc_now(), 120, :second)

    {:ok, _} =
      Settings.record_session(%{
        id: session_id,
        alarm_id: alarm.id,
        scheduled_for: Clock.utc_now(),
        started_at: DateTime.add(Clock.utc_now(), -60, :second),
        state: :snoozed,
        snooze_count: 2,
        snooze_until_utc: snooze_until
      })

    assert {:ok, _pid} = RobineWake.SessionRecovery.run()
    assert %{id: ^session_id, state: :snoozed, snooze_count: 2} = WakeSession.active()
    assert %{active_session: nil} = Audio.status()

    Clock.Manual.advance(120_000)
    assert {:ok, %{state: :ringing, snooze_count: 2}} = WakeSession.tick_sync()
    assert %{active_session: ^session_id} = Audio.status()
  end
end
