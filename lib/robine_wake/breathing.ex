defmodule RobineWake.Breathing do
  @moduledoc """
  Evening breathing session: the LED strip breathes at a cadence while the
  speaker plays the meditation ambience.

  The ESP32 renders the breathing on its own (`light.program` `breathing`)
  and ends it with the last full breath; this server starts it, plays and
  stops the ambience at the same time, and tells the app where the breath
  is. Without the strip the ambience still plays, and the reverse.
  """

  use GenServer

  alias RobineWake.{Audio, EventLog, EventStream, GuideLight, Id, WakeSession}

  @sound "breathing_meditation_ambience"
  @default_volume 60
  @max_minutes 60
  @fade_step_ms 40

  @typedoc "Phase durations of one breath, in milliseconds."
  @type cadence :: %{
          hold_empty_ms: non_neg_integer(),
          inhale_ms: pos_integer(),
          hold_full_ms: non_neg_integer(),
          exhale_ms: pos_integer()
        }

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Starts a session of about `minutes` at `cadence` (`"0-4-0-6"` for cardiac
  coherence), with the ambience at `volume` percent. It replaces a session
  in progress.
  """
  def start(cadence, minutes, volume \\ @default_volume),
    do: GenServer.call(__MODULE__, {:start, cadence, minutes, volume}, 15_000)

  def set_volume(volume), do: GenServer.call(__MODULE__, {:set_volume, volume})
  def stop, do: GenServer.call(__MODULE__, :stop, 15_000)

  @doc """
  Ends a session without waiting, for a wake session that takes over the
  strip: the light is left to it.
  """
  def interrupt, do: GenServer.cast(__MODULE__, :stop)

  def status, do: GenServer.call(__MODULE__, :status)

  @doc """
  Parses `hold empty-inhale-hold full-exhale`, in seconds from 0 to 60
  (decimals allowed), as the ESP32 does. A breath needs an inhale and an
  exhale.
  """
  @spec parse_cadence(term()) :: {:ok, cadence()} | :error
  def parse_cadence(text) when is_binary(text) do
    with [_, _, _, _] = parts <- String.split(String.trim(text), "-"),
         {:ok, [hold_empty, inhale, hold_full, exhale]} <- parse_seconds(parts),
         true <- inhale > 0 and exhale > 0 do
      {:ok,
       %{hold_empty_ms: hold_empty, inhale_ms: inhale, hold_full_ms: hold_full, exhale_ms: exhale}}
    else
      _ -> :error
    end
  end

  def parse_cadence(_text), do: :error

  @doc "Length of a session in whole breaths: `minutes` rounded up."
  def session_ms(cadence, minutes) do
    breath_ms = breath_ms(cadence)
    div(minutes * 60_000 + breath_ms - 1, breath_ms) * breath_ms
  end

  defp parse_seconds(parts) do
    Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, acc} ->
      case Float.parse(String.trim(part)) do
        {seconds, ""} when seconds >= 0 and seconds <= 60 ->
          {:cont, {:ok, acc ++ [round(seconds * 1_000)]}}

        _ ->
          {:halt, :error}
      end
    end)
  end

  defp breath_ms(cadence),
    do: cadence.hold_empty_ms + cadence.inhale_ms + cadence.hold_full_ms + cadence.exhale_ms

  @impl true
  def init(_opts), do: {:ok, %{session: nil}}

  @impl true
  def handle_call({:start, text, minutes, volume}, _from, state) do
    with {:ok, cadence} <- cadence(text),
         :ok <- validate_minutes(minutes),
         :ok <- validate_volume(volume),
         nil <- WakeSession.active() do
      state = end_session(state, :replaced)
      session = begin_session(text, cadence, minutes, volume)
      publish_change()
      {:reply, {:ok, public(session)}, %{state | session: session}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
      %{} -> {:reply, {:error, :wake_session_active}, state}
    end
  end

  def handle_call({:set_volume, volume}, _from, %{session: session} = state)
      when volume in 0..100 and not is_nil(session) do
    session = %{session | volume: volume}

    session =
      case session.audio_id && Audio.set_gain(session.audio_id, volume) do
        {:error, reason} -> %{session | audio_error: reason}
        _ -> session
      end

    publish_change()
    {:reply, {:ok, public(session)}, %{state | session: session}}
  end

  def handle_call({:set_volume, volume}, _from, state) do
    reason = if volume in 0..100, do: :breathing_not_active, else: :invalid_breathing_volume
    {:reply, {:error, reason}, state}
  end

  def handle_call(:stop, _from, state) do
    next = end_session(state, :stopped)
    publish_change()
    {:reply, {:ok, public(next.session)}, next}
  end

  def handle_call(:status, _from, state), do: {:reply, public(state.session), state}

  @impl true
  def handle_cast(:stop, state) do
    next = end_session(state, :interrupted, false)
    publish_change()
    {:noreply, next}
  end

  @impl true
  def handle_info({:complete, token}, %{session: %{token: token}} = state) do
    # The strip went dark on its own with the last breath.
    next = end_session(state, :completed, false)
    publish_change()
    {:noreply, next}
  end

  def handle_info({:complete, _stale_token}, state), do: {:noreply, state}

  defp cadence(text) do
    case parse_cadence(text) do
      {:ok, cadence} -> {:ok, cadence}
      :error -> {:error, :invalid_cadence}
    end
  end

  defp validate_minutes(minutes) when minutes in 1..@max_minutes, do: :ok
  defp validate_minutes(_minutes), do: {:error, :invalid_breathing_duration}

  defp validate_volume(volume) when volume in 0..100, do: :ok
  defp validate_volume(_volume), do: {:error, :invalid_breathing_volume}

  defp begin_session(text, cadence, minutes, volume) do
    session_ms = session_ms(cadence, minutes)
    token = make_ref()

    light_error =
      case GuideLight.program(%{
             "program" => "breathing",
             "cadence" => String.trim(text),
             "duration_ms" => minutes * 60_000
           }) do
        {:ok, _status} -> nil
        {:error, reason} -> reason
      end

    started_ms = System.monotonic_time(:millisecond)
    {audio_id, audio_error} = start_audio(volume)

    EventLog.emit(:breathing_started,
      source: :breathing,
      payload: %{
        cadence: String.trim(text),
        duration_minutes: minutes,
        light: if(light_error, do: inspect(light_error), else: :strip),
        audio: if(audio_id, do: :meditation_ambience, else: :unavailable)
      }
    )

    %{
      token: token,
      timer: Process.send_after(self(), {:complete, token}, session_ms),
      cadence_text: String.trim(text),
      cadence: cadence,
      minutes: minutes,
      session_ms: session_ms,
      started_ms: started_ms,
      started_at: DateTime.utc_now(),
      volume: volume,
      audio_id: audio_id,
      audio_error: audio_error,
      light_error: light_error
    }
  end

  defp start_audio(volume) do
    audio_id = "breathing-" <> Id.generate()

    with :ok <- Audio.play(audio_id, @sound),
         :ok <- Audio.set_gain(audio_id, volume) do
      {audio_id, nil}
    else
      {:error, reason} ->
        _ = Audio.stop(audio_id)

        EventLog.emit(:breathing_audio_failed,
          source: :breathing,
          severity: :warning,
          payload: %{reason: inspect(reason)}
        )

        {nil, reason}
    end
  end

  defp end_session(state, reason, light_off \\ true)
  defp end_session(%{session: nil} = state, _reason, _light_off), do: state

  defp end_session(%{session: session} = state, reason, light_off) do
    Process.cancel_timer(session.timer)
    if light_off, do: GuideLight.start_program(%{"program" => "off"})
    fade_out(session)

    EventLog.emit(:breathing_stopped,
      source: :breathing,
      payload: %{reason: reason, cadence: session.cadence_text}
    )

    %{state | session: nil}
  end

  defp fade_out(%{audio_id: nil}), do: :ok

  defp fade_out(%{audio_id: audio_id, volume: volume}) do
    if volume > 0 do
      Enum.each((volume - 1)..0//-1, fn gain ->
        _ = Audio.set_gain(audio_id, gain)
        Process.sleep(@fade_step_ms)
      end)
    end

    Audio.stop(audio_id)
  end

  defp public(nil), do: %{active: false}

  defp public(session) do
    now_ms = System.monotonic_time(:millisecond)
    elapsed_ms = min(now_ms - session.started_ms, session.session_ms)

    %{
      active: true,
      cadence: session.cadence_text,
      hold_empty_ms: session.cadence.hold_empty_ms,
      inhale_ms: session.cadence.inhale_ms,
      hold_full_ms: session.cadence.hold_full_ms,
      exhale_ms: session.cadence.exhale_ms,
      duration_minutes: session.minutes,
      started_at: DateTime.to_iso8601(session.started_at),
      server_time: DateTime.utc_now() |> DateTime.to_iso8601(),
      elapsed_ms: elapsed_ms,
      remaining_seconds: div(session.session_ms - elapsed_ms + 999, 1_000),
      volume_percent: session.volume,
      audio: %{active: is_binary(session.audio_id), error: error_text(session.audio_error)},
      light: %{active: is_nil(session.light_error), error: error_text(session.light_error)}
    }
  end

  defp publish_change do
    if Process.whereis(EventStream) do
      EventStream.publish("breathing.changed")
      EventStream.publish("state.changed")
    end
  end

  defp error_text(nil), do: nil
  defp error_text(error) when is_atom(error), do: Atom.to_string(error)
  defp error_text(error), do: inspect(error)
end
