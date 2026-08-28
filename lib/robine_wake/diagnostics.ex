defmodule RobineWake.Diagnostics do
  @moduledoc "Builds a local, pixel-free and secret-free diagnostic export."

  alias RobineWake.{Clock, EventLog, Health, Settings}

  def build do
    files = %{
      "configuration.json" => Settings.export_configuration(),
      "health.json" => Health.snapshot(),
      "metrics.json" => EventLog.metrics(),
      "recent_events.json" => EventLog.recent(100),
      "recent_sessions.json" => Settings.recent_sessions(100)
    }

    manifest =
      files
      |> Enum.map(fn {name, value} ->
        encoded = Jason.encode!(value)

        %{
          name: name,
          bytes: byte_size(encoded),
          sha256: :crypto.hash(:sha256, encoded) |> Base.encode16(case: :lower)
        }
      end)
      |> Enum.sort_by(& &1.name)

    %{
      format: "robine-wake-diagnostics",
      format_version: 1,
      generated_at: DateTime.to_iso8601(Clock.utc_now()),
      manifest: manifest,
      files: files
    }
  end
end
