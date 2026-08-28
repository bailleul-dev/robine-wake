defmodule RobineWake.Hue.Driver do
  @moduledoc "Transport contract for a local Philips Hue bridge."

  @callback pair(String.t()) :: {:ok, map()} | {:error, term()}
  @callback targets(map()) :: {:ok, [map()]} | {:error, term()}
  @callback get_target(map(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback set_target(map(), String.t(), map()) :: :ok | {:error, term()}
end
