defmodule RobineWake.Bluetooth.Server do
  @moduledoc "Newline-framed command ingress and paged-read-v1 response transport."

  use GenServer

  alias RobineWake.Bluetooth.Command

  @maximum_command_bytes 65_536
  @page_bytes 480
  @header_bytes 20
  @payload_bytes @page_bytes - @header_bytes
  @transport_version 1

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def receive_chunk(chunk) when is_binary(chunk),
    do: GenServer.call(__MODULE__, {:receive_chunk, chunk})

  def response, do: GenServer.call(__MODULE__, :response)
  def next_response_chunk, do: GenServer.call(__MODULE__, :next_response_chunk)

  @impl true
  def init(_opts) do
    response = encode(%{"v" => 1, "id" => nil, "status" => "ok", "body" => %{"ready" => true}})

    {:ok,
     %{
       buffer: <<>>,
       response: response,
       response_offset: 0,
       response_sequence: 0,
       response_crc32: :erlang.crc32(response)
     }}
  end

  @impl true
  def handle_call(:response, _from, state), do: {:reply, state.response <> "\n", state}

  def handle_call(:next_response_chunk, _from, state) do
    total = byte_size(state.response)
    remaining = total - state.response_offset
    payload_size = min(max(remaining, 0), @payload_bytes)
    payload = binary_part(state.response, state.response_offset, payload_size)
    page_index = div(state.response_offset, @payload_bytes)
    page_count = max(1, ceil_div(total, @payload_bytes))
    next_offset = state.response_offset + payload_size
    flags = if next_offset >= total, do: 0x01, else: 0x00

    header =
      <<"RW", @transport_version, flags, state.response_sequence::unsigned-big-32,
        page_index::unsigned-big-16, page_count::unsigned-big-16, total::unsigned-big-32,
        state.response_crc32::unsigned-big-32>>

    {:reply, header <> payload, %{state | response_offset: next_offset}}
  end

  def handle_call({:receive_chunk, chunk}, _from, state) do
    buffer = state.buffer <> chunk

    if byte_size(buffer) > @maximum_command_bytes do
      response =
        encode(%{
          "v" => 1,
          "id" => nil,
          "status" => "error",
          "error" => %{"code" => "command_too_large"}
        })

      {:reply, :ok, state |> Map.put(:buffer, <<>>) |> put_response(response)}
    else
      parts = :binary.split(buffer, "\n", [:global])
      remainder = List.last(parts)

      frames = parts |> Enum.drop(-1) |> Enum.reject(&(&1 == <<>>))

      next_state = process_frames(frames, remainder, state)

      {:reply, :ok, next_state}
    end
  end

  defp process_frames([], remainder, state), do: %{state | buffer: remainder}

  defp process_frames(frames, remainder, state) do
    response = Enum.reduce(frames, state.response, fn frame, _previous -> execute(frame) end)
    state |> Map.put(:buffer, remainder) |> put_response(response)
  end

  defp put_response(state, response) do
    sequence = rem(state.response_sequence + 1, 0x1_0000_0000)

    %{
      state
      | response: response,
        response_offset: 0,
        response_sequence: sequence,
        response_crc32: :erlang.crc32(response)
    }
  end

  defp execute(frame) do
    case Jason.decode(frame) do
      {:ok, command} ->
        command |> Command.execute() |> encode()

      {:error, _reason} ->
        encode(%{
          "v" => 1,
          "id" => nil,
          "status" => "error",
          "error" => %{"code" => "invalid_json"}
        })
    end
  end

  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)
  defp encode(value), do: Jason.encode!(value)
end
