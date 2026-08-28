defmodule RobineWake.LoRa.TestDriver do
  @moduledoc false
  @behaviour RobineWake.LoRa.Driver

  @impl true
  def open(options) do
    {:ok,
     %{
       owner: Keyword.fetch!(options, :owner),
       packets: options |> Keyword.get(:packets, []) |> :queue.from_list()
     }}
  end

  @impl true
  def receive_packet(%{packets: packets} = state) do
    case :queue.out(packets) do
      {{:value, payload}, remaining} ->
        {:ok, payload, %{rssi_dbm: -72, snr_db: 8.5}, %{state | packets: remaining}}

      {:empty, _packets} ->
        {:ok, nil, state}
    end
  end

  @impl true
  def transmit(payload, state) do
    send(state.owner, {:lora_transmit, payload})
    {:ok, state}
  end

  @impl true
  def close(_state), do: :ok
end
