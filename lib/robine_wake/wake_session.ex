defmodule RobineWake.WakeSession do
  @moduledoc false
  use GenServer

  alias RobineWake.{Alarm, Audio, Clock, EventLog, EventStream, Hue, Id, Settings}

  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :id)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  def start(alarm) do
    start(alarm, DateTime.add(Clock.utc_now(), alarm.prewake_seconds, :second))
  end

  def start(alarm, scheduled_for) do
    start_with_phase(alarm, scheduled_for, :gentle, false)
  end

  def start_test(alarm, scheduled_for) do
    start_with_phase(alarm, scheduled_for, :gentle, true)
  end

  def start_strong_test(alarm, scheduled_for \\ Clock.utc_now()) do
    start_with_phase(alarm, scheduled_for, :strong, true)
  end

  defp start_with_phase(alarm, scheduled_for, phase, test_mode) do
    case active_pid() do
      nil ->
        id = Id.generate()

        DynamicSupervisor.start_child(
          RobineWake.SessionSupervisor,
          {__MODULE__,
           id: id,
           alarm: alarm,
           scheduled_for: scheduled_for,
           start_phase: phase,
           test_mode: test_mode}
        )

      _pid ->
        {:error, :active_session}
    end
  end

  def restore(alarm, session) do
    case active_pid() do
      nil ->
        DynamicSupervisor.start_child(
          RobineWake.SessionSupervisor,
          {__MODULE__,
           id: session["id"],
           alarm: alarm,
           scheduled_for: session["scheduled_for"],
           restore: session}
        )

      _pid ->
        {:error, :active_session}
    end
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {RobineWake.Registry, :active_session}}
    )
  end

  def active do
    case active_pid() do
      nil ->
        nil

      pid ->
        if Process.alive?(pid), do: safe_status(pid), else: nil
    end
  end

  def dismiss(reason \\ :manual) do
    case call_active({:dismiss, reason}) do
      {:error, :no_active_session} ->
        {:ok, %{state: :idle, terminal_reason: :already_inactive}}

      result ->
        result
    end
  end

  def snooze, do: call_active(:snooze)

  def observe(observation) do
    case active_pid() do
      nil -> :ok
      pid -> GenServer.cast(pid, {:observation, observation})
    end
  end

  def observe_sync(observation) do
    case active_pid() do
      nil -> :ok
      pid -> GenServer.call(pid, {:observation, observation})
    end
  end

  def audio_failed(reason) do
    case active_pid() do
      nil -> :ok
      pid -> GenServer.cast(pid, {:audio_failed, reason})
    end
  end

  def tick do
    case active_pid() do
      nil -> :ok
      pid -> send(pid, :tick)
    end
  end

  def tick_sync, do: call_active(:tick)

  @impl true
  def init(opts) do
    context = initialization_context(opts)
    initial = initial_state(context)
    record = session_record(context)
    persistence_result = persist_initial_session(context.restored, record)

    complete_initialization(persistence_result, initial, context)
  end

  defp initialization_context(opts) do
    alarm = Keyword.fetch!(opts, :alarm)
    restored = Keyword.get(opts, :restore)
    now = Clock.utc_now()
    restored_started_at = restored_datetime(restored, "started_at") || now
    snooze_remaining_ms = restored_snooze_remaining(restored, now)

    test_mode =
      if restored,
        do: restored["test_mode"] in [true, "true"],
        else: Keyword.get(opts, :test_mode, false)

    %{
      alarm: alarm,
      id: Keyword.fetch!(opts, :id),
      scheduled_for: normalize_datetime(Keyword.fetch!(opts, :scheduled_for)),
      restored: restored,
      requested_phase: Keyword.get(opts, :start_phase, :gentle),
      now: now,
      monotonic: Clock.monotonic_ms(),
      restored_started_at: restored_started_at,
      elapsed_ms: max(0, DateTime.diff(now, restored_started_at, :millisecond)),
      snooze_remaining_ms: snooze_remaining_ms,
      restored_snoozed?: snooze_remaining_ms > 0,
      test_mode: test_mode,
      smartphone_dismiss_allowed: test_mode or Settings.smartphone_dismiss_enabled()
    }
  end

  defp initial_state(context) do
    %{
      id: context.id,
      alarm: context.alarm,
      alarm_id: context.alarm.id,
      scheduled_for: context.scheduled_for,
      state: if(context.restored_snoozed?, do: :snoozed, else: :starting),
      started_at: context.restored_started_at,
      started_monotonic: context.monotonic - context.elapsed_ms,
      ringing_since: context.monotonic,
      last_tick_monotonic: context.monotonic,
      audible_ms: restored_integer(context.restored, "audible_ms", context.elapsed_ms),
      exit_candidate_since: nil,
      snooze_until: snooze_deadline(context),
      snooze_until_utc: restored_snooze_deadline(context),
      snooze_count: restored_snooze_count(context.restored),
      current_gain: 0,
      audio_phase: :gentle,
      requested_phase: context.requested_phase,
      last_observation: nil,
      terminal_reason: nil,
      audio_error: nil,
      test_mode: context.test_mode,
      smartphone_dismiss_allowed: context.smartphone_dismiss_allowed
    }
  end

  defp session_record(context) do
    %{
      id: context.id,
      alarm_id: context.alarm.id,
      scheduled_for: context.scheduled_for,
      started_at: context.now,
      state: :starting,
      test_mode: context.test_mode,
      snooze_count: 0
    }
  end

  defp persist_initial_session(nil, record), do: Settings.record_session(record)
  defp persist_initial_session(restored, _record), do: {:ok, restored}

  defp complete_initialization(persistence_result, initial, context) do
    case persistence_result do
      {:ok, _} ->
        EventLog.emit(:wake_session_started, %{
          source: :wake_session,
          session_id: context.id,
          alarm_id: context.alarm.id,
          payload: %{scheduled_for: context.scheduled_for}
        })

        resume_initial_state(initial, context.restored_snoozed?)

      {:error, reason} ->
        {:stop, {:persistence_failed, reason}}
    end
  end

  defp resume_initial_state(initial, true) do
    send(self(), :resume_snoozed)
    EventStream.publish("session.changed")
    {:ok, initial}
  end

  defp resume_initial_state(initial, false) do
    next = begin_ringing(initial)
    schedule_tick()
    EventStream.publish("session.changed")
    {:ok, next}
  end

  defp snooze_deadline(%{restored_snoozed?: true} = context),
    do: context.monotonic + context.snooze_remaining_ms

  defp snooze_deadline(_context), do: nil

  defp restored_snooze_deadline(%{restored_snoozed?: true, restored: restored}),
    do: restored["snooze_until_utc"]

  defp restored_snooze_deadline(_context), do: nil

  defp restored_snooze_count(nil), do: 0
  defp restored_snooze_count(restored), do: restored["snooze_count"] || 0

  @impl true
  def handle_info(:begin_ringing, state) do
    next = begin_ringing(state)
    schedule_tick()
    EventStream.publish("session.changed")
    {:noreply, next}
  end

  def handle_info(:resume_snoozed, state) do
    schedule_tick()
    {:noreply, state}
  end

  def handle_info(:tick, state) do
    now = Clock.monotonic_ms()

    case advance(state, now) do
      {:continue, next} ->
        schedule_tick()
        {:noreply, next}

      {:stop, next} ->
        {:stop, :normal, next}
    end
  end

  @impl true
  def handle_cast({:observation, observation}, state) do
    next = apply_observation(%{state | last_observation: observation}, observation)
    {:noreply, next}
  end

  def handle_cast({:audio_failed, reason}, state) do
    next = %{state | state: :failed_safe, audio_error: reason}
    persist_state(next)

    EventLog.emit(:audio_failed,
      source: :wake_session,
      severity: :critical,
      session_id: state.id,
      alarm_id: state.alarm_id,
      payload: %{reason: reason}
    )

    {:noreply, next}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, public(state), state}

  def handle_call({:observation, observation}, _from, state) do
    next = apply_observation(%{state | last_observation: observation}, observation)
    {:reply, :ok, next}
  end

  def handle_call(:tick, _from, state) do
    case advance(state, Clock.monotonic_ms()) do
      {:continue, next} -> {:reply, {:ok, public(next)}, next}
      {:stop, next} -> {:stop, :normal, {:completed, public(next)}, next}
    end
  end

  def handle_call({:dismiss, reason}, _from, state) do
    if not state.test_mode and remote_dismiss_reason?(reason) and
         (not Settings.remote_dismiss_enabled?() or not state.smartphone_dismiss_allowed) do
      {:reply, {:error, :smartphone_dismiss_disabled}, state}
    else
      next = complete(state, reason)
      {:stop, :normal, {:ok, public(next)}, next}
    end
  end

  def handle_call(:snooze, _from, state) do
    snooze = state.alarm.snooze

    cond do
      state.state == :snoozed ->
        {:reply, {:ok, public(state)}, state}

      not snooze.enabled ->
        {:reply, {:error, :snooze_disabled}, state}

      state.snooze_count >= snooze.maximum ->
        {:reply, {:error, :snooze_limit}, state}

      state.state not in [:ringing, :exit_candidate, :failed_safe] ->
        {:reply, {:error, :invalid_state}, state}

      true ->
        :ok = Audio.stop(state.id)
        Hue.snooze(state.id)
        until = Clock.monotonic_ms() + snooze.duration_seconds * 1_000
        until_utc = DateTime.add(Clock.utc_now(), snooze.duration_seconds, :second)

        next = %{
          state
          | state: :snoozed,
            snooze_until: until,
            snooze_until_utc: DateTime.to_iso8601(until_utc),
            snooze_count: state.snooze_count + 1,
            exit_candidate_since: nil,
            current_gain: 0,
            audio_phase: :gentle
        }

        persist_state(next)

        EventLog.emit(:session_snoozed,
          source: :wake_session,
          session_id: state.id,
          alarm_id: state.alarm_id,
          payload: %{snooze_count: next.snooze_count, duration_seconds: snooze.duration_seconds}
        )

        EventStream.publish("session.changed")

        {:reply, {:ok, public(next)}, next}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state.state not in [:dismissed, :timed_out], do: Audio.stop(state.id)
    if state.state not in [:dismissed, :timed_out], do: Hue.finish_wake(state.id, :restore)
    EventStream.publish("session.changed")
    :ok
  end

  defp begin_ringing(state) do
    strong? = state.requested_phase == :strong

    start_gain =
      if strong?, do: strong_gain(state.alarm), else: state.alarm.volume_profile.start

    sound_id = if strong?, do: state.alarm.strong_sound_id, else: state.alarm.sound_id
    now = Clock.monotonic_ms()
    utc_now = Clock.utc_now()

    light_profile = %{
      state.alarm.light_profile
      | start_brightness: 1,
        ramp_seconds: state.alarm.prewake_seconds
    }

    Hue.start_wake(state.id, light_profile)

    with :ok <- Audio.play(state.id, sound_id),
         :ok <- Audio.set_gain(state.id, start_gain) do
      if strong?, do: Hue.strong_wake(state.id)

      next = %{
        state
        | state: :ringing,
          ringing_since: ringing_since(state, strong?, now, utc_now),
          last_tick_monotonic: now,
          current_gain: start_gain,
          audio_phase: if(strong?, do: :strong, else: :gentle),
          audio_error: nil
      }

      persist_state(next)

      EventLog.emit(:audio_started,
        source: :wake_session,
        session_id: state.id,
        alarm_id: state.alarm_id,
        payload: %{phase: next.audio_phase, sound_id: sound_id, gain: start_gain}
      )

      next
    else
      {:error, reason} -> fail_audio(state, reason)
    end
  end

  defp apply_observation(state, %{state: :vacant, confidence: confidence})
       when confidence >= 0.0 do
    threshold = Application.fetch_env!(:robine_wake, :exit_confidence)
    grace = Application.fetch_env!(:robine_wake, :exit_grace_ms)
    grace_elapsed? = Clock.monotonic_ms() - state.started_monotonic >= grace

    if grace_elapsed? and confidence >= threshold and
         state.state in [:ringing, :exit_candidate] and
         state.alarm.dismiss_policy in [:bed_exit, :either] do
      since = state.exit_candidate_since || Clock.monotonic_ms()
      %{state | state: :exit_candidate, exit_candidate_since: since}
    else
      state
    end
  end

  defp apply_observation(state, %{state: :occupied, confidence: confidence})
       when confidence >= 0.75 do
    if state.state == :exit_candidate,
      do: %{state | state: :ringing, exit_candidate_since: nil},
      else: state
  end

  defp apply_observation(state, _observation), do: state

  defp advance(%{state: :snoozed, snooze_until: until} = state, now) when now >= until,
    do:
      {:continue,
       begin_ringing(%{
         state
         | snooze_until: nil,
           snooze_until_utc: nil,
           last_tick_monotonic: now
       })}

  defp advance(%{state: :exit_candidate, exit_candidate_since: since} = state, now) do
    state = account_audible(state, now)
    confirmation = Application.fetch_env!(:robine_wake, :exit_confirmation_ms)

    if now - since >= confirmation do
      {:stop, complete(state, :bed_exit)}
    else
      {:continue, update_gain(state, now)}
    end
  end

  defp advance(state, now) do
    state = account_audible(state, now)
    max_session = Application.fetch_env!(:robine_wake, :max_session_ms)

    if state.audible_ms >= max_session do
      {:stop, complete(state, :timed_out)}
    else
      {:continue, update_gain(state, now)}
    end
  end

  defp update_gain(%{state: state_name} = state, _now)
       when state_name not in [:ringing, :exit_candidate],
       do: state

  defp update_gain(state, now) do
    %{start: start, ceiling: ceiling} = state.alarm.volume_profile
    ramp_ms = state.alarm.prewake_seconds * 1_000
    elapsed_ms = max(0, now - state.ringing_since)

    progress =
      if ramp_ms == 0 do
        1.0
      else
        min(1.0, elapsed_ms / ramp_ms)
      end

    strong_at_ms = ramp_ms + Application.fetch_env!(:robine_wake, :gentle_plateau_ms)
    state = if elapsed_ms >= strong_at_ms, do: escalate_audio(state), else: state

    gain =
      if state.audio_phase == :strong,
        do: strong_gain(state.alarm),
        else: round(start + (ceiling - start) * progress)

    if state.state in [:ringing, :exit_candidate] and gain != state.current_gain do
      case Audio.set_gain(state.id, gain) do
        :ok -> %{state | current_gain: gain}
        {:error, reason} -> fail_audio(state, reason)
      end
    else
      state
    end
  end

  defp strong_gain(%{volume_profile: profile}), do: Map.get(profile, :strong, profile.ceiling)

  defp escalate_audio(%{audio_phase: :strong} = state), do: state

  defp escalate_audio(state) do
    case Audio.play(state.id, state.alarm.strong_sound_id) do
      :ok ->
        Hue.strong_wake(state.id)

        EventLog.emit(:gentle_wake_escalated,
          source: :wake_session,
          severity: :warning,
          session_id: state.id,
          alarm_id: state.alarm_id,
          payload: %{
            gentle_sound_id: state.alarm.sound_id,
            strong_sound_id: state.alarm.strong_sound_id
          }
        )

        # Audio.play/2 replaces the player and deliberately mutes the mixer first.
        # Reset the tracked gain as well so update_gain/2 always reapplies the
        # requested level to the newly started strong track.
        next = %{state | audio_phase: :strong, current_gain: 0}
        persist_state(next)
        EventStream.publish("session.changed")
        next

      {:error, reason} ->
        next = %{state | state: :failed_safe, audio_error: {:strong_sound_failed, reason}}
        persist_state(next)
        next
    end
  end

  defp fail_audio(state, reason) do
    _ = Audio.stop(state.id)
    next = %{state | state: :failed_safe, audio_error: reason, current_gain: 0}
    persist_state(next)

    EventLog.emit(:audio_failed,
      source: :wake_session,
      severity: :critical,
      session_id: state.id,
      alarm_id: state.alarm_id,
      payload: %{reason: reason}
    )

    next
  end

  defp account_audible(%{state: state_name} = state, now)
       when state_name in [:ringing, :exit_candidate, :failed_safe] do
    delta = max(0, now - state.last_tick_monotonic)
    %{state | audible_ms: state.audible_ms + delta, last_tick_monotonic: now}
  end

  defp account_audible(state, now), do: %{state | last_tick_monotonic: now}

  defp ringing_since(state, true, monotonic_now, _utc_now),
    do: monotonic_now - state.alarm.prewake_seconds * 1_000

  defp ringing_since(state, false, monotonic_now, utc_now) do
    gentle_starts_at = DateTime.add(state.scheduled_for, -state.alarm.prewake_seconds, :second)
    elapsed_ms = max(0, DateTime.diff(utc_now, gentle_starts_at, :millisecond))
    monotonic_now - elapsed_ms
  end

  defp complete(state, reason) do
    _ = Audio.stop(state.id)
    Hue.finish_wake(state.id, state.alarm.light_profile.end_behavior)
    terminal_state = if reason == :timed_out, do: :timed_out, else: :dismissed

    next = %{
      state
      | state: terminal_state,
        terminal_reason: reason,
        exit_candidate_since: nil,
        current_gain: 0
    }

    Settings.update_session(state.id, %{
      state: terminal_state,
      terminal_reason: reason,
      ended_at: Clock.utc_now(),
      snooze_count: state.snooze_count
    })

    EventLog.emit(:session_dismissed, %{
      source: :wake_session,
      session_id: state.id,
      alarm_id: state.alarm_id,
      severity: if(reason == :timed_out, do: :warning, else: :info),
      payload: %{reason: reason, snooze_count: state.snooze_count}
    })

    EventStream.publish("session.changed")

    next
  end

  defp persist_state(state) do
    Settings.update_session(state.id, %{
      state: state.state,
      snooze_count: state.snooze_count,
      snooze_until_utc: state.snooze_until_utc,
      audible_ms: state.audible_ms,
      audio_phase: state.audio_phase,
      audio_error: state.audio_error
    })
  end

  defp public(state) do
    state
    |> Map.drop([:alarm, :requested_phase])
    |> Map.put(:alarm, Alarm.to_map(state.alarm))
  end

  defp remote_dismiss_reason?(reason), do: reason in [:smartphone, :mcp]

  defp active_pid do
    case Registry.lookup(RobineWake.Registry, :active_session) do
      [{pid, _}] -> if Process.alive?(pid), do: pid, else: nil
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp call_active(message) do
    case active_pid() do
      nil ->
        {:error, :no_active_session}

      pid ->
        if Process.alive?(pid) do
          try do
            GenServer.call(pid, message)
          catch
            :exit, _ -> {:error, :no_active_session}
          end
        else
          {:error, :no_active_session}
        end
    end
  end

  defp safe_status(pid) do
    GenServer.call(pid, :status)
  catch
    :exit, _ -> nil
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, 250)

  defp normalize_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      {:error, reason} ->
        raise ArgumentError, "invalid scheduled_for datetime: #{inspect(reason)}"
    end
  end

  defp restored_datetime(nil, _key), do: nil

  defp restored_datetime(restored, key) do
    case DateTime.from_iso8601(restored[key] || "") do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp restored_snooze_remaining(nil, _now), do: 0

  defp restored_snooze_remaining(%{"state" => "snoozed"} = restored, now) do
    case restored_datetime(restored, "snooze_until_utc") do
      %DateTime{} = until -> max(0, DateTime.diff(until, now, :millisecond))
      _ -> 0
    end
  end

  defp restored_snooze_remaining(_restored, _now), do: 0

  defp restored_integer(nil, _key, default), do: default

  defp restored_integer(restored, key, default) do
    case restored[key] do
      value when is_integer(value) and value >= 0 -> value
      _ -> default
    end
  end
end
