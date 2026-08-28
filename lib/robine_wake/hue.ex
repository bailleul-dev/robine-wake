defmodule RobineWake.Hue do
  @moduledoc "Local Philips Hue bridge pairing and wake-light orchestration."

  use GenServer
  require Logger

  alias RobineWake.{Audio, EventLog, EventStream, Id, Settings}

  @breathing_low_brightness 1
  @breathing_high_brightness 30
  @breathing_inhale_color %{"xy" => %{"x" => 0.2, "y" => 0.24}}
  @breathing_exhale_color %{"xy" => %{"x" => 0.6, "y" => 0.34}}
  @breathing_color_transition_ms 750
  @breathing_audio_sound "breathing_meditation_ambience"
  @breathing_audio_default_volume 60
  @breathing_audio_tick_ms 250
  @breathing_min_hue_latency_ms 5
  @breathing_max_hue_latency_ms 750
  @breathing_latency_alpha 0.25
  @breathing_default_duration_minutes 10
  @breathing_durations [3, 5, 10, 15, 20, 30]
  @strong_wake_interval_ms 3_000
  @strong_wake_transition_ms 650
  @strong_wake_colors [
    %{"xy" => %{"x" => 0.675, "y" => 0.322}},
    %{"xy" => %{"x" => 0.153, "y" => 0.048}},
    %{"xy" => %{"x" => 0.313, "y" => 0.329}}
  ]
  @sunrise_initial_color %{"xy" => %{"x" => 0.65, "y" => 0.34}}
  @sunrise_stages [
    %{end_progress: 0.18, brightness_progress: 0.08, mirek: 455},
    %{end_progress: 0.45, brightness_progress: 0.28, mirek: 370},
    %{end_progress: 0.75, brightness_progress: 0.62, mirek: 250},
    %{end_progress: 1.0, brightness_progress: 1.0, mirek: 182}
  ]

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def status, do: GenServer.call(__MODULE__, :status)
  def targets, do: GenServer.call(__MODULE__, :targets)
  def pair(host), do: GenServer.call(__MODULE__, {:pair, host}, 15_000)
  def refresh, do: GenServer.call(__MODULE__, :refresh, 15_000)
  def disconnect, do: GenServer.call(__MODULE__, :disconnect)
  def reset, do: GenServer.call(__MODULE__, :reset)

  def start_breathing(
        target_id,
        duration_minutes \\ @breathing_default_duration_minutes,
        volume_percent \\ @breathing_audio_default_volume
      ),
      do:
        GenServer.call(
          __MODULE__,
          {:start_breathing, target_id, duration_minutes, volume_percent},
          15_000
        )

  def set_breathing_volume(volume_percent),
    do: GenServer.call(__MODULE__, {:set_breathing_volume, volume_percent})

  def stop_breathing, do: GenServer.call(__MODULE__, :stop_breathing, 15_000)

  def start_wake(session_id, profile),
    do: GenServer.call(__MODULE__, {:start_wake, session_id, profile}, 15_000)

  def snooze(session_id), do: GenServer.cast(__MODULE__, {:snooze, session_id})
  def strong_wake(session_id), do: GenServer.cast(__MODULE__, {:strong_wake, session_id})

  def finish_wake(session_id, behavior),
    do: GenServer.cast(__MODULE__, {:finish_wake, session_id, behavior})

  @impl true
  def init(_opts) do
    state = %{
      driver: Application.fetch_env!(:robine_wake, :hue_driver),
      targets: [],
      sessions: %{},
      breathing: nil,
      last_error: nil
    }

    send(self(), :load)
    {:ok, state}
  end

  @impl true
  def handle_info(:load, state), do: {:noreply, refresh_targets(state)}

  def handle_info({:breathing_phase, token}, %{breathing: %{token: token}} = state) do
    next = advance_breathing(state)
    publish_change(next)
    {:noreply, next}
  end

  def handle_info({:breathing_phase, _stale_token}, state), do: {:noreply, state}

  def handle_info(
        {:breathing_light_dispatch, token, phase, boundary_ms},
        %{breathing: %{token: token}} = state
      ) do
    {:noreply, dispatch_breathing_light(state, phase, boundary_ms)}
  end

  def handle_info({:breathing_light_dispatch, _token, _phase, _boundary_ms}, state),
    do: {:noreply, state}

  def handle_info(
        {:breathing_light_result, token, boundary_ms, sent_at_ms, result},
        %{breathing: %{token: token}} = state
      ) do
    next = record_breathing_light_result(state, boundary_ms, sent_at_ms, result)
    publish_change(next)
    {:noreply, next}
  end

  def handle_info(
        {:breathing_light_result, _token, _boundary_ms, _sent_at_ms, _result},
        state
      ),
      do: {:noreply, state}

  def handle_info({:breathing_audio_tick, token}, %{breathing: %{token: token}} = state) do
    {:noreply, advance_breathing_audio(state)}
  end

  def handle_info({:breathing_audio_tick, _stale_token}, state), do: {:noreply, state}

  def handle_info({:breathing_complete, token}, %{breathing: %{token: token}} = state) do
    next = end_breathing(state, true)
    publish_change(next)
    {:noreply, next}
  end

  def handle_info({:breathing_complete, _stale_token}, state), do: {:noreply, state}

  def handle_info({:strong_wake_color, session_id, token}, state) do
    case Map.get(state.sessions, session_id) do
      %{strong_token: ^token} = session ->
        {:noreply, advance_strong_wake_color(state, session_id, session)}

      _stale_or_missing ->
        {:noreply, state}
    end
  end

  def handle_info({:sunrise_stage, session_id, token}, state) do
    case Map.get(state.sessions, session_id) do
      %{sunrise_token: ^token} = session ->
        {:noreply, advance_sunrise(state, session_id, session)}

      _stale_or_missing ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, public_status(state), state}
  def handle_call(:targets, _from, state), do: {:reply, state.targets, state}

  def handle_call({:pair, host}, _from, state) when is_binary(host) do
    host = String.trim(host)

    with :ok <- validate_host(host),
         {:ok, config} <- state.driver.pair(host),
         :ok <- Settings.put_hue_bridge(config) do
      next = refresh_targets(%{state | last_error: nil})
      publish_change()
      {:reply, {:ok, public_status(next)}, next}
    else
      {:error, reason} ->
        next = %{state | last_error: reason}
        {:reply, {:error, reason}, next}
    end
  end

  def handle_call({:pair, _host}, _from, state),
    do: {:reply, {:error, :invalid_hue_bridge_address}, state}

  def handle_call(
        {:start_breathing, target_id, duration_minutes, volume_percent},
        _from,
        %{breathing: %{target_id: target_id}} = state
      )
      when duration_minutes in @breathing_durations and volume_percent in 0..100 do
    next = update_breathing_volume(state, volume_percent)
    publish_change(next)
    {:reply, {:ok, breathing_status(next.breathing)}, next}
  end

  def handle_call({:start_breathing, target_id, duration_minutes, volume_percent}, _from, state)
      when is_binary(target_id) and duration_minutes in @breathing_durations and
             volume_percent in 0..100 do
    with true <- state.sessions == %{} || {:error, :wake_session_active},
         true <-
           Enum.any?(state.targets, &(&1["id"] == target_id)) || {:error, :hue_target_not_found},
         state <- end_breathing(state, true),
         {:ok, config} <- bridge_config(),
         {:ok, previous} <- state.driver.get_target(config, target_id),
         {:ok, next} <-
           begin_breathing(
             state,
             config,
             target_id,
             previous,
             duration_minutes,
             volume_percent
           ) do
      publish_change(next)
      {:reply, {:ok, breathing_status(next.breathing)}, next}
    else
      {:error, reason} when reason in [:wake_session_active, :hue_target_not_found] ->
        {:reply, {:error, reason}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | last_error: reason}}
    end
  end

  def handle_call({:start_breathing, target_id, duration_minutes, volume_percent}, _from, state) do
    reason =
      cond do
        not is_binary(target_id) -> :invalid_hue_target
        duration_minutes not in @breathing_durations -> :invalid_breathing_duration
        volume_percent not in 0..100 -> :invalid_breathing_volume
      end

    {:reply, {:error, reason}, state}
  end

  def handle_call({:set_breathing_volume, volume_percent}, _from, state)
      when volume_percent in 0..100 and not is_nil(state.breathing) do
    next = update_breathing_volume(state, volume_percent)
    publish_change(next)
    {:reply, {:ok, breathing_status(next.breathing)}, next}
  end

  def handle_call({:set_breathing_volume, volume_percent}, _from, state) do
    reason =
      if volume_percent in 0..100, do: :breathing_not_active, else: :invalid_breathing_volume

    {:reply, {:error, reason}, state}
  end

  def handle_call(:stop_breathing, _from, state) do
    next = end_breathing(state, true)
    publish_change(next)
    {:reply, {:ok, breathing_status(next.breathing)}, next}
  end

  def handle_call({:start_wake, _session_id, %{enabled: false}}, _from, state),
    do: {:reply, :ok, end_breathing(state, true)}

  def handle_call({:start_wake, session_id, profile}, _from, state) do
    {:reply, :ok, begin_wake(state, session_id, profile)}
  end

  def handle_call(:refresh, _from, state) do
    next = refresh_targets(state)
    publish_change()

    if next.last_error,
      do: {:reply, {:error, next.last_error}, next},
      else: {:reply, {:ok, public_status(next)}, next}
  end

  def handle_call(:disconnect, _from, state) do
    state = end_breathing(state, true)

    case Settings.clear_hue_bridge() do
      :ok ->
        next = %{state | targets: [], sessions: %{}, breathing: nil, last_error: nil}
        publish_change()
        {:reply, :ok, next}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | last_error: reason}}
    end
  end

  def handle_call(:reset, _from, state) do
    state = end_breathing(state, false)
    next = %{state | targets: [], sessions: %{}, breathing: nil, last_error: nil}
    publish_change()
    {:reply, :ok, next}
  end

  @impl true
  def handle_cast({:snooze, session_id}, state) do
    next =
      with {:ok, session} <- Map.fetch(state.sessions, session_id),
           {:ok, config} <- bridge_config(),
           :ok <- state.driver.set_target(config, session.target_id, %{"on" => %{"on" => false}}) do
        session = session |> cancel_sunrise() |> cancel_strong_wake()
        %{state | sessions: Map.put(state.sessions, session_id, session)}
      else
        _ -> state
      end

    {:noreply, next}
  end

  def handle_cast({:strong_wake, session_id}, state) do
    next =
      with {:ok, session} <- Map.fetch(state.sessions, session_id),
           {:ok, config} <- bridge_config(),
           session <- session |> cancel_sunrise() |> cancel_strong_wake(),
           token <- make_ref(),
           :ok <- set_strong_wake_color(state.driver, config, session, 0) do
        strong_session = %{
          session
          | strong_token: token,
            strong_color_index: 0,
            strong_timer: schedule_strong_wake_color(session_id, token)
        }

        EventLog.emit(:hue_strong_wake_started,
          source: :hue,
          session_id: session_id,
          payload: %{target_id: session.target_id, interval_ms: @strong_wake_interval_ms}
        )

        %{state | sessions: Map.put(state.sessions, session_id, strong_session), last_error: nil}
      else
        :error -> state
        {:error, reason} -> record_error(state, :hue_strong_wake_failed, session_id, reason)
      end

    {:noreply, next}
  end

  def handle_cast({:finish_wake, session_id, behavior}, state) do
    {session, sessions} = Map.pop(state.sessions, session_id)
    if session, do: session |> cancel_sunrise() |> cancel_strong_wake()
    next = %{state | sessions: sessions}

    next =
      if session do
        finish_target(next, session, behavior)
      else
        next
      end

    {:noreply, next}
  end

  defp begin_wake(state, session_id, profile) do
    state = end_breathing(state, true)

    with {:ok, config} <- bridge_config(),
         {:ok, previous, sessions} <- previous_state(state, config, session_id, profile.target_id),
         :ok <- set_start(state.driver, config, profile),
         {:ok, sunrise} <- start_sunrise(state.driver, config, session_id, profile) do
      EventLog.emit(:hue_wake_started,
        source: :hue,
        session_id: session_id,
        payload: %{target_id: profile.target_id, ramp_seconds: profile.ramp_seconds}
      )

      %{
        state
        | sessions:
            Map.put(sessions, session_id, %{
              target_id: profile.target_id,
              previous: previous,
              sunrise_token: sunrise.token,
              sunrise_timer: sunrise.timer,
              sunrise_stage_index: 0,
              sunrise_stages: sunrise.stages,
              strong_brightness: profile.end_brightness,
              strong_token: nil,
              strong_color_index: 0,
              strong_timer: nil
            }),
          last_error: nil
      }
    else
      {:error, reason} -> record_error(state, :hue_wake_failed, session_id, reason)
    end
  end

  defp previous_state(state, config, session_id, target_id) do
    case Map.fetch(state.sessions, session_id) do
      {:ok, session} ->
        {:ok, session.previous, state.sessions}

      :error ->
        with {:ok, previous} <- state.driver.get_target(config, target_id),
             do: {:ok, previous, state.sessions}
    end
  end

  defp set_start(driver, config, profile) do
    driver.set_target(config, profile.target_id, %{
      "on" => %{"on" => true},
      "dimming" => %{"brightness" => profile.start_brightness},
      "color" => @sunrise_initial_color
    })
  end

  defp start_sunrise(driver, config, session_id, profile) do
    stages = sunrise_stages(profile)
    first = hd(stages)
    token = make_ref()

    with :ok <- set_sunrise_stage(driver, config, profile.target_id, first) do
      {:ok,
       %{
         token: token,
         timer: schedule_sunrise_stage(session_id, token, first.duration_ms),
         stages: stages
       }}
    end
  end

  defp advance_sunrise(state, session_id, session) do
    next_index = session.sunrise_stage_index + 1

    case Enum.at(session.sunrise_stages, next_index) do
      nil ->
        next_session = %{session | sunrise_timer: nil, sunrise_token: nil}
        %{state | sessions: Map.put(state.sessions, session_id, next_session)}

      stage ->
        with {:ok, config} <- bridge_config(),
             :ok <- set_sunrise_stage(state.driver, config, session.target_id, stage) do
          next_session = %{
            session
            | sunrise_stage_index: next_index,
              sunrise_timer:
                schedule_sunrise_stage(session_id, session.sunrise_token, stage.duration_ms)
          }

          %{state | sessions: Map.put(state.sessions, session_id, next_session), last_error: nil}
        else
          {:error, reason} -> record_error(state, :hue_sunrise_failed, session_id, reason)
        end
    end
  end

  defp set_sunrise_stage(driver, config, target_id, stage) do
    driver.set_target(config, target_id, %{
      "on" => %{"on" => true},
      "dimming" => %{"brightness" => stage.brightness},
      "color_temperature" => %{"mirek" => stage.mirek},
      "dynamics" => %{"duration" => stage.duration_ms}
    })
  end

  defp sunrise_stages(profile) do
    ramp_ms = profile.ramp_seconds * 1_000

    Enum.map_reduce(@sunrise_stages, 0.0, fn stage, previous_progress ->
      brightness =
        profile.start_brightness +
          (profile.end_brightness - profile.start_brightness) * stage.brightness_progress

      duration_ms = round((stage.end_progress - previous_progress) * ramp_ms)

      {%{
         brightness: Float.round(brightness * 1.0, 1),
         mirek: stage.mirek,
         duration_ms: duration_ms
       }, stage.end_progress}
    end)
    |> elem(0)
  end

  defp schedule_sunrise_stage(session_id, token, duration_ms) do
    Process.send_after(self(), {:sunrise_stage, session_id, token}, duration_ms)
  end

  defp cancel_sunrise(session) do
    if session.sunrise_timer, do: Process.cancel_timer(session.sunrise_timer)
    %{session | sunrise_timer: nil, sunrise_token: nil}
  end

  defp advance_strong_wake_color(state, session_id, session) do
    case bridge_config() do
      {:ok, config} -> advance_strong_wake_color(state, session_id, session, config)
      {:error, reason} -> record_error(state, :hue_strong_wake_failed, session_id, reason)
    end
  end

  defp advance_strong_wake_color(state, session_id, session, config) do
    next_index = rem(session.strong_color_index + 1, length(@strong_wake_colors))

    case set_strong_wake_color(state.driver, config, session, next_index) do
      :ok ->
        next_session = %{
          session
          | strong_color_index: next_index,
            strong_timer: schedule_strong_wake_color(session_id, session.strong_token)
        }

        %{state | sessions: Map.put(state.sessions, session_id, next_session), last_error: nil}

      {:error, reason} ->
        record_error(state, :hue_strong_wake_failed, session_id, reason)
    end
  end

  defp set_strong_wake_color(driver, config, session, index) do
    driver.set_target(config, session.target_id, %{
      "on" => %{"on" => true},
      "dimming" => %{"brightness" => session.strong_brightness},
      "color" => Enum.at(@strong_wake_colors, index),
      "dynamics" => %{"duration" => @strong_wake_transition_ms}
    })
  end

  defp schedule_strong_wake_color(session_id, token) do
    Process.send_after(self(), {:strong_wake_color, session_id, token}, @strong_wake_interval_ms)
  end

  defp cancel_strong_wake(session) do
    if session.strong_timer, do: Process.cancel_timer(session.strong_timer)
    %{session | strong_timer: nil, strong_token: nil}
  end

  defp finish_target(state, _session, :leave), do: state

  defp finish_target(state, session, behavior) do
    with {:ok, config} <- bridge_config(),
         changes <- finish_changes(session.previous, behavior),
         :ok <- state.driver.set_target(config, session.target_id, changes) do
      state
    else
      {:error, reason} -> record_error(state, :hue_restore_failed, nil, reason)
    end
  end

  defp finish_changes(_previous, :off), do: %{"on" => %{"on" => false}}

  defp finish_changes(previous, :restore) do
    %{}
    |> maybe_put("on", previous["on"])
    |> maybe_put("dimming", previous["dimming"])
    |> maybe_put("color", previous["color"])
    |> maybe_put("color_temperature", previous["color_temperature"])
  end

  defp finish_changes(_previous, _behavior), do: %{}

  defp begin_breathing(state, config, target_id, previous, duration_minutes, volume_percent) do
    state = end_breathing(state, true)
    token = make_ref()

    initial_result =
      timed_set_target(state.driver, config, target_id, %{
        "on" => %{"on" => true},
        "dimming" => %{"brightness" => @breathing_low_brightness},
        "color" => @breathing_exhale_color,
        "dynamics" => %{"duration" => 0}
      })

    case initial_result do
      {:ok, initial_rtt_ms} ->
        hue_latency_ms = one_way_latency(initial_rtt_ms)
        initial_boundary_ms = System.monotonic_time(:millisecond) + hue_latency_ms

        dispatch_light_command(
          self(),
          state.driver,
          config,
          token,
          target_id,
          :inhale,
          initial_boundary_ms
        )

        Process.sleep(hue_latency_ms)
        {audio_low_gain, audio_high_gain} = breathing_audio_gains(volume_percent)
        {audio_session_id, audio_gain, audio_error} = start_breathing_audio(audio_low_gain)
        now = System.monotonic_time(:millisecond)
        duration_ms = duration_minutes * 60_000
        deadline_ms = now + 4_000

        breathing = %{
          token: token,
          timer: schedule_phase(token, deadline_ms),
          light_timer: schedule_light_phase(token, :exhale, deadline_ms, hue_latency_ms),
          completion_timer: Process.send_after(self(), {:breathing_complete, token}, duration_ms),
          audio_timer: schedule_audio_tick(token, audio_session_id),
          audio_session_id: audio_session_id,
          audio_gain: audio_gain,
          audio_low_gain: audio_low_gain,
          audio_high_gain: audio_high_gain,
          volume_percent: volume_percent,
          audio_error: audio_error,
          deadline_ms: deadline_ms,
          hue_latency_ms: hue_latency_ms,
          hue_rtt_ms: initial_rtt_ms,
          sync_error_ms: 0,
          sync_samples: 1,
          sync_checked_at: DateTime.utc_now(),
          target_id: target_id,
          target_name: target_name(state.targets, target_id),
          previous: previous,
          phase: :inhale,
          phase_started_at: DateTime.utc_now(),
          duration_minutes: duration_minutes,
          ends_at: DateTime.add(DateTime.utc_now(), duration_ms, :millisecond),
          end_deadline_ms: now + duration_ms,
          cycle_count: 0
        }

        EventLog.emit(:breathing_started,
          source: :hue,
          payload: %{
            target_id: target_id,
            inhale_ms: 4_000,
            exhale_ms: 6_000,
            duration_minutes: duration_minutes,
            hue_latency_ms: hue_latency_ms,
            audio: if(audio_session_id, do: :meditation_ambience, else: :unavailable)
          }
        )

        {:ok, %{state | breathing: breathing, last_error: nil}}

      {:error, reason} ->
        _ = state.driver.set_target(config, target_id, finish_changes(previous, :restore))
        {:error, reason}
    end
  end

  defp advance_breathing(%{breathing: breathing} = state) do
    {phase, duration, cycle_count} =
      case breathing.phase do
        :inhale -> {:exhale, 6_000, breathing.cycle_count}
        :exhale -> {:inhale, 4_000, breathing.cycle_count + 1}
      end

    deadline_ms = breathing.deadline_ms + duration

    next_breathing = %{
      breathing
      | phase: phase,
        phase_started_at: DateTime.utc_now(),
        cycle_count: cycle_count,
        deadline_ms: deadline_ms,
        timer: schedule_phase(breathing.token, deadline_ms),
        light_timer:
          schedule_light_phase(
            breathing.token,
            opposite_phase(phase),
            deadline_ms,
            breathing.hue_latency_ms
          )
    }

    %{state | breathing: next_breathing}
  end

  defp dispatch_breathing_light(%{breathing: breathing} = state, phase, boundary_ms) do
    case bridge_config() do
      {:ok, config} ->
        dispatch_light_command(
          self(),
          state.driver,
          config,
          breathing.token,
          breathing.target_id,
          phase,
          boundary_ms
        )

        state

      {:error, reason} ->
        state
        |> record_error(:breathing_failed, nil, reason)
        |> end_breathing(true)
    end
  end

  defp dispatch_light_command(server, driver, config, token, target_id, phase, boundary_ms) do
    Task.start(fn ->
      sent_at_ms = System.monotonic_time(:millisecond)

      result =
        case driver.set_target(config, target_id, breathing_color_changes(phase)) do
          :ok ->
            color_rtt_ms = max(System.monotonic_time(:millisecond) - sent_at_ms, 1)

            case driver.set_target(config, target_id, breathing_brightness_changes(phase)) do
              :ok -> {:ok, color_rtt_ms}
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      send(server, {:breathing_light_result, token, boundary_ms, sent_at_ms, result})
    end)
  end

  defp record_breathing_light_result(state, boundary_ms, sent_at_ms, {:ok, rtt_ms}) do
    record_successful_breathing_light(state, boundary_ms, sent_at_ms, rtt_ms)
  end

  defp record_breathing_light_result(state, boundary_ms, sent_at_ms, :ok) do
    rtt_ms = max(System.monotonic_time(:millisecond) - sent_at_ms, 1)
    record_successful_breathing_light(state, boundary_ms, sent_at_ms, rtt_ms)
  end

  defp record_breathing_light_result(state, _boundary_ms, _sent_at_ms, {:error, reason}) do
    state
    |> record_error(:breathing_failed, nil, reason)
    |> end_breathing(true)
  end

  defp record_successful_breathing_light(state, boundary_ms, sent_at_ms, rtt_ms) do
    measured_latency_ms = one_way_latency(rtt_ms)
    breathing = state.breathing

    latency_ms =
      round(
        breathing.hue_latency_ms * (1.0 - @breathing_latency_alpha) +
          measured_latency_ms * @breathing_latency_alpha
      )
      |> clamp_latency()

    estimated_arrival_ms = sent_at_ms + measured_latency_ms
    sync_error_ms = estimated_arrival_ms - boundary_ms

    next_breathing = %{
      breathing
      | hue_latency_ms: latency_ms,
        hue_rtt_ms: rtt_ms,
        sync_error_ms: sync_error_ms,
        sync_samples: breathing.sync_samples + 1,
        sync_checked_at: DateTime.utc_now()
    }

    %{state | breathing: next_breathing, last_error: nil}
  end

  defp timed_set_target(driver, config, target_id, changes) do
    started_at_ms = System.monotonic_time(:millisecond)

    case driver.set_target(config, target_id, changes) do
      :ok -> {:ok, max(System.monotonic_time(:millisecond) - started_at_ms, 1)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp breathing_color_changes(:inhale) do
    %{
      "on" => %{"on" => true},
      "color" => @breathing_inhale_color,
      "dynamics" => %{"duration" => @breathing_color_transition_ms}
    }
  end

  defp breathing_color_changes(:exhale) do
    %{
      "on" => %{"on" => true},
      "color" => @breathing_exhale_color,
      "dynamics" => %{"duration" => @breathing_color_transition_ms}
    }
  end

  defp breathing_brightness_changes(:inhale) do
    %{
      "on" => %{"on" => true},
      "dimming" => %{"brightness" => @breathing_high_brightness},
      "dynamics" => %{"duration" => 4_000}
    }
  end

  defp breathing_brightness_changes(:exhale) do
    %{
      "on" => %{"on" => true},
      "dimming" => %{"brightness" => @breathing_low_brightness},
      "dynamics" => %{"duration" => 6_000}
    }
  end

  defp opposite_phase(:inhale), do: :exhale
  defp opposite_phase(:exhale), do: :inhale

  defp end_breathing(%{breathing: nil} = state, _restore), do: state

  defp end_breathing(%{breathing: breathing} = state, restore) do
    if breathing.timer, do: Process.cancel_timer(breathing.timer)
    if breathing.light_timer, do: Process.cancel_timer(breathing.light_timer)
    if breathing.completion_timer, do: Process.cancel_timer(breathing.completion_timer)
    if breathing.audio_timer, do: Process.cancel_timer(breathing.audio_timer)
    stop_breathing_audio(breathing)

    state = %{state | breathing: nil}

    state =
      if restore do
        with {:ok, config} <- bridge_config(),
             :ok <-
               state.driver.set_target(
                 config,
                 breathing.target_id,
                 finish_changes(breathing.previous, :restore)
               ) do
          state
        else
          {:error, reason} -> record_error(state, :breathing_restore_failed, nil, reason)
        end
      else
        state
      end

    EventLog.emit(:breathing_stopped,
      source: :hue,
      payload: %{target_id: breathing.target_id, cycles: breathing.cycle_count}
    )

    state
  end

  defp schedule_phase(token, deadline_ms) do
    delay = max(deadline_ms - System.monotonic_time(:millisecond), 0)
    Process.send_after(self(), {:breathing_phase, token}, delay)
  end

  defp schedule_light_phase(token, phase, boundary_ms, latency_ms) do
    dispatch_at_ms = boundary_ms - latency_ms
    delay = max(dispatch_at_ms - System.monotonic_time(:millisecond), 0)
    Process.send_after(self(), {:breathing_light_dispatch, token, phase, boundary_ms}, delay)
  end

  defp one_way_latency(rtt_ms), do: rtt_ms |> div(2) |> clamp_latency()

  defp clamp_latency(latency_ms) do
    latency_ms
    |> max(@breathing_min_hue_latency_ms)
    |> min(@breathing_max_hue_latency_ms)
  end

  defp start_breathing_audio(initial_gain) do
    session_id = "breathing-" <> Id.generate()

    with :ok <- Audio.play(session_id, @breathing_audio_sound),
         :ok <- Audio.set_gain(session_id, initial_gain) do
      {session_id, initial_gain, nil}
    else
      {:error, reason} ->
        _ = Audio.stop(session_id)

        EventLog.emit(:breathing_audio_failed,
          source: :hue,
          severity: :warning,
          payload: %{reason: inspect(reason)}
        )

        {nil, 0, reason}
    end
  end

  defp advance_breathing_audio(%{breathing: %{audio_session_id: nil}} = state), do: state

  defp advance_breathing_audio(%{breathing: breathing} = state) do
    duration = if breathing.phase == :inhale, do: 4_000, else: 6_000
    started_at = breathing.deadline_ms - duration
    progress = (System.monotonic_time(:millisecond) - started_at) / duration
    progress = min(max(progress, 0.0), 1.0)
    smoothed = progress * progress * (3.0 - 2.0 * progress)

    gain = breathing_gain(breathing, smoothed)

    next_breathing = %{
      breathing
      | audio_timer: schedule_audio_tick(breathing.token, breathing.audio_session_id)
    }

    if gain == breathing.audio_gain do
      %{state | breathing: next_breathing}
    else
      case Audio.set_gain(breathing.audio_session_id, gain) do
        :ok ->
          %{state | breathing: %{next_breathing | audio_gain: gain}}

        {:error, reason} ->
          _ = Audio.stop(breathing.audio_session_id)

          EventLog.emit(:breathing_audio_failed,
            source: :hue,
            severity: :warning,
            payload: %{reason: inspect(reason)}
          )

          %{
            state
            | breathing: %{
                next_breathing
                | audio_session_id: nil,
                  audio_gain: 0,
                  audio_error: reason
              }
          }
      end
    end
  end

  defp stop_breathing_audio(%{audio_session_id: nil}), do: :ok

  defp stop_breathing_audio(breathing) do
    if breathing.audio_gain > 0 do
      Enum.each((breathing.audio_gain - 1)..0//-1, fn gain ->
        _ = Audio.set_gain(breathing.audio_session_id, gain)
        Process.sleep(40)
      end)
    end

    Audio.stop(breathing.audio_session_id)
  end

  defp schedule_audio_tick(_token, nil), do: nil

  defp schedule_audio_tick(token, _audio_session_id),
    do: Process.send_after(self(), {:breathing_audio_tick, token}, @breathing_audio_tick_ms)

  defp update_breathing_volume(%{breathing: breathing} = state, volume_percent) do
    {low_gain, high_gain} = breathing_audio_gains(volume_percent)

    next_breathing = %{
      breathing
      | volume_percent: volume_percent,
        audio_low_gain: low_gain,
        audio_high_gain: high_gain
    }

    gain = current_breathing_gain(next_breathing)

    case next_breathing.audio_session_id && Audio.set_gain(next_breathing.audio_session_id, gain) do
      :ok -> %{state | breathing: %{next_breathing | audio_gain: gain}}
      nil -> %{state | breathing: next_breathing}
      {:error, reason} -> %{state | breathing: %{next_breathing | audio_error: reason}}
    end
  end

  defp current_breathing_gain(breathing) do
    duration = if breathing.phase == :inhale, do: 4_000, else: 6_000
    started_at = breathing.deadline_ms - duration
    progress = (System.monotonic_time(:millisecond) - started_at) / duration
    progress = min(max(progress, 0.0), 1.0)
    breathing_gain(breathing, progress * progress * (3.0 - 2.0 * progress))
  end

  defp breathing_gain(breathing, smoothed) do
    range = breathing.audio_high_gain - breathing.audio_low_gain

    case breathing.phase do
      :inhale -> round(breathing.audio_low_gain + range * smoothed)
      :exhale -> round(breathing.audio_high_gain - range * smoothed)
    end
  end

  defp breathing_audio_gains(volume_percent) do
    {volume_percent, volume_percent}
  end

  defp target_name(targets, target_id) do
    case Enum.find(targets, &(&1["id"] == target_id)) do
      nil -> nil
      target -> target["name"]
    end
  end

  defp breathing_status(nil), do: %{active: false}

  defp breathing_status(breathing) do
    now_ms = System.monotonic_time(:millisecond)
    phase_duration_ms = if breathing.phase == :inhale, do: 4_000, else: 6_000
    phase_remaining_ms = max(breathing.deadline_ms - now_ms, 0)

    %{
      active: true,
      target_id: breathing.target_id,
      target_name: breathing.target_name,
      phase: breathing.phase,
      phase_started_at: DateTime.to_iso8601(breathing.phase_started_at),
      phase_duration_ms: phase_duration_ms,
      phase_elapsed_ms: min(max(phase_duration_ms - phase_remaining_ms, 0), phase_duration_ms),
      phase_remaining_ms: min(phase_remaining_ms, phase_duration_ms),
      cycle_count: breathing.cycle_count,
      duration_minutes: breathing.duration_minutes,
      ends_at: DateTime.to_iso8601(breathing.ends_at),
      server_time: DateTime.utc_now() |> DateTime.to_iso8601(),
      remaining_seconds: max(div(breathing.end_deadline_ms - now_ms + 999, 1_000), 0),
      inhale_seconds: 4,
      exhale_seconds: 6,
      low_brightness: @breathing_low_brightness,
      high_brightness: @breathing_high_brightness,
      inhale_color: "clear_sky_blue",
      exhale_color: "deep_amber",
      synchronization: %{
        hue_latency_ms: breathing.hue_latency_ms,
        hue_round_trip_ms: breathing.hue_rtt_ms,
        estimated_error_ms: breathing.sync_error_ms,
        samples: breathing.sync_samples,
        checked_at: DateTime.to_iso8601(breathing.sync_checked_at)
      },
      audio: %{
        active: is_binary(breathing.audio_session_id),
        kind: "meditation_ambience",
        gain: breathing.audio_gain,
        volume_percent: breathing.volume_percent,
        low_gain: breathing.audio_low_gain,
        high_gain: breathing.audio_high_gain,
        error: error_text(breathing.audio_error)
      }
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp refresh_targets(state) do
    case bridge_config() do
      {:ok, config} ->
        case state.driver.targets(config) do
          {:ok, targets} ->
            %{state | targets: merge_targets(targets, persisted_targets()), last_error: nil}

          {:error, reason} ->
            targets = if state.targets == [], do: persisted_targets(), else: state.targets
            %{state | targets: targets, last_error: reason}
        end

      {:error, :hue_not_configured} ->
        %{state | targets: [], last_error: nil}
    end
  end

  defp persisted_targets do
    Settings.list_alarms()
    |> Enum.map(& &1.light_profile)
    |> Enum.filter(&(&1.enabled and is_binary(&1.target_id) and &1.target_id != ""))
    |> Enum.map(fn profile ->
      %{
        "id" => profile.target_id,
        "name" => profile.target_name || "Lumière Hue enregistrée",
        "kind" => "saved"
      }
    end)
    |> Enum.uniq_by(& &1["id"])
  end

  defp merge_targets(discovered, saved) do
    (discovered ++ saved)
    |> Enum.uniq_by(& &1["id"])
    |> Enum.sort_by(&{&1["kind"], String.downcase(&1["name"])})
  end

  defp bridge_config do
    case Settings.hue_bridge() do
      %{"host" => host, "application_key" => key} = config
      when is_binary(host) and is_binary(key) ->
        {:ok, config}

      _ ->
        {:error, :hue_not_configured}
    end
  end

  defp public_status(state) do
    config = Settings.hue_bridge()

    %{
      configured: is_map(config),
      state: hue_state(config, state.last_error),
      bridge_host: config && config["host"],
      target_count: length(state.targets),
      breathing: breathing_status(state.breathing),
      last_error: error_text(state.last_error)
    }
  end

  defp hue_state(nil, _error), do: :not_configured
  defp hue_state(_config, nil), do: :available
  defp hue_state(_config, _error), do: :unavailable

  defp validate_host(host) when is_binary(host) do
    host = String.trim(host)

    if host != "" and byte_size(host) <= 253 and String.match?(host, ~r/\A[0-9A-Za-z.-]+\z/),
      do: :ok,
      else: {:error, :invalid_hue_bridge_address}
  end

  defp validate_host(_), do: {:error, :invalid_hue_bridge_address}

  defp record_error(state, event, session_id, reason) do
    Logger.warning("Hue command failed: #{inspect(reason)}")

    EventLog.emit(event,
      source: :hue,
      severity: :warning,
      session_id: session_id,
      payload: %{reason: inspect(reason)}
    )

    %{state | last_error: reason}
  end

  defp publish_change do
    if Process.whereis(EventStream), do: EventStream.publish("state.changed")
  end

  defp publish_change(state) do
    if Process.whereis(EventStream) do
      EventStream.publish("breathing.changed", %{hue: public_status(state)})
      EventStream.publish("state.changed")
    end
  end

  defp error_text(nil), do: nil
  defp error_text(error) when is_atom(error), do: Atom.to_string(error)
  defp error_text(error), do: inspect(error)
end
