defmodule RobineWake.CommandCache do
  @moduledoc "Bounded idempotency cache shared by the HTTP and Bluetooth command transports."

  use GenServer

  @maximum_entries 256

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def execute(request_id, fingerprint, function)
      when is_binary(request_id) and is_binary(fingerprint) and is_function(function, 0) do
    GenServer.call(__MODULE__, {:execute, request_id, fingerprint, function}, 30_000)
  end

  @impl true
  def init(_opts), do: {:ok, %{entries: %{}, order: :queue.new()}}

  @impl true
  def handle_call({:execute, request_id, fingerprint, function}, _from, state) do
    case state.entries[request_id] do
      %{fingerprint: ^fingerprint, response: response} ->
        {:reply, {:ok, response}, state}

      %{fingerprint: _different} ->
        {:reply, {:error, :request_id_reused}, state}

      nil ->
        response = function.()
        next = put_entry(state, request_id, fingerprint, response)
        {:reply, {:ok, response}, next}
    end
  end

  defp put_entry(state, request_id, fingerprint, response) do
    entries = Map.put(state.entries, request_id, %{fingerprint: fingerprint, response: response})
    order = :queue.in(request_id, state.order)

    if map_size(entries) > @maximum_entries do
      {{:value, oldest}, order} = :queue.out(order)
      %{entries: Map.delete(entries, oldest), order: order}
    else
      %{entries: entries, order: order}
    end
  end
end
