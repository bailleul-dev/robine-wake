defmodule RobineWakeDev.Clock.Scaled do
  @moduledoc """
  Accelerated clock for demo mode.

  Virtual time = anchor + real elapsed time × speed. The demonstrator changes
  the speed (×1 to watch a breathing session, ×10 or ×60 to watch a dawn) or
  jumps forward; the domain keeps running unchanged on top of it.

  Reads (`utc_now/0`, `monotonic_ms/0`) come from `:persistent_term`, so they
  cost nothing. Timers created with `send_after/3` keep a virtual deadline and
  are re-armed when the speed changes; a jump fires, in order, every timer that
  becomes due. The virtual monotonic time never goes backwards; only the wall
  clock can be set back (demo reset).
  """

  @behaviour RobineWake.Clock

  use GenServer

  @key {__MODULE__, :anchor}
  @speeds [1, 10, 60]

  # --- Clock behaviour ------------------------------------------------------

  @impl RobineWake.Clock
  def utc_now, do: virtual_utc() |> DateTime.truncate(:second)

  @impl RobineWake.Clock
  def monotonic_ms, do: virtual_monotonic_ms()

  @impl RobineWake.Clock
  def send_after(destination, message, milliseconds),
    do: GenServer.call(__MODULE__, {:send_after, destination, message, milliseconds})

  @impl RobineWake.Clock
  def cancel_timer(reference), do: GenServer.call(__MODULE__, {:cancel_timer, reference})

  # --- Demo controls ----------------------------------------------------------

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def speeds, do: @speeds

  @doc "Changes the speed; pending timers keep their virtual deadlines."
  def set_speed(speed) when speed in @speeds, do: GenServer.call(__MODULE__, {:set_speed, speed})
  def set_speed(_speed), do: {:error, :unsupported_speed}

  @doc "Moves virtual time forward and fires the timers that become due, in order."
  def advance(milliseconds) when is_integer(milliseconds) and milliseconds >= 0,
    do: GenServer.call(__MODULE__, {:advance, milliseconds})

  @doc "Sets the wall clock (demo reset); the monotonic time keeps going forward."
  def set_utc(%DateTime{} = utc), do: GenServer.call(__MODULE__, {:set_utc, utc})

  def snapshot do
    anchor = anchor()

    %{
      utc: DateTime.to_iso8601(virtual_utc()),
      utc_ms: DateTime.to_unix(virtual_utc(), :millisecond),
      speed: anchor.speed
    }
  end

  # --- GenServer --------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    utc = Keyword.get(opts, :utc, DateTime.utc_now())
    put_anchor(System.monotonic_time(:millisecond), 0, DateTime.to_unix(utc, :millisecond), 1)
    {:ok, %{timers: %{}}}
  end

  @impl GenServer
  def handle_call({:send_after, destination, message, milliseconds}, _from, state) do
    reference = make_ref()
    deadline = virtual_monotonic_ms() + milliseconds
    timer = %{destination: destination, message: message, deadline: deadline}

    {:reply, reference,
     %{state | timers: Map.put(state.timers, reference, arm(reference, timer))}}
  end

  def handle_call({:cancel_timer, reference}, _from, state) do
    case Map.pop(state.timers, reference) do
      {nil, _timers} ->
        {:reply, false, state}

      {timer, timers} ->
        Process.cancel_timer(timer.real)
        {:reply, max(timer.deadline - virtual_monotonic_ms(), 0), %{state | timers: timers}}
    end
  end

  def handle_call({:set_speed, speed}, _from, state) do
    reanchor(speed: speed)
    {:reply, :ok, %{state | timers: rearm_all(state.timers)}}
  end

  def handle_call({:advance, milliseconds}, _from, state) do
    reanchor(shift: milliseconds)
    {:reply, :ok, %{state | timers: fire_due(state.timers)}}
  end

  def handle_call({:set_utc, utc}, _from, state) do
    anchor = anchor()
    now_virtual = virtual_monotonic_ms()

    put_anchor(
      System.monotonic_time(:millisecond),
      now_virtual,
      DateTime.to_unix(utc, :millisecond),
      anchor.speed
    )

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:fire, reference}, state) do
    case Map.pop(state.timers, reference) do
      {nil, _timers} ->
        {:noreply, state}

      {timer, timers} ->
        send(timer.destination, timer.message)
        {:noreply, %{state | timers: timers}}
    end
  end

  # --- Internals ----------------------------------------------------------------

  defp anchor, do: :persistent_term.get(@key)

  defp put_anchor(real_ms, virtual_ms, utc_ms, speed) do
    :persistent_term.put(@key, %{
      real_ms: real_ms,
      virtual_ms: virtual_ms,
      utc_ms: utc_ms,
      speed: speed
    })
  end

  defp elapsed_virtual(anchor),
    do: (System.monotonic_time(:millisecond) - anchor.real_ms) * anchor.speed

  defp virtual_monotonic_ms do
    anchor = anchor()
    anchor.virtual_ms + elapsed_virtual(anchor)
  end

  defp virtual_utc do
    anchor = anchor()
    DateTime.from_unix!(anchor.utc_ms + elapsed_virtual(anchor), :millisecond)
  end

  defp reanchor(opts) do
    anchor = anchor()
    elapsed = elapsed_virtual(anchor)
    shift = Keyword.get(opts, :shift, 0)

    put_anchor(
      System.monotonic_time(:millisecond),
      anchor.virtual_ms + elapsed + shift,
      anchor.utc_ms + elapsed + shift,
      Keyword.get(opts, :speed, anchor.speed)
    )
  end

  defp arm(reference, timer) do
    remaining = max(timer.deadline - virtual_monotonic_ms(), 0)
    real_delay = ceil(remaining / anchor().speed)
    Map.put(timer, :real, Process.send_after(self(), {:fire, reference}, real_delay))
  end

  defp rearm_all(timers) do
    Map.new(timers, fn {reference, timer} ->
      Process.cancel_timer(timer.real)
      {reference, arm(reference, timer)}
    end)
  end

  defp fire_due(timers) do
    now = virtual_monotonic_ms()
    {due, pending} = Enum.split_with(timers, fn {_reference, timer} -> timer.deadline <= now end)

    due
    |> Enum.sort_by(fn {_reference, timer} -> timer.deadline end)
    |> Enum.each(fn {_reference, timer} ->
      Process.cancel_timer(timer.real)
      send(timer.destination, timer.message)
    end)

    pending |> Map.new() |> rearm_all()
  end
end
