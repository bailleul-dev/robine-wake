defmodule RobineWake.Clock do
  @moduledoc """
  Clock boundary used by domain code and deterministic tests.

  Long domain deadlines (the sunrise stages of a wake session) are scheduled
  through the clock, so an accelerated clock (demo mode) keeps them consistent
  with the time it reports. Rhythms paced for a human body (the 4/6 breathing,
  the strong-wake colour alternation) and polling ticks stay on real time.
  """

  @callback utc_now() :: DateTime.t()
  @callback monotonic_ms() :: integer()
  @doc "Sends `message` to `destination` once `milliseconds` of clock time have passed."
  @callback send_after(pid() | atom(), term(), non_neg_integer()) :: reference()
  @callback cancel_timer(reference()) :: non_neg_integer() | false

  def adapter, do: Application.fetch_env!(:robine_wake, :clock)
  def utc_now, do: adapter().utc_now()
  def monotonic_ms, do: adapter().monotonic_ms()

  def send_after(destination, message, milliseconds),
    do: adapter().send_after(destination, message, milliseconds)

  def cancel_timer(nil), do: false
  def cancel_timer(reference), do: adapter().cancel_timer(reference)
end

defmodule RobineWake.Clock.System do
  @moduledoc false
  @behaviour RobineWake.Clock

  @impl true
  def utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @impl true
  def monotonic_ms, do: System.monotonic_time(:millisecond)

  @impl true
  def send_after(destination, message, milliseconds),
    do: Process.send_after(destination, message, milliseconds)

  @impl true
  def cancel_timer(reference), do: Process.cancel_timer(reference)
end

defmodule RobineWake.Clock.Manual do
  @moduledoc """
  Controllable clock for host simulations and deterministic tests.

  Time only moves with `advance/1` or `set/2`; timers keep real-time behaviour
  so existing simulations are unaffected.
  """
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

  @impl true
  def send_after(destination, message, milliseconds),
    do: Process.send_after(destination, message, milliseconds)

  @impl true
  def cancel_timer(reference), do: Process.cancel_timer(reference)

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
