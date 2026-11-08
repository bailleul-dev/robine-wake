import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/time/duration
import gleam/time/timestamp
import robine/alarm
import robine/breathing
import robine/calendar
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
  // A Hue sunrise, switched off, recorded before the strip.
  assert morning.settings.light
    == alarm.Light(dawn: False, afterwards: alarm.TurnOff)
  assert list.length(morning.next_rings) == 5
  assert clock.breathing == breathing.Resting
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
    "{\"breathing\":{\"active\":true,\"cadence\":\"2-4-1-6\",\"hold_empty_ms\":2000,\"inhale_ms\":4000,\"hold_full_ms\":1000,\"exhale_ms\":6000,\"started_at\":\"2026-10-20T21:00:00Z\",\"server_time\":\"2026-10-20T21:00:30Z\",\"remaining_seconds\":270,\"volume_percent\":40,\"audio\":{\"active\":true},\"light\":{\"active\":false}}}"
  let assert Ok(clock) = json.parse(text, snapshot.decoder())
  let assert breathing.Guided(
    cadence: "2-4-1-6",
    breath:,
    started:,
    ends: Some(ends),
    volume:,
    ambience: True,
    strip: False,
  ) = clock.breathing
  assert volume == level.percent(40)
  assert timestamp.difference(started, ends) == duration.minutes(5)
  // 13 s a breath: hold, inhale, hold, exhale.
  assert breathing.phase_at(breath, 1000) == #(breathing.HoldEmpty, 0.5, 0.0)
  assert breathing.phase_at(breath, 3000) == #(breathing.Inhale, 0.25, 0.25)
  assert breathing.phase_at(breath, 6500) == #(breathing.HoldFull, 0.5, 1.0)
  assert breathing.phase_at(breath, 10_000) == #(breathing.Exhale, 0.5, 0.5)
  assert breathing.phase_at(breath, 13_000 + 3000)
    == #(breathing.Inhale, 0.25, 0.25)
  assert breathing.elapsed_ms(
      started,
      timestamp.add(started, duration.seconds(3)),
    )
    == 3000
}

pub fn no_session_without_its_start_test() {
  let text = "{\"breathing\":{\"active\":true,\"cadence\":\"0-4-0-6\"}}"
  let assert Ok(clock) = json.parse(text, snapshot.decoder())
  assert clock.breathing == breathing.Resting
  let assert Ok(clock) = json.parse("{\"hue\":{}}", snapshot.decoder())
  assert clock.breathing == breathing.Resting
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
    json.parse(alarm("\"prewake_seconds\":7200"), snapshot.decoder())
}

/// Firmware without the night window reads as switched off.
pub fn night_radio_defaults_when_absent_test() {
  let decoder = decode.at(["body"], snapshot.decoder())
  let assert Ok(clock) = json.parse(read_fixture("state_fixture.json"), decoder)
  assert clock.night_radio
    == snapshot.NightRadio(
      enabled: False,
      start: "23:00",
      until: "07:00",
      silenced: False,
    )
}

pub fn decodes_the_night_radio_window_test() {
  let text =
    "{\"night_radio\":{\"enabled\":true,\"start\":\"22:30\",\"end\":\"06:15\",\"state\":\"silenced\",\"reason\":\"quiet_window\"}}"
  let assert Ok(clock) = json.parse(text, snapshot.decoder())
  assert clock.night_radio
    == snapshot.NightRadio(
      enabled: True,
      start: "22:30",
      until: "06:15",
      silenced: True,
    )
}

pub fn shifts_night_times_around_midnight_test() {
  assert snapshot.shift_time("23:30", 30) == "00:00"
  assert snapshot.shift_time("00:00", -30) == "23:30"
  assert snapshot.shift_time("06:45", 30) == "07:15"
  assert snapshot.shift_time("bad", 30) == "bad"
}
