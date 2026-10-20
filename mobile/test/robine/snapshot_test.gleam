import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/time/duration
import gleam/time/timestamp
import robine/alarm
import robine/calendar
import robine/hue
import robine/id
import robine/level
import robine/nap
import robine/session
import robine/snapshot

@external(javascript, "../test_ffi.mjs", "read_fixture")
fn read_fixture(name: String) -> String

/// A `state.get` response recorded from the Raspberry Pi.
pub fn decodes_a_recorded_state_test() {
  let decoder = decode.at(["body"], snapshot.decoder())
  let assert Ok(clock) = json.parse(read_fixture("state_fixture.json"), decoder)
  assert clock.http_endpoints == ["http://192.168.1.3:4000/api/v1/command"]
  assert clock.active_session == None
  assert clock.smartphone_dismiss
    == snapshot.SmartphoneDismiss(enabled: False, locked: True)
  let assert [morning, ..] = clock.alarms
  assert alarm.time_label(morning) == "06:15"
  assert morning.settings.days == calendar.every_day()
  // A light switched off remembers its room.
  assert morning.settings.light.switch
    == alarm.SwitchedOff(
      Some(alarm.Target(
        id: id.from_string("cb20ac8a-cf99-4267-a2e0-9d995b3ce9a2"),
        name: Some("Chambre"),
      )),
    )
  assert list.length(morning.next_rings) == 5
  assert clock.hue
    == hue.Paired(bridge: "192.168.1.193", reachable: False, target_count: 0)
  assert clock.breathing == hue.Resting
  let assert Some(device) = clock.device
  assert device.firmware == Some("0.1.0")
  assert device.network == snapshot.Available
  assert list.length(clock.sounds) > 3
  let assert [snapshot.RemoteButton(name:, ..)] = clock.remote.buttons
  assert name == "Bouton chevet Wi-Fi"
  let assert [last, previous, ..] = clock.recent_sessions
  assert last.outcome == session.Dismissed
  assert previous.outcome == session.Missed
}

pub fn decodes_a_breathing_session_test() {
  let text =
    "{\"configured\":true,\"state\":\"available\",\"bridge_host\":\"hue.local\",\"breathing\":{\"active\":true,\"phase\":\"exhale\",\"phase_started_at\":\"2026-10-20T21:00:00Z\",\"remaining_seconds\":300,\"audio\":{\"active\":true,\"volume_percent\":40}}}"
  let assert Ok(clock) =
    json.parse("{\"hue\":" <> text <> "}", snapshot.decoder())
  assert clock.hue
    == hue.Paired(bridge: "hue.local", reachable: True, target_count: 0)
  let assert hue.Guided(
    phase: hue.Exhale,
    clock: hue.StartedAt(started),
    remaining: Some(remaining),
    ambience: True,
    volume: Some(volume),
    ..,
  ) = clock.breathing
  assert remaining == duration.minutes(5)
  assert volume == level.percent(40)
  // Three seconds into a six-second exhale.
  let now = timestamp.add(started, duration.seconds(3))
  assert hue.phase_progress(clock.breathing, now) == 0.5
  assert hue.phase_progress(
      clock.breathing,
      timestamp.add(now, duration.hours(1)),
    )
    == 1.0
}

pub fn older_firmware_tells_how_long_the_phase_has_lasted_test() {
  let text =
    "{\"hue\":{\"configured\":true,\"breathing\":{\"active\":true,\"phase_elapsed_ms\":1000}}}"
  let assert Ok(clock) = json.parse(text, snapshot.decoder())
  assert hue.phase_progress(clock.breathing, timestamp.system_time()) == 0.25
}

pub fn a_finished_session_is_not_active_test() {
  let text = "{\"active_session\":{\"id\":\"s\",\"state\":\"dismissed\"}}"
  let assert Ok(clock) = json.parse(text, snapshot.decoder())
  assert clock.active_session == None
  let text =
    "{\"active_session\":{\"id\":\"s\",\"state\":\"ringing\",\"audio_phase\":\"strong\"}}"
  let assert Ok(clock) = json.parse(text, snapshot.decoder())
  let assert Some(session.Active(
    stage: session.Ringing,
    phase: session.StrongPhase,
    ..,
  )) = clock.active_session
}

pub fn a_one_shot_date_makes_a_nap_test() {
  let text =
    "{\"alarms\":[{\"id\":\"nap\",\"enabled\":true,\"local_time\":\"14:20:00\",\"one_shot_date\":\"2026-01-15\",\"days_of_week\":[],\"next_occurrences\":[\"2026-01-15T14:20:00+01:00\"]}]}"
  let assert Ok(clock) = json.parse(text, snapshot.decoder())
  assert clock.alarms == []
  let assert Ok(rings_at) = timestamp.parse_rfc3339("2026-01-15T13:20:00Z")
  assert clock.nap == Some(nap.Nap(rings_at:))
  let assert Ok(now) = timestamp.parse_rfc3339("2026-01-15T13:00:00Z")
  assert nap.pending(clock.nap, now) == Some(rings_at)
  assert nap.pending(clock.nap, timestamp.add(now, duration.minutes(30)))
    == None
}

pub fn an_alarm_without_any_day_is_refused_test() {
  let text = "{\"alarms\":[{\"id\":\"a\",\"days_of_week\":[]}]}"
  let assert Error(_) = json.parse(text, snapshot.decoder())
  let text = "{\"alarms\":[{\"id\":\"a\",\"days_of_week\":[8]}]}"
  let assert Error(_) = json.parse(text, snapshot.decoder())
}

/// The clock never stores these; reading one means something is wrong.
pub fn an_alarm_beyond_the_clock_bounds_is_refused_test() {
  let alarm = fn(fields) {
    "{\"alarms\":[{\"id\":\"a\",\"days_of_week\":[1]," <> fields <> "}]}"
  }
  let assert Ok(_) = json.parse(alarm("\"label\":\"ok\""), snapshot.decoder())
  let assert Error(_) =
    json.parse(
      alarm("\"volume_profile\":{\"start\":90,\"ceiling\":20}"),
      snapshot.decoder(),
    )
  let assert Error(_) =
    json.parse(
      alarm("\"light_profile\":{\"start_brightness\":0}"),
      snapshot.decoder(),
    )
  let assert Error(_) =
    json.parse(alarm("\"prewake_seconds\":7200"), snapshot.decoder())
}
