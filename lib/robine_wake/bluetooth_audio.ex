defmodule RobineWake.BluetoothAudio do
  @moduledoc """
  Supervises the target's Bluetooth A2DP sink and arbitrates its access to ALSA.

  The radio stack (D-Bus, BlueZ, BlueALSA and an auto-accepting pairing agent)
  runs on the onboard controller and stays up across alarms, so a phone
  keeps its link. Only `bluealsa-aplay`, the single process that opens the
  HiFiBerry, is stopped by `suspend/0` before wake audio and restarted by
  `resume/0` afterwards.

  Any stack daemon exit tears the whole stack down and restarts it after a
  delay; the player restarts on its own. Failures are reported through
  `status/0` and never propagate to the alarm path.
  """

  use GenServer

  require Logger

  alias RobineWake.Audio.Driver.Alsa

  @codecs ["aac", "aptx", "aptx-hd"]
  @bus_socket "/run/dbus/system_bus_socket"
  @bus_poll_ms 100
  @bus_poll_attempts 50
  @stage_delay_ms 1_000

  @type status :: %{
          enabled: boolean(),
          state: :disabled | :starting | :available | :suspended | :unavailable,
          name: String.t(),
          protocol: :a2dp_sink,
          codecs: [String.t()],
          adapter: :present | :missing,
          reason: nil | term()
        }

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def suspend, do: call_if_running(:suspend)
  def resume, do: call_if_running(:resume)

  @spec status() :: status()
  def status do
    case Process.whereis(__MODULE__) do
      nil -> base_status(:unavailable, :not_started)
      _pid -> GenServer.call(__MODULE__, :status)
    end
  end

  @doc false
  def bluealsa_args do
    ["--profile=a2dp-sink", "--loglevel=info"] ++ Enum.map(@codecs, &("--codec=" <> &1))
  end

  @doc false
  def player_args(device) do
    ["--pcm=" <> device, "--volume=software", "--single-audio", "--loglevel=info"]
  end

  @impl true
  def init(_opts) do
    enabled = Application.get_env(:robine_wake, :bluetooth_audio_enabled, false)

    state = %{
      enabled: enabled,
      suspended: false,
      stage: :idle,
      generation: 0,
      daemons: %{},
      agent: nil,
      player: nil,
      restart_timer: nil,
      reason: nil
    }

    Process.flag(:trap_exit, true)

    if enabled, do: {:ok, state, {:continue, :start}}, else: {:ok, state}
  end

  @impl true
  def handle_continue(:start, state), do: {:noreply, start_stack(state)}

  @impl true
  def handle_call(:suspend, _from, %{enabled: false} = state), do: {:reply, :ok, state}

  def handle_call(:suspend, _from, state) do
    {:reply, :ok, %{stop_player(state) | suspended: true}}
  end

  def handle_call(:resume, _from, %{enabled: false} = state), do: {:reply, :ok, state}

  def handle_call(:resume, _from, %{suspended: true} = state) do
    next = maybe_start_player(%{state | suspended: false})
    {:reply, :ok, next}
  end

  def handle_call(:resume, _from, state), do: {:reply, :ok, state}

  def handle_call(:status, _from, state) do
    {:reply, base_status(public_state(state), state.reason), state}
  end

  @impl true
  def handle_info({:await_bus, generation, attempt}, %{generation: generation} = state) do
    cond do
      File.exists?(@bus_socket) ->
        {:noreply, start_stage(state, :bluetoothd, :bluealsa)}

      attempt >= @bus_poll_attempts ->
        {:noreply, fail_stack(state, :dbus_socket_timeout)}

      true ->
        Process.send_after(self(), {:await_bus, generation, attempt + 1}, @bus_poll_ms)
        {:noreply, state}
    end
  end

  def handle_info({:stage, generation, :bluealsa}, %{generation: generation} = state) do
    {:noreply, start_stage(state, :bluealsa, :ready)}
  end

  def handle_info({:stage, generation, :ready}, %{generation: generation} = state) do
    case start_agent(state) do
      {:ok, next} ->
        Logger.info("Bluetooth audio receiver #{receiver_name()} started")
        {:noreply, maybe_start_player(%{next | stage: :running, reason: nil})}

      {:error, reason} ->
        {:noreply, fail_stack(state, reason)}
    end
  end

  def handle_info({:restart_player, generation}, %{generation: generation} = state) do
    {:noreply, maybe_start_player(state)}
  end

  def handle_info(:restart, state) do
    {:noreply, start_stack(%{state | restart_timer: nil})}
  end

  def handle_info({agent, {:data, {_eol, line}}}, %{agent: agent} = state) do
    Logger.debug("Bluetooth agent: " <> line)
    if String.contains?(line, "Agent registered"), do: configure_agent(agent)
    {:noreply, state}
  end

  def handle_info({agent, {:exit_status, status}}, %{agent: agent} = state) do
    {:noreply, fail_stack(%{state | agent: nil}, {:agent_exit, status})}
  end

  def handle_info({:EXIT, agent, reason}, %{agent: agent} = state) when is_port(agent) do
    {:noreply, fail_stack(%{state | agent: nil}, {:agent_exit, reason})}
  end

  def handle_info({:EXIT, player, reason}, %{player: player} = state) when is_pid(player) do
    Logger.warning("Bluetooth audio player exited with reason #{inspect(reason)}")
    next = %{state | player: nil, reason: {:player_exit, reason}}

    if not next.suspended and next.stage == :running do
      delay = Application.fetch_env!(:robine_wake, :bluetooth_audio_restart_delay_ms)
      Process.send_after(self(), {:restart_player, next.generation}, delay)
    end

    {:noreply, next}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    case Enum.find(state.daemons, fn {_name, daemon} -> daemon == pid end) do
      {name, _daemon} ->
        Logger.warning("Bluetooth #{name} exited with reason #{inspect(reason)}")
        daemons = Map.delete(state.daemons, name)
        {:noreply, fail_stack(%{state | daemons: daemons}, {:daemon_exit, name, reason})}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = stop_stack(state)
    :ok
  end

  defp start_stack(%{enabled: false} = state), do: state
  defp start_stack(%{stage: stage} = state) when stage != :idle, do: state

  defp start_stack(state) do
    case missing_executable() do
      nil ->
        prepare_runtime()
        state = %{state | stage: :starting, generation: state.generation + 1}

        case start_daemon(state, :dbus) do
          {:ok, next} ->
            Process.send_after(self(), {:await_bus, next.generation, 0}, @bus_poll_ms)
            next

          {:error, reason} ->
            fail_stack(state, reason)
        end

      path ->
        Logger.error("Bluetooth audio receiver is unavailable: #{path} was not found")
        schedule_restart(%{state | reason: {:executable_not_found, path}})
    end
  end

  defp start_stage(state, daemon, next_stage) do
    case start_daemon(state, daemon) do
      {:ok, next} ->
        Process.send_after(self(), {:stage, next.generation, next_stage}, @stage_delay_ms)
        next

      {:error, reason} ->
        fail_stack(state, reason)
    end
  end

  defp start_daemon(state, name) do
    {executable, args} = daemon_command(name)

    case MuonTrap.Daemon.start_link(executable, args,
           stderr_to_stdout: true,
           log_output: :debug,
           log_prefix: "Bluetooth #{name}: ",
           delay_to_sigkill: 500
         ) do
      {:ok, pid} -> {:ok, %{state | daemons: Map.put(state.daemons, name, pid)}}
      {:error, reason} -> {:error, {:start_failed, name, reason}}
    end
  rescue
    exception -> {:error, {:start_failed, name, Exception.message(exception)}}
  end

  defp daemon_command(:dbus),
    do: {executable(:dbus_daemon), ["--system", "--nofork", "--nopidfile"]}

  defp daemon_command(:bluetoothd), do: {executable(:bluetoothd), ["--nodetach"]}
  defp daemon_command(:bluealsa), do: {executable(:bluealsa), bluealsa_args()}

  # bluetoothctl keeps the "auto" agent registered for as long as it runs; it
  # needs an open stdin, which MuonTrap does not provide, hence a raw port.
  defp start_agent(state) do
    port =
      Port.open({:spawn_executable, executable(:bluetoothctl)}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 1_024},
        args: ["--agent", "auto"]
      ])

    {:ok, %{state | agent: port}}
  rescue
    exception -> {:error, {:start_failed, :agent, Exception.message(exception)}}
  end

  defp configure_agent(agent) do
    Port.command(agent, "default-agent\npairable on\ndiscoverable on\n")
  end

  defp maybe_start_player(%{stage: :running, suspended: false, player: nil} = state) do
    device = Alsa.output_device()

    case MuonTrap.Daemon.start_link(executable(:player), player_args(device),
           stderr_to_stdout: true,
           log_output: :debug,
           log_prefix: "Bluetooth player: ",
           delay_to_sigkill: 500
         ) do
      {:ok, player} ->
        %{state | player: player}

      {:error, reason} ->
        Logger.error("Unable to start Bluetooth audio player: #{inspect(reason)}")
        delay = Application.fetch_env!(:robine_wake, :bluetooth_audio_restart_delay_ms)
        Process.send_after(self(), {:restart_player, state.generation}, delay)
        %{state | reason: {:player_start_failed, reason}}
    end
  rescue
    exception ->
      Logger.error("Unable to start Bluetooth audio player: #{Exception.message(exception)}")
      %{state | reason: {:player_start_failed, Exception.message(exception)}}
  end

  defp maybe_start_player(state), do: state

  defp fail_stack(state, reason) do
    Logger.error("Bluetooth audio receiver stopped: #{inspect(reason)}")
    state |> stop_stack() |> Map.put(:reason, reason) |> schedule_restart()
  end

  defp stop_stack(state) do
    state = stop_player(state)
    stop_agent(state.agent)

    Enum.each([:bluealsa, :bluetoothd, :dbus], fn name ->
      if pid = state.daemons[name], do: safe_stop(pid)
    end)

    %{
      state
      | stage: :idle,
        generation: state.generation + 1,
        daemons: %{},
        agent: nil
    }
  end

  defp stop_player(%{player: nil} = state), do: state

  defp stop_player(%{player: player} = state) do
    safe_stop(player)
    %{state | player: nil}
  end

  defp stop_agent(nil), do: :ok

  defp stop_agent(port) do
    Port.command(port, "quit\n")
    Port.close(port)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp safe_stop(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1_500)
  catch
    :exit, reason ->
      Logger.warning("Unable to stop Bluetooth process cleanly: #{inspect(reason)}")
  end

  # bluetoothd keeps pairing keys under /var/lib/bluetooth, a symlink to the
  # persistent data partition; D-Bus needs its socket directory and a machine id.
  defp prepare_runtime do
    storage = Application.fetch_env!(:robine_wake, :bluetooth_audio_storage_path)

    with :ok <- File.mkdir_p(storage), do: File.chmod(storage, 0o700)
    File.mkdir_p("/run/dbus")
    File.mkdir_p("/tmp/dbus")
    run_quietly(executable(:dbus_uuidgen), ["--ensure"])

    if modprobe = System.find_executable("modprobe"), do: run_quietly(modprobe, ["hci_uart"])
    :ok
  end

  defp run_quietly(executable, args) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> Logger.warning("#{executable} exited #{status}: #{String.trim(output)}")
    end
  rescue
    exception -> Logger.warning("#{executable} failed: #{Exception.message(exception)}")
  end

  defp missing_executable do
    [:dbus_daemon, :dbus_uuidgen, :bluetoothd, :bluealsa, :player, :bluetoothctl]
    |> Enum.map(&executable/1)
    |> Enum.find(&(not File.exists?(&1)))
  end

  defp executable(name),
    do: Map.fetch!(Application.fetch_env!(:robine_wake, :bluetooth_audio_executables), name)

  defp schedule_restart(%{restart_timer: timer} = state) when is_reference(timer), do: state

  defp schedule_restart(state) do
    delay = Application.fetch_env!(:robine_wake, :bluetooth_audio_restart_delay_ms)
    %{state | restart_timer: Process.send_after(self(), :restart, delay)}
  end

  defp public_state(%{enabled: false}), do: :disabled
  defp public_state(%{stage: :starting}), do: :starting
  defp public_state(%{stage: :idle, restart_timer: timer}) when is_reference(timer), do: :starting
  defp public_state(%{stage: :idle}), do: :unavailable

  defp public_state(state) do
    cond do
      adapter() == :missing -> :unavailable
      state.suspended -> :suspended
      is_pid(state.player) -> :available
      true -> :starting
    end
  end

  defp adapter do
    case File.ls("/sys/class/bluetooth") do
      {:ok, entries} ->
        if Enum.any?(entries, &String.starts_with?(&1, "hci")), do: :present, else: :missing

      {:error, _reason} ->
        :missing
    end
  end

  defp call_if_running(message) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.call(__MODULE__, message)
    end
  end

  defp base_status(state, reason) do
    adapter = adapter()

    %{
      enabled: Application.get_env(:robine_wake, :bluetooth_audio_enabled, false),
      state: state,
      name: receiver_name(),
      protocol: :a2dp_sink,
      codecs: ["sbc" | @codecs],
      adapter: adapter,
      reason: reason || adapter_reason(state, adapter)
    }
  end

  defp adapter_reason(:unavailable, :missing), do: :adapter_not_found
  defp adapter_reason(_state, _adapter), do: nil

  defp receiver_name,
    do: Application.get_env(:robine_wake, :bluetooth_audio_name, "Robine Wake Bedroom")
end
