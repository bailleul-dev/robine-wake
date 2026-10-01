defmodule RobineWake.Audio.Driver do
  @moduledoc "Hardware boundary for alarm audio output."

  @callback capabilities() :: map()
  @callback prepare(String.t()) :: :ok | {:error, term()}
  @callback play(String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  @callback set_gain(non_neg_integer()) :: :ok | {:error, term()}
  @callback stop(term()) :: :ok | {:error, term()}
  @callback status() :: map()

  @doc """
  Sets the hardware output level used for music between alarms, in dB. Music
  receivers attenuate in software below it, so it is their shared ceiling.
  """
  @callback set_music_level(float()) :: :ok | {:error, term()}

  @optional_callbacks set_music_level: 1
end
