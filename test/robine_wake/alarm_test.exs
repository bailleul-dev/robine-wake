defmodule RobineWake.AlarmTest do
  use ExUnit.Case, async: true

  alias RobineWake.Alarm

  test "validates and normalizes alarm input" do
    assert {:ok, alarm} =
             Alarm.new(%{
               "label" => "Weekdays",
               "local_time" => "07:30",
               "days_of_week" => [5, 1, 1, 3],
               "timezone" => "Europe/Paris",
               "dismiss_policy" => "bed_exit"
             })

    assert alarm.days_of_week == [1, 3, 5]
    assert alarm.local_time == ~T[07:30:00]
    assert alarm.dismiss_policy == :bed_exit
    assert alarm.prewake_seconds == 1_200
    assert alarm.revision == 1
  end

  test "persists a configurable pre-wake duration and falls back to legacy ramp data" do
    assert {:ok, configured} = Alarm.new(%{prewake_seconds: 1_800})
    assert configured.prewake_seconds == 1_800
    assert Alarm.to_map(configured)["prewake_seconds"] == 1_800

    assert {:ok, legacy} = Alarm.new(%{volume_profile: %{ramp_seconds: 420}})
    assert legacy.prewake_seconds == 420

    assert {:error, %{prewake_seconds: _}} = Alarm.new(%{prewake_seconds: 3_601})
  end

  test "rejects unsafe or incomplete input" do
    assert {:error, %{days_of_week: _}} = Alarm.new(%{days_of_week: [], one_shot_date: nil})
    assert {:error, %{timezone: _}} = Alarm.new(%{timezone: "Nowhere/Invalid"})

    assert {:error, %{volume_profile: _}} =
             Alarm.new(%{volume_profile: %{start: 80, ceiling: 20, ramp_seconds: 10}})

    assert {:error, %{volume_profile: _}} =
             Alarm.new(%{volume_profile: %{start: 15, ceiling: 101, ramp_seconds: 10}})

    assert {:error, %{volume_profile: _}} =
             Alarm.new(%{volume_profile: %{start: 15, ceiling: 60, strong: 101}})

    assert {:error, %{light_profile: _}} =
             Alarm.new(%{light_profile: %{enabled: true, end_behavior: "blink"}})
  end

  test "the strong-phase volume defaults to the ceiling and can differ from it" do
    assert {:ok, %{volume_profile: %{ceiling: 60, strong: 60}}} =
             Alarm.new(%{volume_profile: %{start: 15, ceiling: 60}})

    assert {:ok, %{volume_profile: %{ceiling: 60, strong: 90}}} =
             Alarm.new(%{volume_profile: %{start: 15, ceiling: 60, strong: 90}})

    assert {:ok, %{volume_profile: %{ceiling: 60, strong: 40}}} =
             Alarm.new(%{"volume_profile" => %{"start" => 15, "ceiling" => 60, "strong" => 40}})
  end

  test "a dawn on the strip by default, and Hue sunrises become strip dawns" do
    assert {:ok, %{light_profile: %{enabled: true, end_behavior: :off}}} = Alarm.new(%{})

    assert {:ok, alarm} =
             Alarm.new(%{
               "light_profile" => %{
                 "enabled" => true,
                 "target_id" => "bedroom-group",
                 "target_name" => "Chambre",
                 "start_brightness" => 2,
                 "end_brightness" => 80,
                 "ramp_seconds" => 1_200,
                 "end_behavior" => "restore"
               }
             })

    assert alarm.light_profile == %{enabled: true, end_behavior: :off}

    assert Alarm.to_map(alarm)["light_profile"] == %{"enabled" => true, "end_behavior" => :off}

    assert {:ok, %{light_profile: %{enabled: false, end_behavior: :leave}}} =
             Alarm.new(%{light_profile: %{enabled: false, end_behavior: "leave"}})
  end

  test "moves a nonexistent DST local time to the first valid instant" do
    assert {:ok, alarm} =
             Alarm.new(%{
               local_time: "02:30",
               one_shot_date: "2026-03-29",
               days_of_week: [],
               timezone: "Europe/Paris"
             })

    assert {:ok, occurrence} = Alarm.next_occurrence(alarm, ~U[2026-03-28 00:00:00Z])
    assert occurrence.hour == 3
    assert occurrence.minute == 0
    assert occurrence.time_zone == "Europe/Paris"
  end

  test "uses the first occurrence of an ambiguous DST local time" do
    assert {:ok, alarm} =
             Alarm.new(%{
               local_time: "02:30",
               one_shot_date: "2026-10-25",
               days_of_week: [],
               timezone: "Europe/Paris"
             })

    assert {:ok, occurrence} = Alarm.next_occurrence(alarm, ~U[2026-10-24 00:00:00Z])
    assert occurrence.utc_offset + occurrence.std_offset == 7_200
  end

  test "generates ordered recurring occurrences" do
    assert {:ok, alarm} = Alarm.new(%{local_time: "07:00", days_of_week: [1, 2, 3, 4, 5]})
    occurrences = Alarm.next_occurrences(alarm, 5, ~U[2026-01-16 07:00:00Z])

    assert length(occurrences) == 5

    assert Enum.chunk_every(occurrences, 2, 1, :discard)
           |> Enum.all?(fn [a, b] -> DateTime.before?(a, b) end)
  end

  test "finds the previous occurrence and returns none for a zero-count preview" do
    assert {:ok, alarm} = Alarm.new(%{local_time: "07:00", days_of_week: [1, 2, 3, 4, 5]})
    assert Alarm.next_occurrences(alarm, 0, ~U[2026-01-16 07:00:00Z]) == []

    assert {:ok, previous} = Alarm.previous_occurrence(alarm, ~U[2026-01-16 07:00:00Z])
    assert DateTime.to_iso8601(previous) == "2026-01-16T07:00:00+01:00"
  end
end
