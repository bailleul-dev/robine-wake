defmodule RobineWake.LoRa.Driver.SX1276 do
  @moduledoc false

  @behaviour RobineWake.LoRa.Driver

  import Bitwise

  @register_fifo 0x00
  @register_op_mode 0x01
  @register_frequency_msb 0x06
  @register_pa_config 0x09
  @register_lna 0x0C
  @register_fifo_address_pointer 0x0D
  @register_fifo_tx_base 0x0E
  @register_fifo_rx_base 0x0F
  @register_fifo_rx_current 0x10
  @register_irq_flags 0x12
  @register_rx_bytes 0x13
  @register_packet_snr 0x19
  @register_packet_rssi 0x1A
  @register_modem_config_1 0x1D
  @register_modem_config_2 0x1E
  @register_preamble_msb 0x20
  @register_payload_length 0x22
  @register_max_payload_length 0x23
  @register_modem_config_3 0x26
  @register_sync_word 0x39
  @register_version 0x42

  @mode_lora_sleep 0x80
  @mode_lora_standby 0x81
  @mode_lora_transmit 0x83
  @mode_lora_receive_continuous 0x85

  @irq_rx_done 0x40
  @irq_payload_crc_error 0x20
  @irq_tx_done 0x08
  @expected_version 0x12
  @oscillator_hz 32_000_000
  @maximum_packet_bytes 255
  @transmit_timeout_ms 3_000

  @impl true
  def open(options) do
    bus_name = Keyword.get(options, :spi_bus, "spidev0.0")

    case Circuits.SPI.open(bus_name, mode: 0, speed_hz: 4_000_000) do
      {:ok, spi} -> initialize(spi, options)
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def receive_packet(%{spi: spi} = state) do
    with {:ok, flags} <- read_register(spi, @register_irq_flags) do
      cond do
        band(flags, @irq_rx_done) == 0 ->
          {:ok, nil, state}

        band(flags, @irq_payload_crc_error) != 0 ->
          :ok = write_register(spi, @register_irq_flags, flags)
          {:ok, nil, state}

        true ->
          receive_ready_packet(spi, flags, state)
      end
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl true
  def transmit(payload, %{spi: spi} = state)
      when is_binary(payload) and byte_size(payload) <= @maximum_packet_bytes do
    result =
      with :ok <- write_register(spi, @register_op_mode, @mode_lora_standby),
           :ok <- write_register(spi, @register_fifo_address_pointer, 0),
           :ok <- write_burst(spi, @register_fifo, payload),
           :ok <- write_register(spi, @register_payload_length, byte_size(payload)),
           :ok <- write_register(spi, @register_irq_flags, 0xFF),
           :ok <- write_register(spi, @register_op_mode, @mode_lora_transmit),
           :ok <- await_transmit(spi, System.monotonic_time(:millisecond)) do
        :ok
      end

    _ = resume_receive(spi)

    case result do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  def transmit(_payload, state), do: {:error, :lora_packet_too_large, state}

  @impl true
  def close(%{spi: spi}), do: Circuits.SPI.close(spi)

  defp configure(spi, options) do
    frequency = Keyword.get(options, :frequency_hz, 868_100_000)
    spreading_factor = Keyword.get(options, :spreading_factor, 9)
    coding_rate = Keyword.get(options, :coding_rate, 5)
    bandwidth = Keyword.get(options, :bandwidth_hz, 125_000)
    sync_word = Keyword.get(options, :sync_word, 0x12)
    tx_power = Keyword.get(options, :tx_power_dbm, 14)

    with {:ok, bandwidth_bits} <- bandwidth_bits(bandwidth),
         :ok <- validate_radio_options(spreading_factor, coding_rate, sync_word, tx_power) do
      frequency_register = div(frequency * 524_288 + div(@oscillator_hz, 2), @oscillator_hz)
      modem_config_1 = bor(bsl(bandwidth_bits, 4), bsl(coding_rate - 4, 1))
      modem_config_2 = bor(bsl(spreading_factor, 4), 0x04)

      low_data_rate_optimization =
        if symbol_duration_ms(spreading_factor, bandwidth) > 16, do: 0x08, else: 0

      modem_config_3 = bor(0x04, low_data_rate_optimization)
      pa_config = bor(0x80, max(0, min(15, tx_power - 2)))

      with :ok <- write_register(spi, @register_op_mode, @mode_lora_sleep),
           :ok <-
             write_register(spi, @register_frequency_msb, band(bsr(frequency_register, 16), 0xFF)),
           :ok <-
             write_register(
               spi,
               @register_frequency_msb + 1,
               band(bsr(frequency_register, 8), 0xFF)
             ),
           :ok <- write_register(spi, @register_frequency_msb + 2, band(frequency_register, 0xFF)),
           :ok <- write_register(spi, @register_fifo_tx_base, 0),
           :ok <- write_register(spi, @register_fifo_rx_base, 0),
           :ok <- write_register(spi, @register_lna, 0x23),
           :ok <- write_register(spi, @register_modem_config_1, modem_config_1),
           :ok <- write_register(spi, @register_modem_config_2, modem_config_2),
           :ok <- write_register(spi, @register_modem_config_3, modem_config_3),
           :ok <- write_register(spi, @register_preamble_msb, 0),
           :ok <- write_register(spi, @register_preamble_msb + 1, 8),
           :ok <- write_register(spi, @register_max_payload_length, @maximum_packet_bytes),
           :ok <- write_register(spi, @register_sync_word, sync_word),
           :ok <- write_register(spi, @register_pa_config, pa_config),
           :ok <- write_register(spi, @register_irq_flags, 0xFF) do
        resume_receive(spi)
      end
    end
  end

  defp initialize(spi, options) do
    result =
      with {:ok, version} <- read_register(spi, @register_version),
           :ok <- require_version(version),
           :ok <- configure(spi, options) do
        {:ok, %{spi: spi, options: options}}
      end

    case result do
      {:ok, _state} = ready ->
        ready

      {:error, _reason} = error ->
        :ok = Circuits.SPI.close(spi)
        error
    end
  end

  defp receive_ready_packet(spi, flags, state) do
    with {:ok, byte_count} <- read_register(spi, @register_rx_bytes),
         {:ok, current_address} <- read_register(spi, @register_fifo_rx_current),
         :ok <- write_register(spi, @register_fifo_address_pointer, current_address),
         {:ok, payload} <- read_burst(spi, @register_fifo, byte_count),
         {:ok, raw_snr} <- read_register(spi, @register_packet_snr),
         {:ok, raw_rssi} <- read_register(spi, @register_packet_rssi),
         :ok <- write_register(spi, @register_irq_flags, flags) do
      metadata = %{
        snr_db: signed_byte(raw_snr) / 4,
        rssi_dbm: -157 + raw_rssi
      }

      {:ok, payload, metadata, state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp resume_receive(spi) do
    with :ok <- write_register(spi, @register_fifo_address_pointer, 0),
         :ok <- write_register(spi, @register_irq_flags, 0xFF) do
      write_register(spi, @register_op_mode, @mode_lora_receive_continuous)
    end
  end

  defp await_transmit(spi, started_at) do
    with {:ok, flags} <- read_register(spi, @register_irq_flags) do
      cond do
        band(flags, @irq_tx_done) != 0 ->
          write_register(spi, @register_irq_flags, @irq_tx_done)

        System.monotonic_time(:millisecond) - started_at >= @transmit_timeout_ms ->
          {:error, :lora_transmit_timeout}

        true ->
          Process.sleep(5)
          await_transmit(spi, started_at)
      end
    end
  end

  defp read_register(spi, address) do
    case Circuits.SPI.transfer(spi, <<band(address, 0x7F), 0>>) do
      {:ok, <<_ignored, value>>} -> {:ok, value}
      {:ok, response} -> {:error, {:invalid_spi_response, response}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_register(spi, address, value) do
    case Circuits.SPI.transfer(spi, <<bor(address, 0x80), band(value, 0xFF)>>) do
      {:ok, <<_ignored, _value>>} -> :ok
      {:ok, response} -> {:error, {:invalid_spi_response, response}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_burst(_spi, _address, 0), do: {:ok, <<>>}

  defp read_burst(spi, address, count) do
    case Circuits.SPI.transfer(spi, [<<band(address, 0x7F)>>, :binary.copy(<<0>>, count)]) do
      {:ok, <<_ignored, payload::binary-size(^count)>>} -> {:ok, payload}
      {:ok, response} -> {:error, {:invalid_spi_response, response}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_burst(spi, address, payload) do
    case Circuits.SPI.transfer(spi, [<<bor(address, 0x80)>>, payload]) do
      {:ok, response} when byte_size(response) == byte_size(payload) + 1 -> :ok
      {:ok, response} -> {:error, {:invalid_spi_response, response}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp bandwidth_bits(125_000), do: {:ok, 7}
  defp bandwidth_bits(value), do: {:error, {:unsupported_lora_bandwidth, value}}

  defp require_version(@expected_version), do: :ok
  defp require_version(version), do: {:error, {:unexpected_sx1276_version, version}}

  defp validate_radio_options(sf, cr, sync, power)
       when sf in 7..12 and cr in 5..8 and sync in 0..255 and power in 2..17,
       do: :ok

  defp validate_radio_options(_sf, _cr, _sync, _power), do: {:error, :invalid_lora_options}

  defp symbol_duration_ms(spreading_factor, bandwidth),
    do: :math.pow(2, spreading_factor) / bandwidth * 1_000

  defp signed_byte(value) when value >= 128, do: value - 256
  defp signed_byte(value), do: value
end
