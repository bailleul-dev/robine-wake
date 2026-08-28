defmodule RobineWake.EventStreamTest do
  use RobineWake.DomainCase

  alias RobineWake.EventStream

  test "pushes events and replays events newer than Last-Event-ID" do
    {:ok, cursor, _older_events} = EventStream.subscribe()
    EventStream.publish("session.changed")

    assert_receive {:robine_event, %{id: event_id, event: "session.changed"}}
    assert event_id > cursor

    EventStream.unsubscribe()
    {:ok, ^event_id, replay} = EventStream.subscribe(cursor)
    assert [%{id: ^event_id, event: "session.changed"}] = replay
    EventStream.unsubscribe()
  end

  test "carries state supplied by the Raspberry to subscribers" do
    {:ok, _cursor, _older_events} = EventStream.subscribe()
    EventStream.publish("breathing.changed", %{cycle_count: 3, phase: :exhale})

    assert_receive {:robine_event,
                    %{
                      event: "breathing.changed",
                      data: %{cycle_count: 3, phase: :exhale}
                    }}

    EventStream.unsubscribe()
  end
end
