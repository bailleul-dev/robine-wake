defmodule RobineWake.EventStream do
  @moduledoc "Small replayable event stream used by HTTP SSE clients."

  use GenServer

  @maximum_events 64

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def subscribe(last_event_id \\ nil) do
    GenServer.call(__MODULE__, {:subscribe, self(), parse_id(last_event_id)})
  end

  def unsubscribe(pid \\ self()), do: GenServer.cast(__MODULE__, {:unsubscribe, pid})

  def publish(event) when is_binary(event), do: publish(event, nil)

  def publish(event, data) when is_binary(event) and (is_map(data) or is_nil(data)),
    do: GenServer.cast(__MODULE__, {:publish, event, data})

  @impl true
  def init(_opts), do: {:ok, %{sequence: 0, subscribers: %{}, events: []}}

  @impl true
  def handle_call({:subscribe, pid, last_event_id}, _from, state) do
    {subscribers, _reference} = monitor_subscriber(state.subscribers, pid)
    replay = Enum.filter(state.events, &(&1.id > last_event_id))
    {:reply, {:ok, state.sequence, replay}, %{state | subscribers: subscribers}}
  end

  @impl true
  def handle_cast({:unsubscribe, pid}, state) do
    {:noreply, %{state | subscribers: remove_subscriber(state.subscribers, pid)}}
  end

  def handle_cast({:publish, event_name, data}, state) do
    event = %{
      id: state.sequence + 1,
      event: event_name,
      at: DateTime.utc_now() |> DateTime.to_iso8601(),
      data: data
    }

    Enum.each(state.subscribers, fn {pid, _reference} -> send(pid, {:robine_event, event}) end)

    {:noreply,
     %{
       state
       | sequence: event.id,
         events: Enum.take(state.events ++ [event], -@maximum_events)
     }}
  end

  @impl true
  def handle_info({:DOWN, reference, :process, pid, _reason}, state) do
    subscribers =
      case state.subscribers[pid] do
        ^reference -> Map.delete(state.subscribers, pid)
        _other -> state.subscribers
      end

    {:noreply, %{state | subscribers: subscribers}}
  end

  defp monitor_subscriber(subscribers, pid) do
    case subscribers[pid] do
      nil ->
        reference = Process.monitor(pid)
        {Map.put(subscribers, pid, reference), reference}

      reference ->
        {subscribers, reference}
    end
  end

  defp remove_subscriber(subscribers, pid) do
    case Map.pop(subscribers, pid) do
      {nil, subscribers} ->
        subscribers

      {reference, subscribers} ->
        _ = Process.demonitor(reference, [:flush])
        subscribers
    end
  end

  defp parse_id(value) when is_integer(value) and value >= 0, do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id >= 0 -> id
      _invalid -> 0
    end
  end

  defp parse_id(_value), do: 0
end
