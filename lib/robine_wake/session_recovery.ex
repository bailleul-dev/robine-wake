defmodule RobineWake.SessionRecovery do
  @moduledoc false

  use Task, restart: :transient

  alias RobineWake.{Clock, Settings, WakeSession}

  @active_states ~w(starting ringing exit_candidate snoozed failed_safe)

  def start_link(_opts), do: Task.start_link(__MODULE__, :run, [])

  def run do
    case Enum.find(Settings.recent_sessions(20), &(&1["state"] in @active_states)) do
      nil -> :ok
      session -> restore_or_expire(session)
    end
  end

  defp restore_or_expire(session) do
    max_age = Application.fetch_env!(:robine_wake, :max_session_ms)

    with {:ok, started_at, _offset} <-
           DateTime.from_iso8601(session["started_at"] || session["created_at"]),
         age when age >= 0 and age <= max_age <-
           DateTime.diff(Clock.utc_now(), started_at, :millisecond),
         {:ok, alarm} <- Settings.get_alarm(session["alarm_id"]) do
      WakeSession.restore(alarm, session)
    else
      _ ->
        Settings.update_session(session["id"], %{
          state: :timed_out,
          terminal_reason: :expired_during_restart,
          ended_at: Clock.utc_now()
        })
    end
  end
end
