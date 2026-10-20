defmodule RobineWakeDev.Demo do
  @moduledoc """
  Seeds and resets the shared demo instance.

  A reset is a factory reset through the domain functions (the same steps as
  the `device.factory_reset` command, the admin password aside), then the
  demo setup a visitor would otherwise do in the app: create a 07:00 alarm
  whose dawn rises on the LED strip, pair the virtual remote, and put the
  clock back to the evening at real speed.

  It runs at boot, from the "Reset demo" button, and every
  `ROBINE_DEMO_RESET_HOURS` hours.
  """

  use GenServer

  require Logger

  alias RobineWake.{Alarm, Breathing, ClockQuality, EventLog, RemoteButton, Scheduler, Settings}
  alias RobineWakeDev.Clock.Scaled
  alias RobineWakeDev.{Hardware, VirtualRemote}

  @timezone "Europe/Paris"
  @evening ~T[22:30:00]
  @lead_minutes 5

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def reset, do: GenServer.call(__MODULE__, :reset, 30_000)

  @doc "Jumps the clock to #{@lead_minutes} minutes before the next dawn starts."
  def jump_before_alarm, do: GenServer.call(__MODULE__, :jump_before_alarm, 30_000)

  def set_speed(speed) do
    with :ok <- Scaled.set_speed(speed) do
      Hardware.clock_changed()
      :ok
    end
  end

  @impl true
  def init(opts) do
    hours =
      Keyword.get(opts, :reset_hours, Application.get_env(:robine_wake, :demo_reset_hours, 6))

    {:ok, %{reset_ms: if(hours > 0, do: :timer.hours(hours)), timer: nil}, {:continue, :reset}}
  end

  @impl true
  def handle_continue(:reset, state), do: {:noreply, do_reset(state)}

  @impl true
  def handle_call(:reset, _from, state), do: {:reply, :ok, do_reset(state)}

  def handle_call(:jump_before_alarm, _from, state) do
    now = Scaled.utc_now()

    reply =
      case next_dawn(now) do
        nil ->
          {:error, :no_alarm}

        starts_at ->
          target = DateTime.add(starts_at, -@lead_minutes, :minute)
          :ok = Scaled.advance(max(DateTime.diff(target, now, :millisecond), 0))
          _status = Scheduler.tick()
          Hardware.clock_changed()
          :ok
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_info(:periodic_reset, state), do: {:noreply, do_reset(state)}

  defp do_reset(state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    stop_sessions()
    :ok = Settings.reset()
    :ok = RemoteButton.reset()
    {:ok, _breathing} = Breathing.stop()
    :ok = EventLog.clear()
    :ok = Hardware.reset()

    :ok = Scaled.set_speed(1)
    :ok = Scaled.set_utc(evening())
    _result = ClockQuality.confirm()

    with {:ok, _alarm} <- Settings.create_alarm(demo_alarm()),
         :ok <- VirtualRemote.pair() do
      :ok
    else
      error -> Logger.error("Demo seeding failed: #{inspect(error)}")
    end

    _status = Scheduler.refresh()
    Hardware.clock_changed()

    timer = if state.reset_ms, do: Process.send_after(self(), :periodic_reset, state.reset_ms)
    %{state | timer: timer}
  end

  defp stop_sessions do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(RobineWake.SessionSupervisor),
        is_pid(pid),
        do: DynamicSupervisor.terminate_child(RobineWake.SessionSupervisor, pid)
  end

  defp demo_alarm do
    %{
      label: "Demo · Réveil",
      local_time: "07:00:00",
      days_of_week: Enum.to_list(1..7),
      timezone: @timezone,
      sound_id: "jungle_sunrise",
      strong_sound_id: "wake_up_call",
      prewake_seconds: 1_200,
      light_profile: %{enabled: true, end_behavior: :off}
    }
  end

  # Today at 22:30, Paris time: the evening, before the breathing session.
  defp evening do
    DateTime.utc_now()
    |> DateTime.shift_zone!(@timezone)
    |> DateTime.to_date()
    |> DateTime.new!(@evening, @timezone)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp next_dawn(now) do
    Settings.list_alarms()
    |> Enum.filter(& &1.enabled)
    |> Enum.flat_map(fn alarm ->
      case Alarm.next_occurrence(alarm, now) do
        {:ok, occurrence} -> [DateTime.add(occurrence, -alarm.prewake_seconds, :second)]
        _ -> []
      end
    end)
    |> Enum.filter(&(DateTime.compare(&1, now) == :gt))
    |> Enum.min(DateTime, fn -> nil end)
  end
end
