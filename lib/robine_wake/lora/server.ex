defmodule RobineWake.LoRa.Server do
  @moduledoc "Always-on authenticated LoRa receiver for the remote alarm button."

  use GenServer
  require Logger

  alias RobineWake.LoRa.Protocol

  @poll_interval_ms 25
  @retry_interval_ms 5_000
  @cache_ttl_ms 300_000
  @maximum_cache_entries 32

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    server_options = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_options)
  end

  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  def safe_status do
    case Process.whereis(__MODULE__) do
      nil -> %{state: :disabled, frequency_hz: configured_frequency()}
      _pid -> status()
    end
  catch
    :exit, reason ->
      %{state: :unavailable, frequency_hz: configured_frequency(), last_error: inspect(reason)}
  end

  @impl true
  def init(opts) do
    state = %{
      driver: Keyword.fetch!(opts, :driver),
      driver_options: Keyword.get(opts, :driver_options, []),
      radio: nil,
      state: :starting,
      last_error: nil,
      packets_received: 0,
      packets_rejected: 0,
      last_packet_at: nil,
      frequency_hz: Keyword.get(Keyword.get(opts, :driver_options, []), :frequency_hz),
      cache: %{}
    }

    send(self(), :open)
    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     Map.take(state, [
       :state,
       :last_error,
       :packets_received,
       :packets_rejected,
       :last_packet_at,
       :frequency_hz
     ]), state}
  end

  @impl true
  def handle_info(:open, %{driver: driver, driver_options: options} = state) do
    case driver.open(options) do
      {:ok, radio} ->
        Logger.info("LoRa receiver ready")
        schedule_poll(0)
        {:noreply, %{state | radio: radio, state: :listening, last_error: nil}}

      {:error, reason} ->
        Logger.error("Unable to start LoRa receiver: #{inspect(reason)}")
        Process.send_after(self(), :open, @retry_interval_ms)
        {:noreply, %{state | state: :unavailable, last_error: inspect(reason)}}
    end
  end

  def handle_info(:poll, %{radio: nil} = state), do: {:noreply, state}

  def handle_info(:poll, state) do
    case state.driver.receive_packet(state.radio) do
      {:ok, nil, radio} ->
        schedule_poll()
        {:noreply, %{state | radio: radio}}

      {:ok, payload, metadata, radio} ->
        next = process_packet(payload, metadata, %{state | radio: radio})
        schedule_poll()
        {:noreply, next}

      {:error, reason, radio} ->
        Logger.warning("LoRa receive error: #{inspect(reason)}")
        schedule_poll(250)
        {:noreply, %{state | radio: radio, state: :degraded, last_error: inspect(reason)}}
    end
  end

  @impl true
  def terminate(_reason, %{radio: nil}), do: :ok
  def terminate(_reason, state), do: state.driver.close(state.radio)

  defp process_packet(payload, metadata, state) do
    now = System.monotonic_time(:millisecond)
    cache = prune_cache(state.cache, now)
    key = Protocol.request_key(payload)

    {result, cache} =
      case cache do
        %{^key => {_expires_at, response}} ->
          {{:ok, response}, cache}

        _ ->
          case Protocol.handle(payload) do
            {:ok, response} = ok ->
              {ok, put_cache(cache, key, now + @cache_ttl_ms, response)}

            {:error, _reason} = error ->
              {error, cache}
          end
      end

    case result do
      {:ok, response} ->
        case state.driver.transmit(response, state.radio) do
          {:ok, radio} ->
            %{
              state
              | radio: radio,
                state: :listening,
                last_error: nil,
                packets_received: state.packets_received + 1,
                last_packet_at: DateTime.utc_now() |> DateTime.to_iso8601(),
                cache: cache
            }

          {:error, reason, radio} ->
            %{state | radio: radio, state: :degraded, last_error: inspect(reason), cache: cache}
        end

      {:error, reason} ->
        Logger.warning("Rejected LoRa packet: #{inspect(reason)}; metadata=#{inspect(metadata)}")
        %{state | packets_rejected: state.packets_rejected + 1, cache: cache}
    end
  end

  defp put_cache(cache, key, expires_at, response) do
    cache = Map.put(cache, key, {expires_at, response})

    if map_size(cache) <= @maximum_cache_entries do
      cache
    else
      {oldest_key, _entry} = Enum.min_by(cache, fn {_key, {expiry, _response}} -> expiry end)
      Map.delete(cache, oldest_key)
    end
  end

  defp prune_cache(cache, now) do
    Map.reject(cache, fn {_key, {expires_at, _response}} -> expires_at <= now end)
  end

  defp schedule_poll(delay \\ @poll_interval_ms), do: Process.send_after(self(), :poll, delay)

  defp configured_frequency do
    :robine_wake
    |> Application.get_env(:lora_options, [])
    |> Keyword.get(:frequency_hz)
  end
end
