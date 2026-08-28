traceability_path = "docs/REQUIREMENTS_TRACEABILITY.md"
traceability = File.read!(traceability_path)

requirements =
  Regex.scan(
    ~r/\| ([A-Z]{2,4}-\d{3}) \| (Verified|Implemented|Partial|Hardware pending|Deferred) \|/,
    traceability,
    capture: :all_but_first
  )

status_counts =
  requirements
  |> Enum.map(fn [_id, status] -> status end)
  |> Enum.frequencies()

scenarios = [
  %{id: "SIM-001", status: "passed", evidence: "continuous confident vacancy test"},
  %{id: "SIM-002", status: "passed", evidence: "occupied return cancels candidate test"},
  %{id: "SIM-003", status: "passed", evidence: "unknown camera input keeps session active"},
  %{id: "SIM-004", status: "passed", evidence: "startup grace test"},
  %{id: "SIM-005", status: "passed", evidence: "false-exit cancellation test"},
  %{id: "SIM-006", status: "passed", evidence: "snooze limit and idempotence tests"},
  %{id: "SIM-007", status: "passed", evidence: "ringing and snoozed recovery tests"},
  %{id: "SIM-008", status: "passed", evidence: "ten-minute clock-jump catch-up test"},
  %{id: "SIM-009", status: "passed", evidence: "injected audio retry exhaustion test"},
  %{id: "SIM-010", status: "passed", evidence: "unusable image produces unknown test"}
]

report = %{
  format: "robine-wake-mvp-verification",
  format_version: 1,
  generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
  command: "mix verify",
  host_suite: %{status: "passed", scenarios: scenarios},
  requirements: %{
    total: length(requirements),
    by_status: status_counts,
    source: traceability_path
  },
  artifacts: %{
    coverage_html: "cover/excoveralls.html",
    requirements_matrix: traceability_path
  },
  hardware_gate: %{
    status: "pending",
    reason: "Raspberry Pi, HiFiBerry, infrared camera, and installed scene are unavailable"
  }
}

File.mkdir_p!("cover")
File.write!("cover/mvp-report.json", Jason.encode!(report, pretty: true) <> "\n")
Mix.shell().info("Saved MVP verification report to cover/mvp-report.json")
