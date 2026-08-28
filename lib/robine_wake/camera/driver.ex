defmodule RobineWake.Camera.Driver do
  @moduledoc "Infrared-camera hardware boundary."

  @callback capabilities() :: map()
  @callback health() :: map()
  @callback capture(keyword()) :: {:ok, map()} | {:error, term()}
end
