defmodule RobineWake.MCP.RateLimiter do
  @moduledoc false

  use GenServer

  @window_ms :timer.minutes(1)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def allow?(peer), do: GenServer.call(__MODULE__, {:allow?, peer})
  def clear, do: GenServer.call(__MODULE__, :clear)

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:allow?, peer}, _from, state) do
    now = System.monotonic_time(:millisecond)
    limit = Application.fetch_env!(:robine_wake, :mcp_max_requests_per_minute)

    state =
      Map.filter(state, fn {_peer, entry} -> now - entry.window_started_at < @window_ms end)

    entry = Map.get(state, peer, %{count: 0, window_started_at: now})
    allowed = entry.count < limit
    next_entry = if allowed, do: %{entry | count: entry.count + 1}, else: entry

    {:reply, allowed, Map.put(state, peer, next_entry)}
  end

  def handle_call(:clear, _from, _state), do: {:reply, :ok, %{}}
end
