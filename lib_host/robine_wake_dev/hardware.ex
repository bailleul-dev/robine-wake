defmodule RobineWakeDev.Hardware do
  @moduledoc """
  State of the emulated hardware in demo mode, as commanded by the real
  domain through the emulated drivers: the lights of the bar (breathing halo,
  bedside lamps) and the audio output.

  Every change is broadcast on `RobineWakeDev.PubSub`, topic `"hardware"`, as
  `{:hardware, event}`; `snapshot/0` gives a new viewer the full state.
  """

  use GenServer

  alias RobineWake.Audio.Driver.Alsa
  alias RobineWake.SoundLibrary

  @topic "hardware"

  # Hue targets exposed by the emulated bridge, and the outputs they drive.
  @targets [
    %{"id" => "halo", "name" => "Halo Robine", "kind" => "zone", "outputs" => ["halo"]},
    %{
      "id" => "lamps",
      "name" => "Lampes de chevet",
      "kind" => "zone",
      "outputs" => ["lamp_left", "lamp_right"]
    },
    %{
      "id" => "bedroom",
      "name" => "Chambre",
      "kind" => "room",
      "outputs" => ["halo", "lamp_left", "lamp_right"]
    }
  ]
  @outputs ["halo", "lamp_left", "lamp_right"]
  @initial_light %{on: false, brightness: 60.0, xy: nil, mirek: 370, transition_ms: 0}
  @initial_audio %{
    playing: false,
    session_id: nil,
    sound_id: nil,
    url: nil,
    loop: false,
    gain: 0,
    db: nil
  }
  @breathing_sound_id "breathing_meditation_ambience"
  # The recording the ALSA driver plays for breathing sessions; the DSP
  # soundscape is its fallback when the recording is missing.
  @meditation_recording_id "storm_rain_lasonotheque_2719"

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def topic, do: @topic
  def subscribe, do: Phoenix.PubSub.subscribe(RobineWakeDev.PubSub, @topic)

  @doc "Hue targets of the emulated bridge, without the internal output mapping."
  def hue_targets, do: Enum.map(@targets, &Map.delete(&1, "outputs"))

  def hue_state(target_id), do: GenServer.call(__MODULE__, {:hue_state, target_id})

  def apply_hue(target_id, changes),
    do: GenServer.call(__MODULE__, {:apply_hue, target_id, changes})

  def audio_play(session_id, sound_id),
    do: GenServer.call(__MODULE__, {:audio_play, session_id, sound_id})

  def audio_gain(gain), do: GenServer.call(__MODULE__, {:audio_gain, gain})
  def audio_stop, do: GenServer.call(__MODULE__, :audio_stop)

  @doc "Publishes a clock change (speed, jump, reset) to the viewers."
  def clock_changed, do: GenServer.cast(__MODULE__, :clock_changed)

  def reset, do: GenServer.call(__MODULE__, :reset)
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  @impl true
  def init(_opts), do: {:ok, initial_state()}

  @impl true
  def handle_call({:hue_state, target_id}, _from, state) do
    case target(target_id) do
      nil -> {:reply, {:error, :hue_target_not_found}, state}
      %{"outputs" => [output | _]} -> {:reply, {:ok, to_hue(state.lights[output])}, state}
    end
  end

  def handle_call({:apply_hue, target_id, changes}, _from, state) do
    case target(target_id) do
      nil ->
        {:reply, {:error, :hue_target_not_found}, state}

      %{"outputs" => outputs} ->
        lights =
          Enum.reduce(outputs, state.lights, fn output, lights ->
            Map.update!(lights, output, &merge_hue(&1, changes))
          end)

        Enum.each(outputs, &broadcast(%{type: "light", id: &1, state: lights[&1]}))
        {:reply, :ok, %{state | lights: lights}}
    end
  end

  def handle_call({:audio_play, session_id, sound_id}, _from, state) do
    audio =
      Map.merge(sound_source(session_id, sound_id), %{
        playing: true,
        session_id: session_id,
        sound_id: sound_id,
        gain: 0,
        db: decibels(0)
      })

    broadcast(%{type: "audio", state: audio})
    {:reply, :ok, %{state | audio: audio}}
  end

  def handle_call({:audio_gain, gain}, _from, state) do
    audio = %{state.audio | gain: gain, db: decibels(gain)}
    broadcast(%{type: "audio", state: audio})
    {:reply, :ok, %{state | audio: audio}}
  end

  def handle_call(:audio_stop, _from, state) do
    broadcast(%{type: "audio", state: @initial_audio})
    {:reply, :ok, %{state | audio: @initial_audio}}
  end

  def handle_call(:reset, _from, _state) do
    state = initial_state()
    broadcast(%{type: "snapshot", state: public(state)})
    {:reply, :ok, state}
  end

  def handle_call(:snapshot, _from, state), do: {:reply, public(state), state}

  @impl true
  def handle_cast(:clock_changed, state) do
    broadcast(%{type: "clock", state: clock()})
    {:noreply, state}
  end

  # --- Hue state ------------------------------------------------------------

  defp target(id), do: Enum.find(@targets, &(&1["id"] == id))

  defp merge_hue(light, changes) do
    light
    |> maybe(changes, ["on", "on"], &%{&2 | on: &1})
    |> maybe(changes, ["dimming", "brightness"], &%{&2 | brightness: &1 * 1.0})
    |> maybe(changes, ["color", "xy"], &%{&2 | xy: %{x: &1["x"], y: &1["y"]}, mirek: nil})
    |> maybe(changes, ["color_temperature", "mirek"], &%{&2 | mirek: &1, xy: nil})
    |> Map.put(:transition_ms, get_in(changes, ["dynamics", "duration"]) || 0)
  end

  defp maybe(light, changes, path, update) do
    case get_in(changes, path) do
      nil -> light
      value -> update.(value, light)
    end
  end

  defp to_hue(light) do
    colour =
      if light.xy,
        do: %{"color" => %{"xy" => %{"x" => light.xy.x, "y" => light.xy.y}}},
        else: %{"color_temperature" => %{"mirek" => light.mirek}}

    Map.merge(
      %{"on" => %{"on" => light.on}, "dimming" => %{"brightness" => light.brightness}},
      colour
    )
  end

  # --- Audio ----------------------------------------------------------------

  def breathing_sound_id, do: @breathing_sound_id

  defp sound_source(session_id, @breathing_sound_id) do
    if SoundLibrary.available?(@meditation_recording_id),
      do: %{url: sound_file_url(@meditation_recording_id), loop: true},
      else: %{
        url: "/emulator/audio/breathing.wav?session=#{URI.encode_www_form(session_id)}",
        loop: false
      }
  end

  defp sound_source(_session_id, sound_id), do: %{url: sound_file_url(sound_id), loop: true}

  defp sound_file_url(sound_id), do: "/emulator/audio/sounds/#{URI.encode_www_form(sound_id)}"

  # Output level of the Amp2 for a gain, from the ALSA driver's own curve
  # (nil when muted).
  defp decibels(0), do: nil

  defp decibels(gain) do
    {decibels, "dB"} = gain |> Alsa.amixer_gain() |> Float.parse()
    decibels
  end

  # --- Snapshot -------------------------------------------------------------

  defp initial_state,
    do: %{lights: Map.new(@outputs, &{&1, @initial_light}), audio: @initial_audio}

  defp public(state), do: %{lights: state.lights, audio: state.audio, clock: clock()}

  defp clock do
    clock = RobineWake.Clock.adapter()

    if function_exported?(clock, :snapshot, 0),
      do: clock.snapshot(),
      else: %{utc: DateTime.to_iso8601(clock.utc_now()), speed: 1}
  end

  defp broadcast(event),
    do: Phoenix.PubSub.broadcast(RobineWakeDev.PubSub, @topic, {:hardware, event})
end
