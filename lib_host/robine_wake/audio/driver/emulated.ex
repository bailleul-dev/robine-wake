defmodule RobineWake.Audio.Driver.Emulated do
  @moduledoc """
  Audio output for demo mode: instead of an ALSA device, playback commands
  are published to `RobineWakeDev.Hardware` and played by the visitor's
  browser. Alarm sounds are served as files; the breathing soundscape is a
  live stream rendered by the server's DSP (`RobineWake.Audio.MeditationDSP`).
  """

  @behaviour RobineWake.Audio.Driver

  alias RobineWakeDev.Hardware

  @impl true
  def capabilities, do: %{state: :available, device: "browser-emulator", gain: true}

  @impl true
  def prepare(sound_id) do
    cond do
      sound_id == Hardware.breathing_sound_id() -> :ok
      RobineWake.SoundLibrary.available?(sound_id) -> :ok
      true -> {:error, :sound_not_found}
    end
  end

  @impl true
  def play(session_id, sound_id) do
    with :ok <- Hardware.audio_play(session_id, sound_id), do: {:ok, {:emulated, session_id}}
  end

  @impl true
  def set_gain(gain) when gain in 0..100, do: Hardware.audio_gain(gain)

  @impl true
  def stop(_handle), do: Hardware.audio_stop()

  @impl true
  def status, do: capabilities()
end
