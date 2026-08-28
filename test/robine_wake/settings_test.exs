defmodule RobineWake.SettingsTest do
  use RobineWake.DomainCase

  test "creates, updates with optimistic concurrency, and deletes an alarm" do
    assert {:ok, alarm} =
             Settings.create_alarm(%{label: "Morning", local_time: "07:00", days_of_week: [1]})

    assert [stored] = Settings.list_alarms()
    assert stored.id == alarm.id

    assert {:ok, updated} = Settings.update_alarm(alarm.id, %{label: "Early", revision: 1})
    assert updated.label == "Early"
    assert updated.revision == 2

    assert {:error, :revision_conflict} =
             Settings.update_alarm(alarm.id, %{label: "Stale", revision: 1})

    assert {:error, :revision_conflict} = Settings.update_alarm(alarm.id, %{label: "Missing"})

    assert {:error, :revision_conflict} = Settings.delete_alarm(alarm.id, 1)
    assert :ok = Settings.delete_alarm(alarm.id, 2)
    assert Settings.list_alarms() == []

    path = Application.fetch_env!(:robine_wake, :data_path)
    assert {:ok, persisted} = path |> File.read!() |> Jason.decode()
    assert persisted["schema_version"] == 1
    assert is_binary(persisted["created_at"])
    assert is_binary(persisted["updated_at"])
    assert {:ok, %{mode: mode}} = File.stat(path)
    assert Bitwise.band(mode, 0o777) == 0o600
  end

  test "rejects alarms that reference an unavailable sound" do
    assert {:error, %{sound_id: message}} =
             Settings.create_alarm(%{
               local_time: "07:00",
               days_of_week: [1],
               sound_id: "missing_sound"
             })

    assert message =~ "available validated sound"
    assert Settings.list_alarms() == []

    assert {:error, %{strong_sound_id: strong_message}} =
             Settings.create_alarm(%{
               local_time: "07:00",
               days_of_week: [1],
               strong_sound_id: "missing_strong_sound"
             })

    assert strong_message =~ "available validated sound"
  end

  test "persists and updates session terminal state" do
    id = RobineWake.Id.generate()

    assert {:ok, _} =
             Settings.record_session(%{
               id: id,
               alarm_id: "a",
               scheduled_for: Clock.utc_now(),
               state: :starting
             })

    assert :ok = Settings.update_session(id, %{state: :dismissed, terminal_reason: :manual})

    assert [%{"id" => ^id, "state" => "dismissed", "terminal_reason" => "manual"}] =
             Settings.recent_sessions(1)
  end

  test "deduplicates equivalent scheduled instants with different offsets" do
    instant = ~U[2026-01-15 06:00:00Z]
    {:ok, local} = DateTime.shift_zone(instant, "Europe/Paris")

    assert {:ok, _session} =
             Settings.record_session(%{
               id: "same-instant",
               alarm_id: "alarm-a",
               scheduled_for: local,
               state: :ringing
             })

    assert Settings.session_recorded?("alarm-a", instant)
    assert [%{"scheduled_for" => "2026-01-15T06:00:00Z"}] = Settings.recent_sessions(1)
  end

  test "records a missed occurrence only while the exact alarm revision is current" do
    assert {:ok, alarm} = Settings.create_alarm(%{local_time: "07:00", days_of_week: [1]})
    scheduled_for = Clock.utc_now()

    assert :stale =
             Settings.record_missed_if_current(
               alarm.id,
               alarm.revision + 1,
               scheduled_for,
               :catch_up_expired
             )

    assert :recorded =
             Settings.record_missed_if_current(
               alarm.id,
               alarm.revision,
               scheduled_for,
               :catch_up_expired
             )

    assert :already_recorded =
             Settings.record_missed_if_current(
               alarm.id,
               alarm.revision,
               scheduled_for,
               :catch_up_expired
             )

    assert [_session] = Settings.recent_sessions()
  end

  test "purges sessions past the configured retention window" do
    old = DateTime.add(Clock.utc_now(), -31, :day)
    recent = DateTime.add(Clock.utc_now(), -1, :day)

    {:ok, _} = Settings.record_session(%{id: "old", created_at: old, state: :dismissed})
    {:ok, _} = Settings.record_session(%{id: "recent", created_at: recent, state: :dismissed})

    send(Settings, :purge)
    _ = Settings.snapshot()

    assert [%{"id" => "recent"}] = Settings.recent_sessions()
  end

  test "exports configuration without runtime secrets and erases history" do
    assert {:ok, _alarm} = Settings.create_alarm(%{local_time: "07:00", days_of_week: [1]})

    assert {:ok, _session} =
             Settings.record_session(%{
               id: "session-1",
               state: :dismissed,
               password: "do-not-export"
             })

    export = Settings.export_configuration()
    encoded = Jason.encode!(export)

    assert export.format == "robine-wake-configuration"
    assert length(export.alarms) == 1
    refute encoded =~ "do-not-export"
    refute encoded =~ "admin_password"

    assert :ok = Settings.erase_history()
    assert Settings.recent_sessions() == []
  end

  test "persists a versioned non-image detection profile" do
    profile = %{
      revision: 2,
      width: 320,
      height: 240,
      roi: %{x: 20, y: 30, width: 200, height: 150},
      pixel_threshold: 30,
      occupied_ratio: 0.15,
      vacant_ratio: 0.03
    }

    assert :ok = Settings.put_detection_profile(profile)
    persisted = Settings.detection_profile()
    assert persisted["revision"] == 2
    assert persisted["roi"]["width"] == 200
    refute Jason.encode!(persisted) =~ "pixels"
  end
end
