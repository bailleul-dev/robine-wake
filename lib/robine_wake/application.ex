defmodule RobineWake.Application do
  @moduledoc false
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    config = Application.get_all_env(:robine_wake)
    _ = RobineWake.SoundLibrary.ensure_default()

    domain = [
      {Registry, keys: :unique, name: RobineWake.Registry},
      {Task.Supervisor, name: RobineWake.TaskSupervisor},
      RobineWake.Auth,
      RobineWake.MCP.RateLimiter,
      RobineWake.EventLog,
      RobineWake.Settings,
      RobineWake.EventStream,
      RobineWake.CommandCache,
      RobineWake.RemoteButton,
      RobineWake.Bluetooth.Server,
      RobineWake.ClockQuality,
      RobineWake.Network,
      RobineWake.GuideLight,
      RobineWake.Breathing,
      RobineWake.LightAmbience,
      RobineWake.AirPlay,
      RobineWake.BluetoothAudio,
      RobineWake.Audio,
      {DynamicSupervisor, strategy: :one_for_one, name: RobineWake.SessionSupervisor},
      RobineWake.SessionRecovery,
      RobineWake.Scheduler,
      RobineWakeWeb.CSRF
    ]

    domain =
      if config[:camera_enabled] do
        List.insert_at(domain, 15, RobineWake.Camera)
      else
        domain
      end

    # Host-only hooks: `boot_children` start before the domain (demo clock and
    # emulated hardware), `demo_children` after it (virtual remote, demo reset).
    children = dev_pubsub(config) ++ List.wrap(config[:boot_children]) ++ domain

    children =
      if config[:bluetooth_enabled] do
        children ++ [config[:bluetooth_driver]]
      else
        children
      end

    children = maybe_add_lora(children, config)

    children =
      if config[:web_enabled] do
        children ++
          [
            {Bandit,
             scheme: :http,
             plug: RobineWakeWeb.Router,
             ip: config[:web_ip],
             port: config[:web_port]}
          ]
      else
        children
      end

    children =
      if config[:dev_emulator_enabled] and config[:target] == :host do
        children ++ List.wrap(config[:demo_children]) ++ [RobineWakeDevWeb.Endpoint]
      else
        children
      end

    case Supervisor.start_link(children, strategy: :one_for_one, name: RobineWake.Supervisor) do
      {:ok, _supervisor} = started ->
        validate_running_firmware(config[:target])
        started

      other ->
        other
    end
  end

  defp dev_pubsub(config) do
    if config[:dev_emulator_enabled] and config[:target] == :host,
      do: [{Phoenix.PubSub, name: RobineWakeDev.PubSub}],
      else: []
  end

  defp maybe_add_lora(children, config) do
    if config[:lora_enabled] do
      children ++
        [
          {RobineWake.LoRa.Server,
           driver: config[:lora_driver], driver_options: config[:lora_options] || []}
        ]
    else
      children
    end
  end

  defp validate_running_firmware(:host), do: :ok

  defp validate_running_firmware(_target) do
    if Nerves.Runtime.firmware_validation_status() == :unvalidated do
      Nerves.Runtime.validate_firmware()
    else
      :ok
    end
  rescue
    exception ->
      Logger.error("Unable to validate the running firmware: #{Exception.message(exception)}")
      :error
  catch
    :exit, reason ->
      Logger.error("Unable to validate the running firmware: #{inspect(reason)}")
      :error
  end
end
