defmodule RobineWake.UpdatePolicy do
  @moduledoc "Preflight policy for signed SSH/Fwup firmware installation."

  alias RobineWake.{Clock, ClockQuality, Scheduler, WakeSession}

  @critical_window_seconds 15 * 60

  def precheck do
    with :ok <- require_target(),
         :ok <- require_public_key(),
         :ok <- require_trusted_clock(),
         :ok <- require_idle_session(),
         :ok <- require_safe_alarm_window() do
      {:ok, []}
    end
  end

  def status do
    key_path = Application.fetch_env!(:robine_wake, :firmware_public_key_path)

    case precheck() do
      {:ok, _options} ->
        %{
          state: :available,
          transport: :authenticated_ssh_fwup,
          signature: :ed25519_required,
          public_key_present: File.exists?(key_path),
          critical_window_seconds: @critical_window_seconds
        }

      {:error, reason} ->
        %{
          state: if(reason == :host_target, do: :available, else: :degraded),
          transport: :authenticated_ssh_fwup,
          signature: :ed25519_required,
          public_key_present: File.exists?(key_path),
          installable: false,
          reason: reason,
          critical_window_seconds: @critical_window_seconds
        }
    end
  end

  def allowed?(now, active_session, next_occurrences, public_key_present?) do
    cond do
      not public_key_present? -> {:error, :signing_key_unavailable}
      not is_nil(active_session) -> {:error, :wake_session_active}
      alarm_within_window?(now, next_occurrences) -> {:error, :alarm_critical_window}
      true -> :ok
    end
  end

  defp require_target do
    if Application.fetch_env!(:robine_wake, :target) == :host,
      do: {:error, :host_target},
      else: :ok
  end

  defp require_public_key do
    path = Application.fetch_env!(:robine_wake, :firmware_public_key_path)
    if File.regular?(path), do: :ok, else: {:error, :signing_key_unavailable}
  end

  defp require_trusted_clock do
    if ClockQuality.trusted?(), do: :ok, else: {:error, :clock_untrusted}
  end

  defp require_idle_session do
    if is_nil(WakeSession.active()), do: :ok, else: {:error, :wake_session_active}
  end

  defp require_safe_alarm_window do
    next_occurrences = Scheduler.status().next |> Map.values()

    case allowed?(Clock.utc_now(), nil, next_occurrences, true) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp alarm_within_window?(now, occurrences) do
    Enum.any?(occurrences, fn occurrence ->
      case parse_datetime(occurrence) do
        {:ok, datetime} -> DateTime.diff(datetime, now, :second) <= @critical_window_seconds
        :error -> true
      end
    end)
  end

  defp parse_datetime(%DateTime{} = datetime), do: {:ok, datetime}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> :error
    end
  end

  defp parse_datetime(_value), do: :error
end
