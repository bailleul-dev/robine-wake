defmodule RobineWake.Alarm do
  @moduledoc "Validated alarm aggregate and time-zone-aware occurrence calculation."

  alias RobineWake.{Clock, Id}

  @days %{
    "monday" => 1,
    "tuesday" => 2,
    "wednesday" => 3,
    "thursday" => 4,
    "friday" => 5,
    "saturday" => 6,
    "sunday" => 7
  }

  @derive Jason.Encoder
  defstruct [
    :id,
    :created_at,
    :label,
    :local_time,
    :one_shot_date,
    enabled: true,
    days_of_week: [],
    timezone: "Europe/Paris",
    sound_id: "default",
    strong_sound_id: "default",
    prewake_seconds: 1_200,
    volume_profile: %{start: 15, ceiling: 85, strong: 85, ramp_seconds: 1_200},
    light_profile: %{
      enabled: false,
      target_id: nil,
      target_name: nil,
      start_brightness: 1,
      end_brightness: 70,
      ramp_seconds: 900,
      end_behavior: :restore
    },
    dismiss_policy: :manual,
    snooze: %{enabled: true, duration_seconds: 480, maximum: 3},
    revision: 1
  ]

  @type t :: %__MODULE__{}

  def new(attrs) when is_map(attrs) do
    with {:ok, created_at} <- parse_datetime(get(attrs, :created_at, Clock.utc_now())),
         {:ok, local_time} <- parse_time(get(attrs, :local_time, "07:00")),
         {:ok, date} <- parse_date(get(attrs, :one_shot_date)),
         {:ok, days} <- parse_days(get(attrs, :days_of_week, Enum.to_list(1..7))),
         {:ok, timezone} <- validate_timezone(get(attrs, :timezone, "Europe/Paris")),
         {:ok, parsed_policy} <- parse_policy(get(attrs, :dismiss_policy, :manual)),
         {:ok, volume} <- parse_volume(get(attrs, :volume_profile, %{})),
         {:ok, prewake_seconds} <-
           parse_prewake(get(attrs, :prewake_seconds, volume.ramp_seconds)),
         {:ok, light} <- parse_light(get(attrs, :light_profile, %{})),
         {:ok, snooze} <- parse_snooze(get(attrs, :snooze, %{})) do
      policy =
        if Application.get_env(:robine_wake, :camera_enabled, true),
          do: parsed_policy,
          else: :manual

      alarm = %__MODULE__{
        id: get(attrs, :id, Id.generate()),
        created_at: created_at,
        label: attrs |> get(:label, "Alarm") |> to_string() |> String.slice(0, 80),
        enabled: truthy?(get(attrs, :enabled, true)),
        local_time: local_time,
        days_of_week: days,
        one_shot_date: date,
        timezone: timezone,
        sound_id: attrs |> get(:sound_id, "default") |> to_string(),
        strong_sound_id: attrs |> get(:strong_sound_id, "default") |> to_string(),
        prewake_seconds: prewake_seconds,
        volume_profile: volume,
        light_profile: light,
        dismiss_policy: policy,
        snooze: snooze,
        revision: integer(get(attrs, :revision, 1), 1)
      }

      validate_schedule(alarm)
    end
  end

  def next_occurrence(alarm, from_utc \\ Clock.utc_now()) do
    with {:ok, local_now} <- DateTime.shift_zone(from_utc, alarm.timezone) do
      DateTime.to_date(local_now)
      |> candidate_dates(alarm)
      |> Enum.find_value(
        {:error, :no_occurrence},
        &future_candidate(&1, alarm, from_utc)
      )
    end
  end

  def next_occurrences(alarm, count, from_utc \\ Clock.utc_now())
  def next_occurrences(_alarm, 0, _from_utc), do: []

  def next_occurrences(alarm, count, from_utc) when is_integer(count) and count > 0 do
    Enum.reduce_while(1..count, {[], from_utc}, fn _, {acc, cursor} ->
      case next_occurrence(alarm, cursor) do
        {:ok, occurrence} ->
          {:cont, {[occurrence | acc], DateTime.add(occurrence, 1, :second)}}

        {:error, _} ->
          {:halt, {acc, cursor}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  def previous_occurrence(alarm, before_utc \\ Clock.utc_now()) do
    with {:ok, local_before} <- DateTime.shift_zone(before_utc, alarm.timezone) do
      DateTime.to_date(local_before)
      |> previous_candidate_dates(alarm)
      |> Enum.find_value(
        {:error, :no_occurrence},
        &past_candidate(&1, alarm, before_utc)
      )
    end
  end

  def to_map(%__MODULE__{} = alarm) do
    %{
      "id" => alarm.id,
      "created_at" => DateTime.to_iso8601(alarm.created_at),
      "label" => alarm.label,
      "enabled" => alarm.enabled,
      "local_time" => Time.to_iso8601(alarm.local_time),
      "days_of_week" => alarm.days_of_week,
      "one_shot_date" => alarm.one_shot_date && Date.to_iso8601(alarm.one_shot_date),
      "timezone" => alarm.timezone,
      "sound_id" => alarm.sound_id,
      "strong_sound_id" => alarm.strong_sound_id,
      "prewake_seconds" => alarm.prewake_seconds,
      "volume_profile" => stringify_keys(alarm.volume_profile),
      "light_profile" => stringify_keys(alarm.light_profile),
      "dismiss_policy" => Atom.to_string(alarm.dismiss_policy),
      "snooze" => stringify_keys(alarm.snooze),
      "revision" => alarm.revision
    }
  end

  defp candidate_dates(date, %{one_shot_date: %Date{} = one}), do: Enum.uniq([date, one])
  defp candidate_dates(date, _alarm), do: Stream.map(0..370, &Date.add(date, &1))
  defp previous_candidate_dates(_date, %{one_shot_date: %Date{} = one}), do: [one]
  defp previous_candidate_dates(date, _alarm), do: Stream.map(0..370, &Date.add(date, -&1))

  defp scheduled_on?(%{one_shot_date: %Date{} = scheduled}, date), do: date == scheduled

  defp scheduled_on?(%{days_of_week: days}, date),
    do: Date.day_of_week(date) in days

  defp future_candidate(date, alarm, from_utc) do
    occurrence_candidate(date, alarm, &DateTime.after?(&1, from_utc))
  end

  defp past_candidate(date, alarm, before_utc) do
    occurrence_candidate(date, alarm, &DateTime.before?(&1, before_utc))
  end

  defp occurrence_candidate(date, alarm, predicate) do
    if scheduled_on?(alarm, date) do
      date
      |> local_datetime(alarm.local_time, alarm.timezone)
      |> accepted_candidate(predicate)
    end
  end

  defp accepted_candidate({:ok, candidate}, predicate) do
    if predicate.(candidate), do: {:ok, candidate}
  end

  defp accepted_candidate(_result, _predicate), do: nil

  defp local_datetime(date, time, timezone) do
    naive = NaiveDateTime.new!(date, time)

    case DateTime.from_naive(naive, timezone) do
      {:ok, datetime} -> {:ok, datetime}
      {:ambiguous, first, _second} -> {:ok, first}
      {:gap, _before, after_gap} -> {:ok, after_gap}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_schedule(%{days_of_week: [], one_shot_date: nil}),
    do: {:error, %{days_of_week: "must not be empty for a recurring alarm"}}

  defp validate_schedule(alarm), do: {:ok, alarm}

  defp parse_time(%Time{} = value), do: {:ok, Time.truncate(value, :second)}

  defp parse_time(value) when is_binary(value) do
    value = if String.length(value) == 5, do: value <> ":00", else: value

    case Time.from_iso8601(value) do
      {:ok, time} -> {:ok, Time.truncate(time, :second)}
      _ -> {:error, %{local_time: "must use HH:MM or HH:MM:SS"}}
    end
  end

  defp parse_time(_), do: {:error, %{local_time: "is invalid"}}

  defp parse_datetime(%DateTime{} = value), do: {:ok, DateTime.truncate(value, :second)}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.truncate(datetime, :second)}
      _ -> {:error, %{created_at: "must use ISO 8601"}}
    end
  end

  defp parse_datetime(_), do: {:error, %{created_at: "is invalid"}}
  defp parse_date(nil), do: {:ok, nil}
  defp parse_date(""), do: {:ok, nil}
  defp parse_date(%Date{} = date), do: {:ok, date}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, %{one_shot_date: "must use YYYY-MM-DD"}}
    end
  end

  defp parse_date(_), do: {:error, %{one_shot_date: "is invalid"}}

  defp parse_days(days) when is_list(days) do
    parsed =
      Enum.map(days, fn
        day when day in 1..7 -> day
        day when is_binary(day) -> Map.get(@days, String.downcase(day)) || parse_int(day)
        _ -> nil
      end)

    if Enum.all?(parsed, &(&1 in 1..7)),
      do: {:ok, parsed |> Enum.uniq() |> Enum.sort()},
      else: {:error, %{days_of_week: "must contain weekdays 1 through 7"}}
  end

  defp parse_days(_), do: {:error, %{days_of_week: "must be a list"}}

  defp validate_timezone(timezone) when is_binary(timezone) do
    case DateTime.now(timezone) do
      {:ok, _} -> {:ok, timezone}
      _ -> {:error, %{timezone: "is not a known IANA time zone"}}
    end
  end

  defp validate_timezone(_), do: {:error, %{timezone: "is invalid"}}

  defp parse_policy(value) when value in [:manual, :bed_exit, :either], do: {:ok, value}

  defp parse_policy(value) when is_binary(value) do
    case value do
      "manual" -> {:ok, :manual}
      "bed_exit" -> {:ok, :bed_exit}
      "either" -> {:ok, :either}
      _ -> {:error, %{dismiss_policy: "must be manual, bed_exit, or either"}}
    end
  end

  defp parse_policy(_), do: {:error, %{dismiss_policy: "is invalid"}}

  defp parse_volume(value) when is_map(value) do
    safety_ceiling = Application.get_env(:robine_wake, :audio_safety_ceiling, 100)

    ceiling = integer(get(value, :ceiling, 85), 85)

    # Alarms saved before the strong level existed keep ringing at the ceiling.
    profile = %{
      start: integer(get(value, :start, 15), 15),
      ceiling: ceiling,
      strong: integer(get(value, :strong, ceiling), ceiling),
      ramp_seconds: integer(get(value, :ramp_seconds, 1_200), 1_200)
    }

    if profile.start in 0..safety_ceiling and
         profile.ceiling in profile.start..safety_ceiling and
         profile.strong in 0..safety_ceiling and
         profile.ramp_seconds in 0..3600,
       do: {:ok, profile},
       else: {:error, %{volume_profile: "contains values outside safe bounds"}}
  end

  defp parse_volume(_), do: {:error, %{volume_profile: "must be an object"}}

  defp parse_prewake(value) do
    seconds = integer(value, -1)

    if seconds in 0..3600,
      do: {:ok, seconds},
      else: {:error, %{prewake_seconds: "must be between 0 and 3600 seconds"}}
  end

  defp parse_light(value) when is_map(value) do
    enabled = truthy?(get(value, :enabled, false))
    target_id = optional_text(get(value, :target_id))
    behavior = parse_end_behavior(get(value, :end_behavior, :restore))

    profile = %{
      enabled: enabled,
      target_id: target_id,
      target_name: optional_text(get(value, :target_name)),
      start_brightness: integer(get(value, :start_brightness, 1), 1),
      end_brightness: integer(get(value, :end_brightness, 70), 70),
      ramp_seconds: integer(get(value, :ramp_seconds, 900), 900),
      end_behavior: behavior
    }

    with :ok <- validate_light_target(profile),
         :ok <- validate_light_brightness(profile),
         :ok <- validate_light_ramp(profile) do
      {:ok, profile}
    end
  end

  defp parse_light(_), do: {:error, %{light_profile: "must be an object"}}

  defp validate_light_target(%{enabled: true, target_id: nil}),
    do: {:error, %{light_profile: "requires a Hue target when enabled"}}

  defp validate_light_target(%{target_id: target_id}) when not is_nil(target_id) do
    if valid_target_id?(target_id),
      do: :ok,
      else: {:error, %{light_profile: "contains an invalid Hue target identifier"}}
  end

  defp validate_light_target(_profile), do: :ok

  defp validate_light_brightness(%{start_brightness: start, end_brightness: finish})
       when start not in 1..100 or finish not in 1..100,
       do: {:error, %{light_profile: "brightness must be between 1 and 100"}}

  defp validate_light_brightness(%{start_brightness: start, end_brightness: finish})
       when finish < start,
       do: {:error, %{light_profile: "end brightness must be at least the start brightness"}}

  defp validate_light_brightness(_profile), do: :ok

  defp validate_light_ramp(%{ramp_seconds: seconds, end_behavior: behavior})
       when seconds not in 0..3600 or is_nil(behavior),
       do: {:error, %{light_profile: "contains values outside supported bounds"}}

  defp validate_light_ramp(_profile), do: :ok

  defp parse_end_behavior(value) when value in [:restore, :off, :leave], do: value
  defp parse_end_behavior("restore"), do: :restore
  defp parse_end_behavior("off"), do: :off
  defp parse_end_behavior("leave"), do: :leave
  defp parse_end_behavior(_), do: nil

  defp optional_text(nil), do: nil
  defp optional_text(""), do: nil
  defp optional_text(value), do: value |> to_string() |> String.slice(0, 120)
  defp valid_target_id?(value), do: String.match?(value, ~r/\A[0-9A-Za-z-]{1,64}\z/)

  defp parse_snooze(value) when is_map(value) do
    snooze = %{
      enabled: truthy?(get(value, :enabled, true)),
      duration_seconds: integer(get(value, :duration_seconds, 480), 480),
      maximum: integer(get(value, :maximum, 3), 3)
    }

    if snooze.duration_seconds in 60..1800 and snooze.maximum in 0..10,
      do: {:ok, snooze},
      else: {:error, %{snooze: "contains values outside safe bounds"}}
  end

  defp parse_snooze(_), do: {:error, %{snooze: "must be an object"}}

  defp get(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp integer(value, _default) when is_integer(value), do: value

  defp integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> default
    end
  end

  defp integer(_, default), do: default

  defp parse_int(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp truthy?(value), do: value in [true, "true", 1, "1", "on"]
  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
