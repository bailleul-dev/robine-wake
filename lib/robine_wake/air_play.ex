defmodule RobineWake.AirPlay do
  @moduledoc """
  Supervises the target's AirPlay 2 receiver and arbitrates access to ALSA.

  Wake audio has hard priority: `suspend/0` frees the HiFiBerry device before
  an alarm opens it, and `resume/0` gives it back afterwards.

  Two receivers, chosen by `:airplay_receiver`:

    * `:shairport` — Shairport Sync, stopped on suspend. AirPlay 2 needs two
      helpers, kept running next to it, including while it is suspended:
      Avahi advertises the service (on the system D-Bus started by
      `RobineWake.BluetoothAudio`) and NQPTP provides the timing.
    * `:robine` — `robine-airplayd`, the project's own receiver, which
      advertises itself and follows PTP alone. It is driven through a port
      (JSON lines, see its README): on suspend it keeps its session and only
      releases ALSA, and it exits when the port closes.
  """

  use GenServer

  require Logger

  # A receiver that does not free ALSA within this delay is killed: it must
  # never hold up an alarm.
  @suspend_timeout_ms 1_000
  @max_line 8_192

  @type status :: %{
          enabled: boolean(),
          state: :disabled | :starting | :available | :suspended | :unavailable,
          receiver: :shairport | :robine,
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
      receiver: Application.get_env(:robine_wake, :airplay_receiver, :shairport),
      suspended: false,
      daemon: nil,
      port: nil,
      partial_line: "",
      session: nil,
      volume_db: nil,
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

  def handle_call(:suspend, _from, %{port: port} = state) when is_port(port) do
    state = cancel_restart(state)
    send_command(port, "suspend")

    state =
      case await_event(state, "suspended", @suspend_timeout_ms) do
        {:ok, state} ->
          state

        {:error, state} ->
          Logger.warning("robine-airplayd did not release ALSA in time; stopping it")
          stop_receiver(state)
      end

    {:reply, :ok, %{state | suspended: true, reason: nil}}
  end

  def handle_call(:suspend, _from, state) do
    state = state |> cancel_restart() |> stop_receiver()
    {:reply, :ok, %{state | suspended: true, reason: nil}}
  end

  def handle_call(:resume, _from, %{enabled: false} = state), do: {:reply, :ok, state}

  def handle_call(:resume, _from, %{suspended: true, port: port} = state) when is_port(port) do
    send_command(port, "resume")
    {:reply, :ok, %{state | suspended: false}}
  end

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
        is_port(state.port) -> :available
        is_pid(state.daemon) and Process.alive?(state.daemon) -> :available
        is_reference(state.restart_timer) -> :starting
        true -> :unavailable
      end

    status =
      public_state
      |> base_status(state.reason)
      |> Map.merge(%{
        receiver: state.receiver,
        session: state.session,
        volume_db: state.volume_db
      })

    {:reply, status, state}
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

  def handle_info({port, {:data, data}}, %{port: port} = state),
    do: {:noreply, receive_data(state, data)}

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    next = %{state | port: nil, partial_line: "", session: nil, reason: {:receiver_exit, status}}

    if state.suspended do
      {:noreply, next}
    else
      Logger.warning("robine-airplayd exited with status #{status}; scheduling restart")
      {:noreply, schedule_restart(next)}
    end
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
  defp start_receiver(%{port: port} = state) when is_port(port), do: state

  defp start_receiver(state) do
    if network_available?() do
      start_receiver_on_network(state)
    else
      Logger.info("AirPlay receiver is waiting for the network")
      schedule_restart(%{state | reason: :network_unavailable})
    end
  end

  defp start_receiver_on_network(%{receiver: :robine} = state) do
    executable = Application.fetch_env!(:robine_wake, :airplay_robine_executable)

    if File.exists?(executable) do
      args = [
        "--name",
        airplay_name(),
        "--device",
        Application.fetch_env!(:robine_wake, :airplay_device),
        "--data-dir",
        Application.fetch_env!(:robine_wake, :airplay_data_dir)
      ]

      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout,
          {:line, @max_line},
          {:args, args}
        ])

      Logger.info("AirPlay receiver #{airplay_name()} started (robine-airplayd)")
      %{state | port: port, reason: nil}
    else
      Logger.error("AirPlay receiver is unavailable: #{executable} was not found")
      schedule_restart(%{state | reason: :executable_not_found})
    end
  rescue
    exception ->
      Logger.error("Unable to start robine-airplayd: #{Exception.message(exception)}")
      schedule_restart(%{state | reason: {:start_failed, Exception.message(exception)}})
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
               env: Application.get_env(:robine_wake, :airplay_environment, []),
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

  defp stop_receiver(%{port: port} = state) when is_port(port) do
    # Closing stdin makes it exit; the kill, when available, covers a hung
    # process. Its `aplay` child then sees the end of its input and exits.
    with {:os_pid, pid} <- Port.info(port, :os_pid) do
      Port.close(port)

      if kill = System.find_executable("kill"),
        do: System.cmd(kill, ["-9", to_string(pid)], stderr_to_stdout: true)
    end

    %{state | port: nil, partial_line: "", session: nil}
  rescue
    # The port closed on its own in the meantime.
    ArgumentError -> %{state | port: nil, partial_line: "", session: nil}
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

  defp send_command(port, command) do
    Port.command(port, [Jason.encode!(%{"cmd" => command}), "\n"])
  end

  # Handles the port output until `event` arrives or the timeout expires.
  defp await_event(state, event, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    port = state.port

    receive do
      {^port, {:data, data}} ->
        {state, events} = collect_lines(state, data)
        state = Enum.reduce(events, state, &handle_event/2)

        if Enum.any?(events, &(&1["event"] == event)),
          do: {:ok, state},
          else: await_event(state, event, max(deadline - System.monotonic_time(:millisecond), 0))
    after
      timeout_ms -> {:error, state}
    end
  end

  defp receive_data(state, data) do
    {state, events} = collect_lines(state, data)
    Enum.reduce(events, state, &handle_event/2)
  end

  # Complete JSON lines are events; anything else is a log line.
  defp collect_lines(state, {:noeol, part}),
    do: {%{state | partial_line: state.partial_line <> part}, []}

  defp collect_lines(state, {:eol, part}) do
    line = state.partial_line <> part
    state = %{state | partial_line: ""}

    case Jason.decode(line) do
      {:ok, %{"event" => _} = event} ->
        {state, [event]}

      _ ->
        Logger.debug("robine-airplayd: " <> line)
        {state, []}
    end
  end

  defp handle_event(%{"event" => "session", "state" => session}, state),
    do: %{state | session: session}

  defp handle_event(%{"event" => "volume", "db" => db}, state), do: %{state | volume_db: db}

  defp handle_event(%{"event" => "error"} = event, state) do
    Logger.warning("robine-airplayd: #{inspect(Map.delete(event, "event"))}")
    state
  end

  defp handle_event(%{"event" => "stats"} = event, state) do
    Logger.debug("robine-airplayd stats: #{inspect(Map.delete(event, "event"))}")
    state
  end

  defp handle_event(_event, state), do: state

  defp base_status(state, reason) do
    %{
      enabled: Application.get_env(:robine_wake, :airplay_enabled, false),
      state: state,
      receiver: Application.get_env(:robine_wake, :airplay_receiver, :shairport),
      name: airplay_name(),
      protocol: :airplay_2,
      reason: reason
    }
  end

  defp airplay_name,
    do: Application.get_env(:robine_wake, :airplay_name, "Robine Wake Bedroom")
end
