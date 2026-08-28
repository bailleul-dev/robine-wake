defmodule RobineWake.EventLog do
  @moduledoc "Bounded, structured, privacy-filtered operational events."

  use GenServer

  alias RobineWake.{Clock, Id, Persistence}

  @forbidden_fragments ["password", "secret", "token", "pixel", "ssid", "frame", "image"]

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def emit(code, attrs \\ %{}), do: GenServer.call(__MODULE__, {:emit, code, attrs})
  def recent(limit \\ 100), do: GenServer.call(__MODULE__, {:recent, limit})
  def metrics, do: GenServer.call(__MODULE__, :metrics)
  def clear, do: GenServer.call(__MODULE__, :clear)

  @impl true
  def init(_opts) do
    path = Application.fetch_env!(:robine_wake, :critical_event_path)

    critical_events =
      case Persistence.load(path) do
        {:ok, data} -> Map.get(data, "critical_events", [])
        {:error, _reason} -> []
      end

    {:ok, %{events: prune_events(critical_events), totals: %{}, path: path}}
  end

  @impl true
  def handle_call({:emit, code, attrs}, _from, state) do
    attrs = Map.new(attrs)
    code = to_string(code)

    event = %{
      event_id: Id.generate(),
      occurred_at_monotonic: Clock.monotonic_ms(),
      occurred_at_utc: DateTime.to_iso8601(Clock.utc_now()),
      source: attrs |> Map.get(:source, Map.get(attrs, "source", :domain)) |> to_string(),
      code: code,
      session_id: Map.get(attrs, :session_id, Map.get(attrs, "session_id")),
      alarm_id: Map.get(attrs, :alarm_id, Map.get(attrs, "alarm_id")),
      severity: attrs |> Map.get(:severity, Map.get(attrs, "severity", :info)) |> to_string(),
      payload: attrs |> Map.get(:payload, Map.get(attrs, "payload", %{})) |> redact()
    }

    limit = Application.fetch_env!(:robine_wake, :telemetry_event_limit)
    existing = prune_events(state.events)
    totals = Map.update(state.totals, code, 1, &(&1 + 1))
    events = Enum.take([event | existing], limit)
    next = %{state | events: events, totals: totals}

    if event.severity == "critical", do: persist_critical(next)
    {:reply, event, next}
  end

  def handle_call({:recent, limit}, _from, state) do
    events = prune_events(state.events)
    next = %{state | events: events}
    {:reply, Enum.take(events, max(0, limit)), next}
  end

  def handle_call(:metrics, _from, state),
    do:
      {:reply, %{events_recorded: Enum.sum(Map.values(state.totals)), by_code: state.totals},
       state}

  def handle_call(:clear, _from, state) do
    next = %{state | events: [], totals: %{}}

    case persist_critical(next) do
      :ok -> {:reply, :ok, next}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp redact(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp redact(value) when is_map(value) do
    value
    |> Enum.reject(fn {key, _value} -> forbidden_key?(key) end)
    |> Map.new(fn {key, nested} -> {to_string(key), redact(nested)} end)
  end

  defp redact(value) when is_list(value), do: Enum.map(value, &redact/1)
  defp redact(value) when value in [true, false, nil], do: value
  defp redact(value) when is_atom(value), do: to_string(value)
  defp redact(value), do: value

  defp forbidden_key?(key) do
    normalized = key |> to_string() |> String.downcase()
    Enum.any?(@forbidden_fragments, &String.contains?(normalized, &1))
  end

  defp prune_events(events) do
    retention_days = Application.fetch_env!(:robine_wake, :telemetry_retention_days)
    cutoff = DateTime.add(Clock.utc_now(), -retention_days, :day)

    Enum.filter(events, fn event ->
      occurred_at = Map.get(event, :occurred_at_utc, Map.get(event, "occurred_at_utc"))

      case DateTime.from_iso8601(occurred_at || "") do
        {:ok, timestamp, _offset} -> DateTime.compare(timestamp, cutoff) != :lt
        _ -> false
      end
    end)
  end

  defp persist_critical(state) do
    critical_events =
      state.events
      |> Enum.filter(fn event ->
        Map.get(event, :severity, Map.get(event, "severity")) == "critical"
      end)
      |> Enum.take(100)

    Persistence.save(state.path, %{
      "schema_version" => 1,
      "critical_events" => critical_events,
      "updated_at" => DateTime.to_iso8601(Clock.utc_now())
    })
  end
end
