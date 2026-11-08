defmodule RobineWake.NightRadio.Driver.Host do
  @moduledoc false
  @behaviour RobineWake.NightRadio.Driver

  @impl true
  def set_silenced(silenced) when is_boolean(silenced) do
    case Application.get_env(:robine_wake, :host_night_radio_failure) do
      nil ->
        Application.put_env(:robine_wake, :host_night_radio_silenced, silenced)
        :ok

      reason ->
        {:error, reason}
    end
  end

  @impl true
  def status do
    silenced = Application.get_env(:robine_wake, :host_night_radio_silenced, false)

    %{
      source: :host_simulator,
      radios:
        Enum.map(["wlan", "bluetooth"], fn type ->
          %{type: type, name: type, soft_blocked: silenced, hard_blocked: false}
        end)
    }
  end
end
