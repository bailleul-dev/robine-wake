defmodule RobineWake.LoRa.Driver do
  @moduledoc false

  @type metadata :: %{optional(:rssi_dbm) => number(), optional(:snr_db) => number()}
  @type state :: term()

  @callback open(keyword()) :: {:ok, state()} | {:error, term()}
  @callback receive_packet(state()) ::
              {:ok, nil, state()}
              | {:ok, binary(), metadata(), state()}
              | {:error, term(), state()}
  @callback transmit(binary(), state()) :: {:ok, state()} | {:error, term(), state()}
  @callback close(state()) :: :ok
end
