defmodule RobineWake.Audio do
  @moduledoc false
  use GenServer

  require Logger

  @music_level_retry_ms 1_000
  @music_level_attempts 120
  @output_release_timeout_ms 3_000
  # Covers the output release wait plus every start attempt.
  @play_timeout_ms 15_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def play(session_id, sound_id),
    do: GenServer.call(__MODULE__, {:play, session_id, sound_id}, @play_timeout_ms)

  def set_gain(session_id, gain), do: GenServer.call(__MODULE__, {:set_gain, session_id, gain})
  def stop(session_id), do: GenServer.call(__MODULE__, {:stop, session_id})
  def status, do: GenServer.call(__MODULE__, :status)

  @impl true
  def init(_opts) do
    driver = Application.fetch_env!(:robine_wake, :audio_driver)
    send(self(), {:restore_music_level, 0})

    {:ok,
     %{
       driver: driver,
       capabilities: driver.capabilities(),
       active_session: nil,
       handle: nil,
       monitor: nil,
       gain: 0,
       commands: [],
       last_error: nil
     }}
  end

  @impl true
  def handle_call(
        {:play, session_id, _sound_id},
        _from,
        %{active_session: active_session} = state
      )
      when not is_nil(active_session) and active_session != session_id do
    {:reply, {:error, :stale_session}, state}
  end

  def handle_call({:play, session_id, sound_id}, _from, state) do
    state = stop_current(state)
    suspend_music_receivers()
    await_output_released(state.driver)

    retry_delays = Application.fetch_env!(:robine_wake, :audio_retry_delays_ms)

    attempt = fn ->
      with :ok <- state.driver.prepare(sound_id),
           :ok <- state.driver.set_gain(0) do
        state.driver.play(session_id, sound_id)
      end
    end

    case retry(attempt, retry_delays) do
      {:ok, handle} ->
        monitor = if is_pid(handle), do: Process.monitor(handle), else: nil

        next =
          record(
            %{
              state
              | active_session: session_id,
                handle: handle,
                monitor: monitor,
                last_error: nil
            },
            {:play, session_id, sound_id}
          )

        {:reply, :ok, next}

      {:error, reason} ->
        Logger.error("Audio playback failed: #{inspect(reason)}")
        resume_music_receivers(state.driver)

        {:reply, {:error, reason},
         %{record(state, {:play_failed, session_id, reason}) | last_error: reason}}
    end
  end

  def handle_call({:set_gain, session_id, gain}, _from, %{active_session: session_id} = state)
      when gain in 0..100 do
    ceiling = Application.fetch_env!(:robine_wake, :audio_safety_ceiling)

    if gain <= ceiling do
      case state.driver.set_gain(gain) do
        :ok -> {:reply, :ok, record(%{state | gain: gain}, {:gain, session_id, gain})}
        {:error, reason} -> {:reply, {:error, reason}, %{state | last_error: reason}}
      end
    else
      {:reply, {:error, :gain_above_safety_ceiling}, state}
    end
  end

  def handle_call({:set_gain, _session_id, _gain}, _from, state),
    do: {:reply, {:error, :stale_session}, state}

  def handle_call({:stop, session_id}, _from, %{active_session: session_id} = state) do
    _ = state.driver.set_gain(0)
    _ = state.driver.stop(state.handle)
    clear_monitor(state.monitor)
    resume_music_receivers(state.driver)

    next =
      record(
        %{state | active_session: nil, handle: nil, monitor: nil, gain: 0},
        {:stop, session_id}
      )

    {:reply, :ok, next}
  end

  def handle_call({:stop, _session_id}, _from, state), do: {:reply, :ok, state}

  def handle_call(:status, _from, state) do
    driver_status = state.driver.status()

    public =
      state
      |> Map.take([:capabilities, :active_session, :gain, :commands, :last_error])
      |> Map.put(:capabilities, state.driver.capabilities())
      |> Map.put(:driver_status, driver_status)

    {:reply, public, state}
  end

  @impl true
  def handle_info({:DOWN, reference, :process, _pid, reason}, %{monitor: reference} = state) do
    RobineWake.WakeSession.audio_failed(reason)
    resume_music_receivers(state.driver)

    {:noreply,
     %{
       state
       | active_session: nil,
         handle: nil,
         monitor: nil,
         gain: 0,
         last_error: {:player_exited, reason}
     }}
  end

  # The sound card may still be probing when the application boots, so the
  # music level is retried until the mixer accepts it. Wake audio owns the
  # mixer while it plays and supersedes any pending retry.
  def handle_info({:restore_music_level, _attempt}, %{active_session: session} = state)
      when not is_nil(session),
      do: {:noreply, state}

  def handle_info({:restore_music_level, attempt}, state) do
    case restore_music_level(state.driver) do
      :ok ->
        :ok

      :error when attempt < @music_level_attempts ->
        Process.send_after(self(), {:restore_music_level, attempt + 1}, @music_level_retry_ms)

      :error ->
        Logger.error("Music level still not applied after #{attempt + 1} attempts")
    end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp stop_current(%{handle: nil} = state), do: state

  defp stop_current(state) do
    _ = state.driver.set_gain(0)
    _ = state.driver.stop(state.handle)
    clear_monitor(state.monitor)
    %{state | active_session: nil, handle: nil, monitor: nil, gain: 0}
  end

  defp retry(fun, [delay | rest]) do
    if delay > 0, do: Process.sleep(delay)

    case fun.() do
      {:ok, _} = ok -> ok
      {:error, _} = error when rest == [] -> error
      {:error, _} -> retry(fun, rest)
    end
  end

  defp record(state, command), do: %{state | commands: Enum.take([command | state.commands], 100)}

  defp clear_monitor(nil), do: :ok
  defp clear_monitor(reference), do: Process.demonitor(reference, [:flush])

  # Music receivers (AirPlay, Bluetooth) release ALSA before wake audio opens
  # it. A failing receiver is logged and skipped: it must never stop the alarm.
  defp suspend_music_receivers, do: Enum.each(music_receivers(), &call_receiver(&1, :suspend))

  defp resume_music_receivers(driver) do
    if restore_music_level(driver) == :error,
      do: Process.send_after(self(), {:restore_music_level, 1}, @music_level_retry_ms)

    Enum.each(music_receivers(), &call_receiver(&1, :resume))
  end

  # The hardware mixer belongs to this process: wake audio ramps it, and in
  # between it stays at the music ceiling while receivers (AirPlay, Bluetooth)
  # attenuate in software. Receivers never write it.
  defp restore_music_level(driver) do
    Code.ensure_loaded(driver)

    if function_exported?(driver, :set_music_level, 1) do
      decibels = Application.fetch_env!(:robine_wake, :music_mixer_db)

      case driver.set_music_level(decibels) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Music level not applied: #{inspect(reason)}")
          :error
      end
    else
      :ok
    end
  catch
    kind, reason ->
      Logger.error("Music level not applied: #{inspect({kind, reason})}")
      :error
  end

  # Stopping a receiver returns before its OS process has closed the card. A
  # card still busy after the timeout is logged only: the player retries.
  defp await_output_released(driver) do
    Code.ensure_loaded(driver)

    if function_exported?(driver, :await_output_released, 1) do
      case driver.await_output_released(@output_release_timeout_ms) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Wake audio starts on a busy output: #{inspect(reason)}")
      end
    end

    :ok
  catch
    kind, reason ->
      Logger.error("Output release check failed: #{inspect({kind, reason})}")
  end

  defp call_receiver(receiver, action) do
    case apply(receiver, action, []) do
      :ok -> :ok
      other -> Logger.warning("#{inspect(receiver)}.#{action}/0 returned #{inspect(other)}")
    end
  catch
    kind, reason ->
      Logger.error("#{inspect(receiver)}.#{action}/0 failed: #{inspect({kind, reason})}")
  end

  defp music_receivers,
    do:
      Application.get_env(:robine_wake, :music_receivers, [
        RobineWake.AirPlay,
        RobineWake.BluetoothAudio
      ])
end
