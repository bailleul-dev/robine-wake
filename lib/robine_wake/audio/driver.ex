defmodule RobineWake.Audio.Driver do
  @moduledoc "Hardware boundary for alarm audio output."

  @callback capabilities() :: map()
  @callback prepare(String.t()) :: :ok | {:error, term()}
  @callback play(String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  @callback set_gain(non_neg_integer()) :: :ok | {:error, term()}
  @callback stop(term()) :: :ok | {:error, term()}
  @callback status() :: map()
end
