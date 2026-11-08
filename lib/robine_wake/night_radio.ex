defmodule RobineWake.NightRadio do
  @moduledoc """
  Silences the Wi-Fi and Bluetooth radios during a nightly quiet window.

  The alarm never depends on a radio (ARCH-001), so they may be blocked while
  the user sleeps. Radios are silenced only when every condition holds:

    * the feature is enabled and local time is inside the window;
    * wall-clock time is trusted, so a boot during the night keeps the radios
      on until NTP has synchronized;
    * no wake session is running, so the smartphone can reach the clock while
      it rings.

  The target driver uses kernel rfkill soft blocks, which a reboot clears: the
  device always boots with its radios on. Any failure to evaluate a condition
  turns the radios back on. Requirements `NRV-008` to `NRV-011`.
  """

  use GenServer

  require Logger

  alias RobineWake.{Clock, ClockQuality, EventStream, Settings, WakeSession}

  @type reason ::
          :disabled
          | :outside_window
          | :clock_untrusted
          | :wake_session
          | :quiet_window
          | :evaluation_failed

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Current configuration and radio state."
  def status, do: GenServer.call(__MODULE__, :status)

  @doc "Re-evaluates the window now instead of waiting for the next tick."
  def evaluate, do: GenServer.call(__MODULE__, :evaluate)

  @doc "Whether the radios are currently blocked; false when the service is not running."
  def silenced? do
    case Process.whereis(__MODULE__) do
      nil -> false
      _pid -> GenServer.call(__MODULE__, :silenced?, 1_000)
    end
  catch
    :exit, _reason -> false
  end

  @doc "Asks a running service to re-read its settings."
  def notify_settings_changed do
    if pid = Process.whereis(__MODULE__), do: send(pid, :settings_changed)
    :ok
  end

  @doc false
  @spec decide(map(), DateTime.t(), boolean(), boolean()) :: {boolean(), reason()}
  def decide(config, now, trusted?, session_active?) do
    cond do
      not config.enabled -> {false, :disabled}
      not in_window?(config, now) -> {false, :outside_window}
      session_active? -> {false, :wake_session}
      not trusted? -> {false, :clock_untrusted}
      true -> {true, :quiet_window}
    end
  end

  @doc false
  def in_window?(%{start: start, end: finish, timezone: timezone}, now) do
    with {:ok, local} <- DateTime.shift_zone(now, timezone),
         {:ok, from} <- parse(start),
         {:ok, until} <- parse(finish) do
      time = local |> DateTime.to_time() |> Time.truncate(:second)

      if Time.compare(from, until) == :lt,
        do: not before?(time, from) and before?(time, until),
        else: not before?(time, from) or before?(time, until)
    else
      _invalid -> false
    end
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    state = %{
      driver: Application.fetch_env!(:robine_wake, :night_radio_driver),
      # Unknown until the first evaluation, so it is always applied.
      silenced: nil,
      reason: nil,
      changed_at: nil,
      error: nil
    }

    send(self(), :tick)
    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, public(state), state}
  def handle_call(:silenced?, _from, state), do: {:reply, state.silenced == true, state}

  def handle_call(:evaluate, _from, state) do
    next = apply_decision(state)
    {:reply, public(next), next}
  end

  @impl true
  def handle_info(:tick, state) do
    next = apply_decision(state)
    Process.send_after(self(), :tick, interval())
    {:noreply, next}
  end

  def handle_info(:settings_changed, state), do: {:noreply, apply_decision(state)}
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{silenced: true, driver: driver}) do
    _ = driver.set_silenced(false)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp apply_decision(state) do
    {silenced, reason} = current_decision()

    if silenced == state.silenced and is_nil(state.error) do
      %{state | reason: reason}
    else
      apply_silenced(state, silenced, reason)
    end
  end

  defp apply_silenced(state, silenced, reason) do
    case state.driver.set_silenced(silenced) do
      :ok ->
        if silenced != state.silenced, do: announce(silenced, reason)

        %{
          state
          | silenced: silenced,
            reason: reason,
            changed_at: changed_at(state, silenced),
            error: nil
        }

      {:error, error} ->
        if state.error != error,
          do: Logger.warning("Night radio could not apply #{silenced}: #{inspect(error)}")

        %{state | reason: reason, error: error}
    end
  end

  defp current_decision do
    decide(Settings.night_radio(), Clock.utc_now(), ClockQuality.trusted?(), session_active?())
  catch
    :exit, reason ->
      Logger.warning("Night radio keeps the radios on: #{inspect(reason)}")
      {false, :evaluation_failed}
  end

  defp session_active?, do: not is_nil(WakeSession.active())

  defp changed_at(%{silenced: same} = state, same), do: state.changed_at
  defp changed_at(_state, _silenced), do: Clock.utc_now()

  defp announce(silenced, reason) do
    Logger.info("Night radio #{if silenced, do: "silenced", else: "restored"} (#{reason})")
    if Process.whereis(EventStream), do: EventStream.publish("state.changed")
  end

  defp public(state) do
    config =
      try do
        Settings.night_radio()
      catch
        :exit, _reason -> %{enabled: false, start: nil, end: nil, timezone: nil}
      end

    %{
      enabled: config.enabled,
      start: config.start,
      end: config.end,
      timezone: config.timezone,
      state: public_state(state),
      reason: state.reason,
      changed_at: state.changed_at,
      error: state.error,
      radios: state.driver.status()
    }
  end

  defp public_state(%{error: error}) when not is_nil(error), do: :error
  defp public_state(%{silenced: true}), do: :silenced
  defp public_state(_state), do: :radios_on

  defp parse(<<hour::binary-size(2), ":", minute::binary-size(2)>>),
    do: Time.from_iso8601("#{hour}:#{minute}:00")

  defp parse(_value), do: {:error, :invalid_time}

  defp before?(left, right), do: Time.compare(left, right) == :lt

  defp interval, do: Application.get_env(:robine_wake, :night_radio_interval_ms, 5_000)
end
