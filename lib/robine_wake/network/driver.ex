defmodule RobineWake.Network.Driver do
  @moduledoc "Network health adapter contract."

  @callback status() :: map()
end
