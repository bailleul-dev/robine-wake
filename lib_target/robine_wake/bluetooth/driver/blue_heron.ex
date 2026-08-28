defmodule RobineWake.Bluetooth.Driver.BlueHeron do
  @moduledoc "Open BLE GATT transport for the feature-first prototype."

  use GenServer
  require Logger

  alias BlueHeron.GATT.{Characteristic, Service}
  alias RobineWake.Bluetooth.Server

  @service_uuid 0x8AD00001A7A94EF7A25967C9C65E4C10
  @command_uuid 0x8AD00002A7A94EF7A25967C9C65E4C10
  @response_uuid 0x8AD00003A7A94EF7A25967C9C65E4C10

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    register_services()
    send(self(), :advertise)
    {:ok, %{advertising: false}}
  end

  @impl true
  def handle_info(:advertise, state) do
    case advertise() do
      :ok ->
        Logger.info("Robine Wake Bluetooth service is advertising")
        {:noreply, %{state | advertising: true}}

      {:error, reason} ->
        Logger.warning("Bluetooth advertising is not ready: #{inspect(reason)}")
        Process.send_after(self(), :advertise, 2_000)
        {:noreply, state}
    end
  end

  defp register_services do
    BlueHeron.Peripheral.add_service(
      Service.new(%{
        id: :gap,
        type: 0x1800,
        characteristics: [
          Characteristic.new(%{id: {:gap, :device_name}, type: 0x2A00, properties: 0x02}),
          Characteristic.new(%{id: {:gap, :appearance}, type: 0x2A01, properties: 0x02})
        ],
        read: fn
          {:gap, :device_name} -> "Robine Wake"
          {:gap, :appearance} -> <<0::little-16>>
        end
      })
    )

    BlueHeron.Peripheral.add_service(
      Service.new(%{
        id: :gatt,
        type: 0x1801,
        characteristics: [
          Characteristic.new(%{
            id: {:gatt, :service_changed},
            type: 0x2A05,
            properties: 0x20
          })
        ]
      })
    )

    BlueHeron.Peripheral.add_service(
      Service.new(%{
        id: :robine_wake,
        type: @service_uuid,
        characteristics: [
          Characteristic.new(%{
            id: {:robine_wake, :command},
            type: @command_uuid,
            properties: 0x08
          }),
          Characteristic.new(%{
            id: {:robine_wake, :response},
            type: @response_uuid,
            properties: 0x02
          })
        ],
        read: fn
          {:robine_wake, :response} -> Server.next_response_chunk()
          _characteristic -> <<>>
        end,
        write: fn
          {:robine_wake, :command}, value -> Server.receive_chunk(value)
          _characteristic, _value -> :ok
        end
      })
    )
  end

  defp advertise do
    flags =
      BlueHeron.AdvertisingData.flags(
        le_general_discoverable_mode: true,
        br_edr_not_supported: true
      )

    short_name = BlueHeron.AdvertisingData.short_name("Robine")

    service =
      BlueHeron.AdvertisingData.incomplete_list_of_service_uuids([@service_uuid])

    with :ok <- stop_advertising(),
         :ok <- BlueHeron.Broadcaster.set_advertising_data(flags <> short_name <> service),
         :ok <-
           BlueHeron.Broadcaster.set_scan_response_data(
             BlueHeron.AdvertisingData.complete_name("Robine Wake")
           ),
         :ok <- BlueHeron.Broadcaster.start_advertising() do
      :ok
    end
  catch
    :exit, reason -> {:error, reason}
  end

  # Some controllers return Command Disallowed when advertising is already off.
  # For setup purposes that is the desired state, so make the operation idempotent.
  defp stop_advertising do
    case BlueHeron.Broadcaster.stop_advertising() do
      :ok -> :ok
      {:error, :command_disallowed} -> :ok
      other -> other
    end
  end
end
