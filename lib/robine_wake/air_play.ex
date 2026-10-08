defmodule RobineWake.AirPlay do
  @moduledoc """
  Supervises the target's Shairport Sync receiver and arbitrates access to ALSA.

  Wake audio has hard priority: `suspend/0` stops the receiver before an alarm
  opens the HiFiBerry device, and `resume/0` advertises it again afterwards.

  AirPlay 2 needs two helpers, kept running next to the receiver, including
  while it is suspended: Avahi advertises the service (on the system D-Bus
  started by `RobineWake.BluetoothAudio`) and NQPTP provides the timing.
  """

  use GenServer

  require Logger

  @type status :: %{
          enabled: boolean(),
          state: :disabled | :starting | :available | :suspended | :unavailable,
          name: String.t(),
          protocol: :airplay_2,
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

  @impl true
  def init(_opts) do
    enabled = Application.get_env(:robine_wake, :airplay_enabled, false)

    state = %{
      enabled: enabled,
      suspended: false,
      daemon: nil,
      ptp: nil,
      mdns: nil,
      restart_timer: nil,
      reason: nil
    }

    Process.flag(:trap_exit, true)

    if enabled, do: {:ok, state, {:continue, :start}}, else: {:ok, state}
  end

  @impl true
  def handle_continue(:start, state), do: {:noreply, start_receiver(state)}

  @impl true
  def handle_call(:suspend, _from, %{enabled: false} = state), do: {:reply, :ok, state}

  def handle_call(:suspend, _from, state) do
    state = state |> cancel_restart() |> stop_receiver()
    {:reply, :ok, %{state | suspended: true, reason: nil}}
  end

  def handle_call(:resume, _from, %{enabled: false} = state), do: {:reply, :ok, state}

  def handle_call(:resume, _from, %{suspended: true} = state) do
    next = start_receiver(%{state | suspended: false})
    {:reply, :ok, next}
  end

  def handle_call(:resume, _from, state), do: {:reply, :ok, state}

  def handle_call(:status, _from, state) do
    public_state =
      cond do
        not state.enabled -> :disabled
        state.suspended -> :suspended
        is_pid(state.daemon) and Process.alive?(state.daemon) -> :available
        is_reference(state.restart_timer) -> :starting
        true -> :unavailable
      end

    {:reply, base_status(public_state, state.reason), state}
  end

  @impl true
  def handle_info({:EXIT, daemon, reason}, %{daemon: daemon} = state) do
    next = %{state | daemon: nil, reason: {:receiver_exit, reason}}

    if state.suspended do
      {:noreply, next}
    else
      Logger.warning("Shairport Sync exited with reason #{inspect(reason)}; scheduling restart")
      {:noreply, schedule_restart(next)}
    end
  end

  def handle_info({:EXIT, ptp, reason}, %{ptp: ptp} = state) do
    Logger.warning("NQPTP exited with reason #{inspect(reason)}; scheduling restart")
    delay = Application.fetch_env!(:robine_wake, :airplay_restart_delay_ms)
    Process.send_after(self(), :restart_ptp, delay)
    {:noreply, %{state | ptp: nil}}
  end

  def handle_info({:EXIT, mdns, reason}, %{mdns: mdns} = state) do
    Logger.warning("Avahi exited with reason #{inspect(reason)}; restarting the AirPlay receiver")
    next = state |> cancel_restart() |> stop_receiver()
    {:noreply, schedule_restart(%{next | mdns: nil, reason: {:mdns_exit, reason}})}
  end

  def handle_info(:restart_ptp, state), do: {:noreply, ensure_ptp(state)}

  def handle_info(:restart, state) do
    {:noreply, start_receiver(%{state | restart_timer: nil})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = stop_receiver(state)
    if is_pid(state.ptp), do: safe_stop_daemon(state.ptp)
    if is_pid(state.mdns), do: safe_stop_daemon(state.mdns)
    :ok
  end

  defp start_receiver(%{enabled: false} = state), do: state
  defp start_receiver(%{suspended: true} = state), do: state
  defp start_receiver(%{daemon: daemon} = state) when is_pid(daemon), do: state

  defp start_receiver(state) do
    if network_available?() do
      start_receiver_on_network(state)
    else
      Logger.info("AirPlay receiver is waiting for the network")
      schedule_restart(%{state | reason: :network_unavailable})
    end
  end

  defp start_receiver_on_network(state) do
    executable = Application.fetch_env!(:robine_wake, :airplay_executable)
    config_path = Application.fetch_env!(:robine_wake, :airplay_config_path)

    cond do
      not File.exists?(executable) ->
        Logger.error("AirPlay receiver is unavailable: #{executable} was not found")
        schedule_restart(%{state | reason: :executable_not_found})

      not File.exists?(config_path) ->
        Logger.error("AirPlay receiver is unavailable: #{config_path} was not found")
        schedule_restart(%{state | reason: :config_not_found})

      not File.exists?(Application.fetch_env!(:robine_wake, :airplay_bus_socket)) ->
        schedule_restart(%{state | reason: :dbus_unavailable})

      true ->
        state = state |> ensure_mdns() |> ensure_ptp()

        case MuonTrap.Daemon.start_link(executable, ["-c", config_path],
               stderr_to_stdout: true,
               log_output: :debug,
               log_prefix: "Shairport Sync: ",
               delay_to_sigkill: 500
             ) do
          {:ok, daemon} ->
            Logger.info("AirPlay receiver #{airplay_name()} started")
            %{state | daemon: daemon, reason: nil}

          {:error, reason} ->
            Logger.error("Unable to start AirPlay receiver: #{inspect(reason)}")
            schedule_restart(%{state | reason: {:start_failed, reason}})
        end
    end
  rescue
    exception ->
      Logger.error("Unable to start AirPlay receiver: #{Exception.message(exception)}")
      schedule_restart(%{state | reason: {:start_failed, Exception.message(exception)}})
  end

  defp ensure_ptp(%{ptp: ptp} = state) when is_pid(ptp), do: state

  defp ensure_ptp(state) do
    executable = Application.fetch_env!(:robine_wake, :airplay_ptp_executable)
    %{state | ptp: start_helper(executable, [], "NQPTP")}
  end

  defp ensure_mdns(%{mdns: mdns} = state) when is_pid(mdns), do: state

  defp ensure_mdns(state) do
    executable = Application.fetch_env!(:robine_wake, :airplay_mdns_executable)
    %{state | mdns: start_helper(executable, ["--no-drop-root"], "Avahi")}
  end

  defp start_helper(executable, args, name) do
    with true <- File.exists?(executable),
         {:ok, daemon} <-
           MuonTrap.Daemon.start_link(executable, args,
             stderr_to_stdout: true,
             log_output: :debug,
             log_prefix: name <> ": ",
             delay_to_sigkill: 500
           ) do
      daemon
    else
      false ->
        Logger.warning("AirPlay 2 helper #{name} is unavailable: #{executable} was not found")
        nil

      {:error, reason} ->
        Logger.error("Unable to start #{name}: #{inspect(reason)}")
        nil
    end
  end

  defp network_available? do
    case RobineWake.Network.status() do
      %{state: :available, ipv4_addresses: []} -> false
      %{state: :available} -> true
      _status -> false
    end
  catch
    :exit, _reason -> false
  end

  defp stop_receiver(%{daemon: nil} = state), do: state

  defp stop_receiver(%{daemon: daemon} = state) do
    safe_stop_daemon(daemon)
    %{state | daemon: nil}
  end

  defp safe_stop_daemon(daemon) do
    if Process.alive?(daemon), do: GenServer.stop(daemon, :normal, 1_500)
  catch
    :exit, reason -> Logger.warning("Unable to stop AirPlay receiver cleanly: #{inspect(reason)}")
  end

  defp schedule_restart(%{restart_timer: timer} = state) when is_reference(timer), do: state

  defp schedule_restart(state) do
    delay = Application.fetch_env!(:robine_wake, :airplay_restart_delay_ms)
    %{state | restart_timer: Process.send_after(self(), :restart, delay)}
  end

  defp cancel_restart(%{restart_timer: nil} = state), do: state

  defp cancel_restart(%{restart_timer: timer} = state) do
    _ = Process.cancel_timer(timer)
    %{state | restart_timer: nil}
  end

  defp call_if_running(message) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.call(__MODULE__, message)
    end
  end

  defp base_status(state, reason) do
    %{
      enabled: Application.get_env(:robine_wake, :airplay_enabled, false),
      state: state,
      name: airplay_name(),
      protocol: :airplay_2,
      reason: reason
    }
  end

  defp airplay_name,
    do: Application.get_env(:robine_wake, :airplay_name, "Robine Wake Bedroom")
end
