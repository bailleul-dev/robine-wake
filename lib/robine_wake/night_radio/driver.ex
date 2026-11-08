defmodule RobineWake.NightRadio.Driver do
  @moduledoc "Radio silencing adapter contract used by `RobineWake.NightRadio`."

  @doc "Blocks (`true`) or unblocks (`false`) every managed radio."
  @callback set_silenced(boolean()) :: :ok | {:error, term()}

  @doc "Describes the managed radios for diagnostics."
  @callback status() :: map()
end
