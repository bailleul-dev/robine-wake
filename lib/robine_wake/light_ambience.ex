defmodule RobineWake.LightAmbience do
  @moduledoc """
  A program on the LED strip (`light.program`) with an optional sound
  ambience, such as the storm and rain, that ends with the light.

  The volume holds while the light holds, and falls to silence while it
  fades: over the whole of a sunset, over the sunset that follows a reading
  light. The ambience of a dawn stops when daylight is reached. `off`, a new
  program and an alarm stop it.

  This server never calls the wake session or the breathing session: the
  command layer stops the breathing first, and a wake session interrupts
  this one.
  """

  use GenServer

  alias RobineWake.{Audio, EventLog, EventStream, GuideLight, Id, SoundLibrary, WakeSession}

  @tick_ms 2_000
  @fade_step_ms 40
  @default_sunset_ms 30 * 60_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Starts the `light.program` `body` on the strip and, unless `ambience` is
  nil, plays `%{sound_id: id, volume: 0..100}` along with it. Returns the
  strip's answer.
  """
  def start(body, ambience \\ nil)

  def start(body, nil) when is_map(body),
    do: GenServer.call(__MODULE__, {:start, body, nil}, 20_000)

  def start(body, %{sound_id: sound_id, volume: volume} = ambience) when is_map(body) do
    cond do
      volume not in 0..100 -> {:error, :invalid_ambience_volume}
      not Enum.any?(SoundLibrary.list(), &(&1.id == sound_id)) -> {:error, :sound_not_found}
      WakeSession.active() -> {:error, :wake_session_active}
      true -> GenServer.call(__MODULE__, {:start, body, ambience}, 20_000)
    end
  end

  def set_volume(volume), do: GenServer.call(__MODULE__, {:set_volume, volume})

  @doc "Fades the sound out and stops it; the light is left as it is."
  def stop, do: GenServer.call(__MODULE__, :stop, 15_000)

  @doc "Stops the sound at once, for an alarm about to ring; the light is left as it is."
  def interrupt, do: GenServer.call(__MODULE__, :interrupt, 5_000)

  def status, do: GenServer.call(__MODULE__, :status)

  @doc """
  How the volume follows `body`: full for `hold_ms`, then down to silence
  over `fade_ms`.
  """
  def timeline(%{"program" => "sunset", "duration_ms" => duration}), do: {0, duration}

  def timeline(%{"program" => "reading", "duration_ms" => duration} = body),
    do: {duration, Map.get(body, "sunset_ms", @default_sunset_ms)}

  def timeline(%{"duration_ms" => duration}), do: {duration, 0}

  @impl true
  def init(_opts), do: {:ok, %{session: nil}}

  @impl true
  def handle_call({:start, %{"program" => "off"} = body, _ambience}, _from, state) do
    state = end_session(state, :stopped)
    {:reply, GuideLight.program(body), state}
  end

  def handle_call({:start, body, ambience}, _from, state) do
    state = end_session(state, :replaced)

    case GuideLight.program(body) do
      {:ok, status} ->
        session = ambience && begin_session(body, ambience)
        publish_change()
        {:reply, {:ok, status}, %{state | session: session}}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:set_volume, volume}, _from, %{session: session} = state)
      when volume in 0..100 and not is_nil(session) do
    session = apply_gain(%{session | volume: volume})
    publish_change()
    {:reply, {:ok, public(session)}, %{state | session: session}}
  end

  def handle_call({:set_volume, volume}, _from, state) do
    reason = if volume in 0..100, do: :ambience_not_active, else: :invalid_ambience_volume
    {:reply, {:error, reason}, state}
  end

  def handle_call(:stop, _from, state) do
    state = end_session(state, :stopped)
    {:reply, {:ok, public(state.session)}, state}
  end

  def handle_call(:interrupt, _from, state) do
    {:reply, :ok, end_session(state, :interrupted, false)}
  end

  def handle_call(:status, _from, state), do: {:reply, public(state.session), state}

  @impl true
  def handle_info({:tick, token}, %{session: %{token: token} = session} = state) do
    if elapsed_ms(session) >= session.hold_ms + session.fade_ms do
      # The light went dark, or reached daylight: the ambience ends with it.
      {:noreply, end_session(state, :completed)}
    else
      Process.send_after(self(), {:tick, token}, @tick_ms)
      {:noreply, %{state | session: apply_gain(session)}}
    end
  end

  def handle_info({:tick, _stale}, state), do: {:noreply, state}

  defp begin_session(body, %{sound_id: sound_id, volume: volume}) do
    {hold_ms, fade_ms} = timeline(body)
    token = make_ref()
    audio_id = "ambience-" <> Id.generate()

    audio_error =
      with :ok <- Audio.play(audio_id, sound_id),
           :ok <- Audio.set_gain(audio_id, volume) do
        nil
      else
        {:error, reason} ->
          _ = Audio.stop(audio_id)

          EventLog.emit(:light_ambience_failed,
            source: :light_ambience,
            severity: :warning,
            payload: %{reason: inspect(reason), sound_id: sound_id}
          )

          reason
      end

    Process.send_after(self(), {:tick, token}, @tick_ms)

    %{
      token: token,
      program: body["program"],
      sound_id: sound_id,
      volume: volume,
      gain: volume,
      hold_ms: hold_ms,
      fade_ms: fade_ms,
      started_ms: System.monotonic_time(:millisecond),
      started_at: DateTime.utc_now(),
      audio_id: if(audio_error, do: nil, else: audio_id),
      audio_error: audio_error
    }
  end

  defp elapsed_ms(session), do: System.monotonic_time(:millisecond) - session.started_ms

  # The volume chosen, scaled down along the fade.
  defp gain(session) do
    fading_ms = elapsed_ms(session) - session.hold_ms

    cond do
      fading_ms <= 0 -> session.volume
      fading_ms >= session.fade_ms -> 0
      true -> round(session.volume * (1 - fading_ms / session.fade_ms))
    end
  end

  defp apply_gain(%{audio_id: nil} = session), do: session

  defp apply_gain(session) do
    case gain(session) do
      gain when gain == session.gain ->
        session

      gain ->
        _ = Audio.set_gain(session.audio_id, gain)
        %{session | gain: gain}
    end
  end

  defp end_session(state, reason, fade \\ true)
  defp end_session(%{session: nil} = state, _reason, _fade), do: state

  defp end_session(%{session: session} = state, reason, fade) do
    if session.audio_id do
      if fade, do: fade_out(session)
      _ = Audio.stop(session.audio_id)
    end

    EventLog.emit(:light_ambience_stopped,
      source: :light_ambience,
      payload: %{reason: reason, program: session.program, sound_id: session.sound_id}
    )

    publish_change()
    %{state | session: nil}
  end

  defp fade_out(%{gain: gain, audio_id: audio_id}) when gain > 0 do
    Enum.each((gain - 1)..0//-1, fn level ->
      _ = Audio.set_gain(audio_id, level)
      Process.sleep(@fade_step_ms)
    end)
  end

  defp fade_out(_session), do: :ok

  defp public(nil), do: %{active: false}

  defp public(session) do
    %{
      active: true,
      program: session.program,
      sound_id: session.sound_id,
      volume_percent: session.volume,
      gain_percent: session.gain,
      started_at: DateTime.to_iso8601(session.started_at),
      server_time: DateTime.to_iso8601(DateTime.utc_now()),
      elapsed_ms: elapsed_ms(session),
      hold_ms: session.hold_ms,
      fade_ms: session.fade_ms,
      audio: %{active: is_binary(session.audio_id), error: error_text(session.audio_error)}
    }
  end

  defp publish_change do
    if Process.whereis(EventStream), do: EventStream.publish("state.changed")
  end

  defp error_text(nil), do: nil
  defp error_text(error) when is_atom(error), do: Atom.to_string(error)
  defp error_text(error), do: inspect(error)
end
