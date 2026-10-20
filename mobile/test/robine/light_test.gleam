import gleam/json
import gleam/list
import gleam/result
import robine/command
import robine/light

pub fn cadences_are_four_phases_with_an_inhale_and_an_exhale_test() {
  assert light.cadence(" 0-4-0-6 ") |> result.map(light.cadence_text)
    == Ok("0-4-0-6")
  assert light.cadence("0-4.5-0-5.5") |> result.is_ok
  assert light.cadence("4-4-4-4") |> result.is_ok
  ["", "4-6", "0-0-0-6", "0-4-0-0", "0-4-0-6-1", "0-x-0-6", "0-61-0-6"]
  |> list.each(fn(text) {
    assert light.cadence(text) == Error(Nil)
  })
}

pub fn lengths_stay_within_two_hours_test() {
  assert light.minutes(light.length(0)) == 1
  assert light.minutes(light.length(30)) == 30
  assert light.minutes(light.length(500)) == 120
}

pub fn programs_encode_as_the_clock_reads_them_test() {
  assert json.to_string(light.encode(light.Dawn(light.length(30))))
    == "{\"program\":\"dawn\",\"duration_ms\":1800000}"
  assert json.to_string(light.encode(light.Sunset(light.length(1))))
    == "{\"program\":\"sunset\",\"duration_ms\":60000}"
  let assert Ok(cadence) = light.cadence(light.coherence)
  assert json.to_string(light.encode(light.Breathing(cadence)))
    == "{\"program\":\"breathing\",\"cadence\":\"0-4-0-6\"}"
  assert json.to_string(light.encode(light.Off)) == "{\"program\":\"off\"}"
}

pub fn the_program_is_sent_as_light_program_test() {
  assert command.encode(command.StartLightProgram(light.Off), "id-1")
    == "{\"v\":1,\"id\":\"id-1\",\"op\":\"light.program\",\"body\":{\"program\":\"off\"}}"
  let refused =
    "{\"v\":1,\"id\":\"a\",\"status\":\"error\",\"error\":{\"code\":\"light_unavailable\"}}"
  assert command.reply(command.StartLightProgram(light.Off), "a", refused)
    == Error(command.Refused(command.LightUnavailable))
}
