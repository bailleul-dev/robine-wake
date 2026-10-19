import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import robine/alarm
import robine/calendar
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
  assert morning.settings.schedule == alarm.Weekly(calendar.every_day())
  // A light switched off remembers its room.
  assert morning.settings.light.switch
    == alarm.SwitchedOff(
      Some(alarm.Target(
        id: "cb20ac8a-cf99-4267-a2e0-9d995b3ce9a2",
        name: Some("Chambre"),
      )),
    )
  assert list.length(morning.next_rings) == 5
  assert clock.hue
    == snapshot.Paired(
      bridge: "192.168.1.193",
      reachable: False,
      target_count: 0,
    )
  assert clock.breathing == snapshot.Resting
  let assert Some(device) = clock.device
  assert device.firmware == Some("0.1.0")
  assert device.network == snapshot.Available
  assert list.length(clock.sounds) > 3
  let assert [snapshot.RemoteButton(name:, ..)] = clock.remote.buttons
  assert name == "Bouton chevet Wi-Fi"
  let assert [last, previous, ..] = clock.recent_sessions
  assert last.state == snapshot.Dismissed
  assert previous.state == snapshot.Missed
}

pub fn decodes_a_breathing_session_test() {
  let text =
    "{\"configured\":true,\"state\":\"available\",\"bridge_host\":\"hue.local\",\"breathing\":{\"active\":true,\"phase\":\"exhale\",\"phase_started_at\":\"2026-10-20T21:00:00Z\",\"remaining_seconds\":300,\"audio\":{\"active\":true,\"volume_percent\":40}}}"
  let assert Ok(clock) =
    json.parse("{\"hue\":" <> text <> "}", snapshot.decoder())
  assert clock.hue
    == snapshot.Paired(bridge: "hue.local", reachable: True, target_count: 0)
  let assert snapshot.Guided(
    phase: snapshot.Exhale,
    phase_ms: 6000,
    remaining_seconds: Some(300),
    ambience: True,
    volume: Some(40),
    phase_started_at: Some(_),
    ..,
  ) = clock.breathing
}

pub fn a_one_shot_date_makes_a_nap_test() {
  let text =
    "{\"alarms\":[{\"id\":\"nap\",\"enabled\":true,\"local_time\":\"14:20:00\",\"one_shot_date\":\"2026-01-15\",\"days_of_week\":[],\"next_occurrences\":[\"2026-01-15T14:20:00+01:00\"]}]}"
  let assert Ok(clock) = json.parse(text, snapshot.decoder())
  let assert [nap] = clock.alarms
  assert nap.settings.schedule == alarm.Once("2026-01-15")
  assert alarm.regular(clock.alarms) == []
  // 2026-01-15T13:00:00Z
  let now = 1_768_482_000_000
  assert alarm.pending_nap(clock.alarms, now) == Some(1_768_483_200_000)
  assert alarm.pending_nap(clock.alarms, now + 1_800_000) == None
}

pub fn an_alarm_without_any_day_is_refused_test() {
  let text = "{\"alarms\":[{\"id\":\"a\",\"days_of_week\":[]}]}"
  let assert Error(_) = json.parse(text, snapshot.decoder())
  let text = "{\"alarms\":[{\"id\":\"a\",\"days_of_week\":[8]}]}"
  let assert Error(_) = json.parse(text, snapshot.decoder())
}
