defmodule RobineWake.NightRadio.Driver.Rfkill do
  @moduledoc """
  Kernel rfkill soft blocks for the onboard Wi-Fi (`wlan`) and Bluetooth radios.

  A soft block is not persisted on Nerves: every boot starts unblocked.
  Ethernet and the SPI LoRa receiver are not rfkill devices and stay on.
  On unblock, wpa_supplicant reassociates and BlueZ powers the adapter back
  on by itself (measured on the Pi 3: about 5 s for Wi-Fi).
  """

  @behaviour RobineWake.NightRadio.Driver

  @default_root "/sys/class/rfkill"
  @default_types ["wlan", "bluetooth"]

  @impl true
  def set_silenced(silenced) when is_boolean(silenced) do
    value = if silenced, do: "1", else: "0"

    with [_ | _] = radios <- radios(),
         [] <- Enum.flat_map(radios, &write_soft(&1, value)) do
      :ok
    else
      [] -> {:error, :no_radio}
      failures -> {:error, {:rfkill_write_failed, failures}}
    end
  end

  defp write_soft(radio, value) do
    case File.write(Path.join(radio.path, "soft"), value) do
      :ok -> []
      {:error, reason} -> [{radio.name, reason}]
    end
  end

  @impl true
  def status do
    %{
      source: :rfkill,
      radios:
        Enum.map(radios(), fn radio ->
          %{
            type: radio.type,
            name: radio.name,
            soft_blocked: read(radio.path, "soft") == "1",
            hard_blocked: read(radio.path, "hard") == "1"
          }
        end)
    }
  end

  defp radios do
    root = Application.get_env(:robine_wake, :rfkill_root, @default_root)
    types = Application.get_env(:robine_wake, :night_radio_types, @default_types)

    root
    |> Path.join("rfkill*")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn path -> %{path: path, type: read(path, "type"), name: read(path, "name")} end)
    |> Enum.filter(&(&1.type in types))
  end

  defp read(path, attribute) do
    case File.read(Path.join(path, attribute)) do
      {:ok, content} -> String.trim(content)
      {:error, _reason} -> nil
    end
  end
end
