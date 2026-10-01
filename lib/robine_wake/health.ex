defmodule RobineWake.Health do
  @moduledoc "Aggregated local health snapshot."

  alias RobineWake.{
    AirPlay,
    Audio,
    Auth,
    BluetoothAudio,
    Camera,
    Clock,
    ClockQuality,
    EventLog,
    Firmware,
    Network,
    Scheduler,
    Settings,
    UpdatePolicy,
    WakeSession
  }

  def snapshot do
    audio = safe(&Audio.status/0, :audio)
    airplay = safe(&AirPlay.status/0, :airplay)
    bluetooth_audio = safe(&BluetoothAudio.status/0, :bluetooth_audio)
    authentication = safe(&Auth.status/0, :authentication)

    camera =
      if Application.get_env(:robine_wake, :camera_enabled, true),
        do: safe(&Camera.status/0, :camera),
        else: %{state: :disabled, enabled: false}

    clock = safe(&ClockQuality.status/0, :clock)
    metrics = safe(&EventLog.metrics/0, :telemetry)
    firmware = safe(&Firmware.status/0, :firmware)
    network = safe(&Network.status/0, :network)
    updates = safe(&UpdatePolicy.status/0, :updates)
    scheduler = safe(&Scheduler.status/0, :scheduler)
    settings = safe(&Settings.snapshot/0, :settings)

    state = health_state(audio, authentication, camera, clock, network, scheduler, settings)

    %{
      state: state,
      version: Application.spec(:robine_wake, :vsn) |> to_string(),
      target: Application.fetch_env!(:robine_wake, :target) |> to_string(),
      authentication: json_safe(authentication),
      now: DateTime.to_iso8601(Clock.utc_now()),
      clock: json_safe(clock),
      uptime_ms: :erlang.statistics(:wall_clock) |> elem(0),
      metrics: json_safe(metrics),
      firmware: json_safe(firmware),
      network: json_safe(network),
      updates: json_safe(updates),
      scheduler: json_safe(scheduler),
      audio: json_safe(audio),
      airplay: json_safe(airplay),
      bluetooth_audio: json_safe(bluetooth_audio),
      camera: json_safe(camera),
      storage: %{state: if(settings[:degraded], do: :degraded, else: :available)},
      active_session: WakeSession.active()
    }
  end

  defp safe(fun, component) do
    fun.()
  catch
    :exit, reason -> %{state: :unhealthy, component: component, reason: inspect(reason)}
  end

  defp health_state(audio, authentication, camera, clock, network, scheduler, settings) do
    component_states = [
      error?(scheduler),
      error?(settings),
      degraded_auth?(authentication),
      degraded?(clock),
      degraded?(network),
      degraded_audio?(audio),
      degraded_camera?(camera)
    ]

    cond do
      Enum.any?(Enum.take(component_states, 2)) -> :unhealthy
      Enum.any?(Enum.drop(component_states, 2)) -> :degraded
      true -> :healthy
    end
  end

  defp error?(%{state: :unhealthy}), do: true
  defp error?(_), do: false

  defp degraded?(%{state: state}) when state in [:healthy, :available], do: false
  defp degraded?(_), do: true

  defp degraded_auth?(%{state: :available}), do: false
  defp degraded_auth?(_), do: true

  defp degraded_audio?(%{capabilities: %{state: state}}), do: state != :available
  defp degraded_audio?(_), do: true

  defp degraded_camera?(%{
         driver_health: %{state: :available},
         analysis_health: %{state: :available}
       }),
       do: false

  defp degraded_camera?(%{state: :disabled}), do: false

  defp degraded_camera?(_), do: true

  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp json_safe(%Date{} = value), do: Date.to_iso8601(value)
  defp json_safe(%Time{} = value), do: Time.to_iso8601(value)

  defp json_safe(value) when is_map(value),
    do: Map.new(value, fn {key, nested} -> {key, json_safe(nested)} end)

  defp json_safe(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&json_safe/1)

  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_pid(value) or is_port(value) or is_reference(value),
    do: inspect(value)

  defp json_safe(value), do: value
end
