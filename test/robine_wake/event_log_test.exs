defmodule RobineWake.EventLogTest do
  use RobineWake.DomainCase

  alias RobineWake.Clock.Manual
  alias RobineWake.EventLog

  test "records correlated structured events and removes sensitive fields" do
    event =
      EventLog.emit(:example, %{
        source: :test,
        session_id: "session-1",
        alarm_id: "alarm-1",
        payload: %{
          reason: :verification,
          password: "never-store-this",
          pixels: <<0, 1, 2>>,
          nested: %{secret_token: "never-store-this-either", safe: true}
        }
      })

    assert event.session_id == "session-1"
    assert event.alarm_id == "alarm-1"
    assert event.payload == %{"nested" => %{"safe" => true}, "reason" => "verification"}
    assert byte_size(event.event_id) > 10
    assert %{events_recorded: 1, by_code: %{"example" => 1}} = EventLog.metrics()

    encoded = EventLog.recent() |> Jason.encode!()
    refute encoded =~ "never-store-this"
    refute encoded =~ "pixels"
    refute encoded =~ "password"
  end

  test "keeps a bounded event history while retaining total counters" do
    previous = Application.fetch_env!(:robine_wake, :telemetry_event_limit)
    Application.put_env(:robine_wake, :telemetry_event_limit, 3)
    on_exit(fn -> Application.put_env(:robine_wake, :telemetry_event_limit, previous) end)

    Enum.each(1..5, fn index -> EventLog.emit(:bounded, payload: %{index: index}) end)

    assert length(EventLog.recent(100)) == 3
    assert %{events_recorded: 5, by_code: %{"bounded" => 5}} = EventLog.metrics()
  end

  test "expires events after seven days" do
    EventLog.emit(:temporary)
    assert length(EventLog.recent()) == 1

    Manual.advance(8 * 24 * 60 * 60 * 1_000)
    assert EventLog.recent() == []
  end

  test "persists redacted critical events across a controlled restart" do
    EventLog.emit(:critical_example, %{
      severity: :critical,
      session_id: "session-critical",
      payload: %{reason: :test, password: "must-not-survive"}
    })

    path = Application.fetch_env!(:robine_wake, :critical_event_path)
    encoded = File.read!(path)
    refute encoded =~ "must-not-survive"
    assert encoded =~ "critical_example"

    :ok = Supervisor.terminate_child(RobineWake.Supervisor, RobineWake.EventLog)
    {:ok, _pid} = Supervisor.restart_child(RobineWake.Supervisor, RobineWake.EventLog)

    assert [%{"code" => "critical_example", "session_id" => "session-critical"}] =
             EventLog.recent(1)
  end
end
