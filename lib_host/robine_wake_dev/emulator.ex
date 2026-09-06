defmodule RobineWakeDev.Emulator do
  @moduledoc "Host-only controls that drive the real Robine Wake domain through simulated hardware."

  alias RobineWake.{Camera, Clock, ClockQuality, Health, Scheduler, Settings, WakeSession}

  @width 320
  @height 240

  def snapshot do
    %{
      health: Health.snapshot(),
      alarms: Settings.list_alarms(),
      session: WakeSession.active(),
      product_url: "http://127.0.0.1:#{Application.fetch_env!(:robine_wake, :web_port)}",
      hardware: %{
        audio: Application.get_env(:robine_wake, :host_audio_state, :available),
        camera: Application.get_env(:robine_wake, :host_camera_state, :available),
        network: Application.get_env(:robine_wake, :host_network_state, :available),
        clock: clock_mode()
      }
    }
  end

  def calibrate_camera do
    frame = synthetic_frame(:vacant)

    with :ok <- Camera.set_background(frame),
         {:ok, _observation} <- Camera.submit_frame(frame, frame.pixels) do
      :ok
    end
  end

  def camera(mode) when mode in [:occupied, :vacant, :unknown, :saturated] do
    Application.put_env(:robine_wake, :host_camera_state, :available)
    frame = synthetic_frame(mode)
    Camera.submit_frame(frame, background_pixels())
  end

  def camera(:offline) do
    Application.put_env(:robine_wake, :host_camera_state, :unavailable)
    Camera.observe(:unknown, 0.0, %{quality: :unusable, reason: :camera_unavailable})
  end

  def camera(_mode), do: {:error, :unsupported_camera_mode}

  def network(mode) when mode in [:available, :unavailable] do
    Application.put_env(:robine_wake, :host_network_state, mode)
    :ok
  end

  def network(_mode), do: {:error, :unsupported_network_mode}

  def audio(mode) when mode in [:available, :unavailable, :failing] do
    Application.put_env(:robine_wake, :host_audio_state, mode)
    :ok
  end

  def audio(_mode), do: {:error, :unsupported_audio_mode}

  def crash_active_audio do
    case WakeSession.active() do
      nil -> {:error, :no_active_session}
      _session -> WakeSession.audio_failed(:simulated_player_crash)
    end
  end

  def clock_quality(:trusted), do: ClockQuality.confirm() |> normalize_ok()
  def clock_quality(:untrusted), do: ClockQuality.mark_untrusted(:simulated_clock_loss)
  def clock_quality(_quality), do: {:error, :unsupported_clock_quality}

  def enable_manual_clock do
    cond do
      WakeSession.active() ->
        {:error, :active_session}

      Process.whereis(Clock.Manual) ->
        Application.put_env(:robine_wake, :clock, Clock.Manual)
        :ok

      true ->
        with {:ok, _pid} <- Clock.Manual.start_link(utc: Clock.utc_now(), monotonic_ms: 0) do
          Application.put_env(:robine_wake, :clock, Clock.Manual)
          Scheduler.refresh()
          :ok
        end
    end
  end

  def use_system_clock do
    if WakeSession.active() do
      {:error, :active_session}
    else
      Application.put_env(:robine_wake, :clock, Clock.System)

      if pid = Process.whereis(Clock.Manual) do
        Agent.stop(pid)
      end

      Scheduler.refresh()
      :ok
    end
  end

  def advance_time(minutes) when is_integer(minutes) and minutes in 1..1_440 do
    if clock_mode() == :manual do
      :ok = Clock.Manual.advance(minutes * 60_000)
      _status = Scheduler.tick()
      :ok
    else
      {:error, :manual_clock_required}
    end
  end

  def advance_time(_minutes), do: {:error, :invalid_duration}

  def create_demo_alarm do
    local_time =
      Clock.utc_now()
      |> DateTime.shift_zone!("Europe/Paris")
      |> DateTime.to_time()
      |> Time.truncate(:second)
      |> Time.to_iso8601()

    Settings.create_alarm(%{
      label: "LiveView demo alarm",
      local_time: local_time,
      days_of_week: Enum.to_list(1..7),
      timezone: "Europe/Paris",
      volume_profile: %{start: 15, ceiling: 70, ramp_seconds: 60},
      snooze: %{enabled: true, duration_seconds: 120, maximum: 3}
    })
    |> normalize_ok()
  end

  def trigger_alarm(id), do: Scheduler.trigger_now(id) |> normalize_ok()
  def snooze, do: WakeSession.snooze() |> normalize_ok()
  def dismiss, do: WakeSession.dismiss(:smartphone) |> normalize_ok()

  def reset_hardware do
    Application.put_env(:robine_wake, :host_audio_state, :available)
    Application.put_env(:robine_wake, :host_camera_state, :available)
    Application.put_env(:robine_wake, :host_network_state, :available)
    :ok = Camera.reset()
    _result = ClockQuality.confirm()
    :ok
  end

  defp synthetic_frame(mode) do
    %{
      pixels: pixels(mode),
      width: @width,
      height: @height,
      quality: if(mode in [:unknown, :saturated], do: :unusable, else: :good),
      captured_at_monotonic: next_frame_timestamp()
    }
  end

  defp pixels(:occupied) do
    foreground = div(@width * @height, 4)
    <<:binary.copy(<<100>>, foreground)::binary, :binary.copy(<<20>>, @width * @height - foreground)::binary>>
  end

  defp pixels(:saturated), do: :binary.copy(<<255>>, @width * @height)
  defp pixels(_mode), do: background_pixels()
  defp background_pixels, do: :binary.copy(<<20>>, @width * @height)

  defp next_frame_timestamp do
    current = Clock.monotonic_ms()
    previous = Camera.status().last_frame_at
    max(current, (previous || current - 1) + 1)
  end

  defp clock_mode do
    if Application.fetch_env!(:robine_wake, :clock) == Clock.Manual, do: :manual, else: :system
  end

  defp normalize_ok({:ok, _value}), do: :ok
  defp normalize_ok(:ok), do: :ok
  defp normalize_ok({:error, _reason} = error), do: error
end
