defmodule RobineWake.Clock do
  @moduledoc "Clock boundary used by domain code and deterministic tests."

  @callback utc_now() :: DateTime.t()
  @callback monotonic_ms() :: integer()

  def adapter, do: Application.fetch_env!(:robine_wake, :clock)
  def utc_now, do: adapter().utc_now()
  def monotonic_ms, do: adapter().monotonic_ms()
end

defmodule RobineWake.Clock.System do
  @moduledoc false
  @behaviour RobineWake.Clock

  @impl true
  def utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @impl true
  def monotonic_ms, do: System.monotonic_time(:millisecond)
end

defmodule RobineWake.Clock.Manual do
  @moduledoc "Controllable clock for host simulations and deterministic tests."
  @behaviour RobineWake.Clock
  use Agent

  def start_link(opts \\ []) do
    utc = Keyword.get(opts, :utc, ~U[2026-01-01 06:00:00Z])
    monotonic_ms = Keyword.get(opts, :monotonic_ms, 0)
    Agent.start_link(fn -> %{utc: utc, monotonic_ms: monotonic_ms} end, name: __MODULE__)
  end

  @impl true
  def utc_now, do: Agent.get(__MODULE__, & &1.utc)

  @impl true
  def monotonic_ms, do: Agent.get(__MODULE__, & &1.monotonic_ms)

  def advance(milliseconds) when is_integer(milliseconds) do
    Agent.update(__MODULE__, fn state ->
      %{
        state
        | utc: DateTime.add(state.utc, milliseconds, :millisecond),
          monotonic_ms: state.monotonic_ms + milliseconds
      }
    end)
  end

  def set(utc, monotonic_ms \\ 0) do
    Agent.update(__MODULE__, fn _ -> %{utc: utc, monotonic_ms: monotonic_ms} end)
  end
end
