defmodule RobineWake do
  @moduledoc "Privacy-first smart alarm-clock domain API."

  alias RobineWake.{Alarm, Scheduler, Settings, WakeSession}

  def list_alarms, do: Settings.list_alarms()
  def create_alarm(attrs), do: Settings.create_alarm(attrs)
  def update_alarm(id, attrs), do: Settings.update_alarm(id, attrs)
  def delete_alarm(id, revision), do: Settings.delete_alarm(id, revision)
  def next_occurrences(alarm, count \\ 5), do: Alarm.next_occurrences(alarm, count)
  def trigger_now(alarm_id), do: Scheduler.trigger_now(alarm_id)
  def active_session, do: WakeSession.active()
  def dismiss, do: WakeSession.dismiss(:manual)
  def snooze, do: WakeSession.snooze()
end
