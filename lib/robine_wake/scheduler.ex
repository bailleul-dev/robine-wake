defmodule RobineWake.Scheduler do
  @moduledoc false
  use GenServer

  alias RobineWake.{Alarm, Clock, ClockQuality, Settings, WakeSession}

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def trigger_now(alarm_id), do: GenServer.call(__MODULE__, {:trigger_now, alarm_id})

  def trigger_strong_test(alarm_id),
    do: GenServer.call(__MODULE__, {:trigger_strong_test, alarm_id})

  def status, do: GenServer.call(__MODULE__, :status)
  def tick, do: GenServer.call(__MODULE__, :tick)
  def refresh, do: GenServer.call(__MODULE__, :refresh)

  @impl true
  def init(_opts) do
    state = %{schedule: %{}, last_tick_at: nil, errors: [], triggers: 0}
    send(self(), :refresh)
    {:ok, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    next = refresh(state)
    schedule_tick()
    {:noreply, next}
  end

  def handle_info(:settings_changed, state), do: {:noreply, refresh(state)}

  def handle_info(:time_quality_changed, state) do
    next = state |> refresh() |> run_tick()
    {:noreply, next}
  end

  def handle_info(:tick, state) do
    next = run_tick(state)
    schedule_tick()
    {:noreply, next}
  end

  @impl true
  def handle_call(:tick, _from, state) do
    next = run_tick(state)
    {:reply, status_map(next), next}
  end

  def handle_call(:status, _from, state), do: {:reply, status_map(state), state}

  def handle_call(:refresh, _from, state) do
    next = refresh(state)
    {:reply, status_map(next), next}
  end

  def handle_call({:trigger_now, alarm_id}, _from, state) do
    with {:ok, alarm} <- Settings.get_alarm(alarm_id),
         scheduled_for = DateTime.add(Clock.utc_now(), alarm.prewake_seconds, :second),
         {:ok, pid} <- WakeSession.start(alarm, scheduled_for) do
      {:reply, {:ok, pid}, %{state | triggers: state.triggers + 1}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:trigger_strong_test, alarm_id}, _from, state) do
    with {:ok, alarm} <- Settings.get_alarm(alarm_id),
         {:ok, pid} <- WakeSession.start_strong_test(alarm, Clock.utc_now()) do
      {:reply, {:ok, pid}, %{state | triggers: state.triggers + 1}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp run_tick(state) do
    now = Clock.utc_now()

    if ClockQuality.trusted?() do
      run_trusted_tick(state, now)
    else
      WakeSession.tick()
      %{state | last_tick_at: now}
    end
  end

  defp run_trusted_tick(state, now) do
    {schedule, errors, trigger_count} =
      Enum.reduce(state.schedule, {%{}, state.errors, 0}, &advance_schedule_entry(&1, &2, now))

    WakeSession.tick()

    %{
      state
      | schedule: schedule,
        errors: Enum.take(errors, 20),
        last_tick_at: now,
        triggers: state.triggers + trigger_count
    }
  end

  defp advance_schedule_entry({alarm_id, entry}, {next, errors, count}, now) do
    case DateTime.compare(entry.starts_at, now) do
      :gt ->
        {Map.put(next, alarm_id, entry), errors, count}

      _due ->
        {new_entry, new_errors, triggered} =
          fire_and_advance(alarm_id, entry, errors, now)

        {put_entry(next, alarm_id, new_entry), new_errors, count + triggered}
    end
  end

  defp put_entry(schedule, _alarm_id, nil), do: schedule
  defp put_entry(schedule, alarm_id, entry), do: Map.put(schedule, alarm_id, entry)

  defp fire_and_advance(alarm_id, entry, errors, now) do
    case Settings.get_alarm(alarm_id) do
      {:ok, alarm} ->
        {errors, triggered} = trigger_occurrence(alarm, entry, errors, now)
        next = following_entry(alarm, entry.scheduled_for)

        {next, errors, triggered}

      {:error, :not_found} ->
        {nil, errors, 0}
    end
  end

  defp trigger_occurrence(alarm, entry, errors, now) do
    cond do
      Settings.session_recorded?(alarm.id, entry.scheduled_for) ->
        {errors, 0}

      catch_up_expired?(entry.scheduled_for, now) ->
        record_missed(alarm, entry.scheduled_for, :catch_up_expired)
        {errors, 0}

      true ->
        start_session(alarm, entry.scheduled_for, errors)
    end
  end

  defp catch_up_expired?(occurrence, now) do
    catch_up = Application.fetch_env!(:robine_wake, :catch_up_seconds)
    DateTime.diff(now, occurrence, :second) > catch_up
  end

  defp following_entry(%{enabled: true, one_shot_date: nil} = alarm, scheduled_for) do
    case Alarm.next_occurrence(alarm, DateTime.add(scheduled_for, 1, :second)) do
      {:ok, datetime} -> schedule_entry(alarm, datetime)
      _error -> nil
    end
  end

  defp following_entry(_alarm, _scheduled_for), do: nil

  defp refresh(state) do
    catch_up = Application.fetch_env!(:robine_wake, :catch_up_seconds)
    now = Clock.utc_now()

    schedule =
      Settings.list_alarms()
      |> Enum.filter(& &1.enabled)
      |> Enum.reduce(%{}, fn alarm, acc ->
        from = DateTime.add(now, -(catch_up + alarm.prewake_seconds), :second)
        maybe_record_expired_occurrence(alarm, DateTime.add(now, -catch_up, :second))

        case Alarm.next_occurrence(alarm, from) do
          {:ok, occurrence} -> Map.put(acc, alarm.id, schedule_entry(alarm, occurrence))
          _ -> acc
        end
      end)

    %{state | schedule: schedule}
  end

  defp start_session(alarm, occurrence, errors) do
    case WakeSession.start(alarm, occurrence) do
      {:ok, _pid} ->
        if alarm.one_shot_date,
          do: Settings.update_alarm(alarm.id, %{enabled: false, revision: alarm.revision})

        {errors, 1}

      {:error, :active_session} ->
        record_missed(alarm, occurrence, :another_session_active)
        {[{:active_session, alarm.id, occurrence} | errors], 0}

      {:error, reason} ->
        {[{reason, alarm.id, occurrence} | errors], 0}
    end
  end

  defp maybe_record_expired_occurrence(alarm, catch_up_start) do
    with {:ok, previous} <- Alarm.previous_occurrence(alarm, catch_up_start),
         true <- DateTime.compare(previous, alarm.created_at) in [:eq, :gt],
         false <- Settings.session_recorded?(alarm.id, previous) do
      record_missed(alarm, previous, :catch_up_expired)
    else
      _ -> :ok
    end
  end

  defp record_missed(alarm, occurrence, reason) do
    result = Settings.record_missed_if_current(alarm.id, alarm.revision, occurrence, reason)

    if result == :recorded and alarm.one_shot_date do
      Settings.update_alarm(alarm.id, %{enabled: false, revision: alarm.revision})
    end

    result
  end

  defp status_map(state) do
    trusted = ClockQuality.trusted?()

    %{
      state: if(trusted, do: :healthy, else: :degraded),
      armed: trusted,
      next:
        Map.new(state.schedule, fn {id, entry} ->
          {id, DateTime.to_iso8601(entry.scheduled_for)}
        end),
      last_tick_at: state.last_tick_at,
      errors: state.errors,
      triggers: state.triggers
    }
  end

  defp schedule_entry(alarm, scheduled_for) do
    %{
      scheduled_for: scheduled_for,
      starts_at: DateTime.add(scheduled_for, -alarm.prewake_seconds, :second)
    }
  end

  defp schedule_tick do
    Process.send_after(
      self(),
      :tick,
      Application.fetch_env!(:robine_wake, :scheduler_interval_ms)
    )
  end
end
