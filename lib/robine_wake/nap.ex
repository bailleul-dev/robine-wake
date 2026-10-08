defmodule RobineWake.Nap do
  @moduledoc """
  A nap is a single one-shot alarm ringing a chosen number of minutes from now.

  It reuses the sounds, volume, and light of the user's regular alarm, but its
  gentle ramp is short: at most five minutes, and never longer than the nap.
  """

  alias RobineWake.{Alarm, Clock, Settings}

  @alarm_id "nap"
  @maximum_ramp_seconds 300
  @maximum_minutes 180

  def alarm_id, do: @alarm_id

  def start(minutes) when is_integer(minutes) and minutes in 1..@maximum_minutes do
    template = template_alarm()
    timezone = if template, do: template.timezone, else: "Europe/Paris"
    wake_at = Clock.utc_now() |> DateTime.add(minutes * 60, :second)

    with {:ok, local} <- DateTime.shift_zone(wake_at, timezone) do
      ramp_seconds = min(@maximum_ramp_seconds, minutes * 60)

      attrs =
        template
        |> template_attrs(ramp_seconds)
        |> Map.merge(%{
          "id" => @alarm_id,
          "label" => "Sieste",
          "enabled" => true,
          "local_time" => local |> DateTime.to_time() |> Time.to_iso8601(),
          "one_shot_date" => local |> DateTime.to_date() |> Date.to_iso8601(),
          "days_of_week" => [],
          "timezone" => timezone,
          "prewake_seconds" => ramp_seconds,
          "snooze" => %{"enabled" => false}
        })

      save(attrs)
    end
  end

  def start(_minutes), do: {:error, %{duration_minutes: "must be between 1 and 180"}}

  def cancel do
    case Settings.get_alarm(@alarm_id) do
      {:ok, alarm} -> Settings.delete_alarm(@alarm_id, alarm.revision)
      {:error, :not_found} -> :ok
    end
  end

  defp save(attrs) do
    case Settings.get_alarm(@alarm_id) do
      {:ok, current} ->
        Settings.update_alarm(@alarm_id, Map.put(attrs, "revision", current.revision))

      {:error, :not_found} ->
        Settings.create_alarm(attrs)
    end
  end

  defp template_alarm do
    alarms = Enum.reject(Settings.list_alarms(), &(&1.id == @alarm_id))
    Enum.find(alarms, & &1.enabled) || List.first(alarms)
  end

  defp template_attrs(nil, ramp_seconds),
    do: %{"volume_profile" => %{"ramp_seconds" => ramp_seconds}}

  defp template_attrs(%Alarm{} = template, ramp_seconds) do
    map = Alarm.to_map(template)

    %{
      "sound_id" => map["sound_id"],
      "strong_sound_id" => map["strong_sound_id"],
      "volume_profile" => Map.put(map["volume_profile"], "ramp_seconds", ramp_seconds),
      "light_profile" => Map.put(map["light_profile"], "ramp_seconds", ramp_seconds)
    }
  end
end
