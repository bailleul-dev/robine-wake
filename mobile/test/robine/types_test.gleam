import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import robine/types

@external(javascript, "../test_ffi.mjs", "read_fixture")
fn read_fixture(name: String) -> String

/// A `state.get` response recorded from the Raspberry Pi.
pub fn decodes_a_recorded_state_test() {
  let decoder = decode.at(["body"], types.state_body_decoder())
  let assert Ok(body) = json.parse(read_fixture("state_fixture.json"), decoder)
  assert body.http_endpoints == ["http://192.168.1.3:4000/api/v1/command"]
  assert body.active_session == None
  assert body.smartphone_dismiss
    == types.SmartphoneDismiss(enabled: False, locked: True)
  let assert [alarm, ..] = body.alarms
  assert alarm.local_time == "06:15:00"
  assert alarm.light_profile.target_name == Some("Chambre")
  let assert Some(hue) = body.hue
  assert hue.configured && hue.state == Some("unavailable")
  assert !hue.breathing.active
  let assert Some(device) = body.device
  assert device.firmware_version == Some("0.1.0")
  assert list.length(body.sounds) > 3
  let assert Some(remote) = body.remote_button
  let assert [button] = remote.buttons
  assert button.name == "Bouton chevet Wi-Fi"
}
