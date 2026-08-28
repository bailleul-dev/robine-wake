defmodule RobineWake.ClockQuality do
  @moduledoc "Tracks whether wall-clock time is safe for automatic alarm arming."

  use GenServer

  alias RobineWake.Clock

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def trusted?, do: GenServer.call(__MODULE__, :trusted?)
  def status, do: GenServer.call(__MODULE__, :status)
  def confirm, do: GenServer.call(__MODULE__, :confirm)
  def mark_untrusted(reason), do: GenServer.call(__MODULE__, {:mark_untrusted, reason})

  @impl true
  def init(_opts) do
    quality = Application.get_env(:robine_wake, :initial_time_quality, :untrusted)
    maybe_subscribe_to_ntp()

    {:ok,
     %{
       quality: quality,
       source: if(quality == :trusted, do: :configured, else: :boot),
       confirmed_at: nil,
       reason: if(quality == :trusted, do: nil, else: :confirmation_required)
     }}
  end

  @impl true
  def handle_call(:trusted?, _from, state), do: {:reply, state.quality == :trusted, state}
  def handle_call(:status, _from, state), do: {:reply, public(state), state}

  def handle_call(:confirm, _from, state) do
    next = trust(state, :user_confirmed, Clock.utc_now())

    notify_scheduler()
    {:reply, {:ok, public(next)}, next}
  end

  def handle_call({:mark_untrusted, reason}, _from, state) do
    next = %{state | quality: :untrusted, source: :runtime, reason: reason}
    notify_scheduler()
    {:reply, :ok, next}
  end

  @impl true
  def handle_info({:nerves_time, event, report}, state)
      when event in [:sync_acquired, :sync_updated] do
    next = trust(state, :ntp, sync_time(report))
    notify_scheduler()
    {:noreply, next}
  end

  def handle_info(
        {:nerves_time, :sync_status, %{synchronized?: true} = report},
        state
      ) do
    next = trust(state, :ntp, sync_time(report))
    notify_scheduler()
    {:noreply, next}
  end

  def handle_info({:nerves_time, _event, _report}, state), do: {:noreply, state}

  defp trust(state, source, confirmed_at) do
    %{
      state
      | quality: :trusted,
        source: source,
        confirmed_at: confirmed_at,
        reason: nil
    }
  end

  defp sync_time(%{last_sync_at: %DateTime{} = synced_at}), do: synced_at
  defp sync_time(_report), do: Clock.utc_now()

  defp maybe_subscribe_to_ntp do
    if Application.get_env(:robine_wake, :auto_confirm_ntp, false) do
      apply(NervesTime, :subscribe, [self()])
    end
  rescue
    _exception -> :ok
  catch
    :exit, _reason -> :ok
  end

  defp public(state) do
    %{
      state: if(state.quality == :trusted, do: :healthy, else: :degraded),
      quality: state.quality,
      trusted: state.quality == :trusted,
      source: state.source,
      confirmed_at: state.confirmed_at,
      reason: state.reason
    }
  end

  defp notify_scheduler do
    if Process.whereis(RobineWake.Scheduler),
      do: send(RobineWake.Scheduler, :time_quality_changed)
  end
end
