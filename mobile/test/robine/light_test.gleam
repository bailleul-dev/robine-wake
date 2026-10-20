import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import robine/command
import robine/id
import robine/level
import robine/light
import robine/snapshot

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

pub fn lengths_stay_within_four_hours_test() {
  assert light.minutes(light.length(0)) == 1
  assert light.minutes(light.length(30)) == 30
  assert light.minutes(light.length(500)) == 240
}

pub fn programs_encode_as_the_clock_reads_them_test() {
  assert json.to_string(light.encode(light.Dawn(light.length(30))))
    == "{\"program\":\"dawn\",\"duration_ms\":1800000}"
  assert json.to_string(light.encode(light.Sunset(light.length(1))))
    == "{\"program\":\"sunset\",\"duration_ms\":60000}"
  assert json.to_string(light.encode(light.Off)) == "{\"program\":\"off\"}"
}

pub fn the_program_is_sent_as_light_program_test() {
  assert command.encode(command.StartLightProgram(light.Off, None), "id-1")
    == "{\"v\":1,\"id\":\"id-1\",\"op\":\"light.program\",\"body\":{\"program\":\"off\"}}"
  let refused =
    "{\"v\":1,\"id\":\"a\",\"status\":\"error\",\"error\":{\"code\":\"light_unavailable\"}}"
  assert command.reply(command.StartLightProgram(light.Off, None), "a", refused)
    == Error(command.Refused(command.LightUnavailable))
}

pub fn a_reading_shows_each_pixel_and_the_program_test() {
  let answer = fn(body) {
    "{\"v\":1,\"id\":\"r\",\"status\":\"ok\",\"body\":" <> body <> "}"
  }
  let assert Ok(command.LightReply(light.Reading(showing:, pixels:))) =
    command.reply(
      command.GetLight,
      "r",
      answer(
        "{\"program\":\"breathing\",\"cadence\":\"0-4-0-6\",\"elapsed_ms\":4000,\"duration_ms\":300000,\"pixels\":\"0a0000ff8800\"}",
      ),
    )
  assert pixels == ["#0a0000", "#ff8800"]
  assert showing
    == light.Running(
      program: "breathing",
      cadence: Some("0-4-0-6"),
      elapsed_ms: 4000,
      duration_ms: 300_000,
    )
  assert light.describe(showing) == "Respiration 0-4-0-6"

  // The answer to a program is a reading too.
  let assert Ok(command.LightReply(light.Reading(showing: light.Dark, ..))) =
    command.reply(
      command.StartLightProgram(light.Off, None),
      "r",
      answer("{\"program\":null,\"pixels\":\"000000000000\"}"),
    )
  let assert Ok(command.LightReply(light.Reading(showing: light.Steady, ..))) =
    command.reply(command.GetLight, "r", answer("{\"pixels\":\"102030\"}"))
}

pub fn a_reading_light_is_a_timed_program_test() {
  assert json.to_string(
      light.encode(light.ReadingLight(light.length(240), sunset: None)),
    )
    == "{\"program\":\"reading\",\"duration_ms\":14400000,\"sunset_ms\":0}"
  assert json.to_string(
      light.encode(light.ReadingLight(
        light.length(45),
        sunset: Some(light.length(20)),
      )),
    )
    == "{\"program\":\"reading\",\"duration_ms\":2700000,\"sunset_ms\":1200000}"
  assert light.describe(light.Running(
      program: "reading",
      cadence: None,
      elapsed_ms: 0,
      duration_ms: 1,
    ))
    == "Lecture"
}

pub fn an_ambience_rides_along_the_program_test() {
  let storm = id.from_string("storm_rain_lasonotheque_2719")
  let ambience = light.Ambience(sound: storm, volume: level.percent(30))
  assert json.to_string(light.encode_with(
      light.Sunset(light.length(20)),
      Some(ambience),
    ))
    == "{\"program\":\"sunset\",\"duration_ms\":1200000,\"ambience\":{\"sound_id\":\"storm_rain_lasonotheque_2719\",\"volume_percent\":30}}"
  // Turning the strip off carries no sound.
  assert json.to_string(light.encode_with(light.Off, Some(ambience)))
    == "{\"program\":\"off\"}"

  let text =
    "{\"light_ambience\":{\"active\":true,\"sound_id\":\"storm_rain_lasonotheque_2719\",\"volume_percent\":30,\"gain_percent\":12,\"audio\":{\"active\":true}}}"
  let assert Ok(clock) = json.parse(text, snapshot.decoder())
  assert clock.ambience
    == Some(light.Playing(
      sound: "storm_rain_lasonotheque_2719",
      volume: 30,
      gain: 12,
      audible: True,
    ))
  let assert Ok(clock) =
    json.parse("{\"light_ambience\":{\"active\":false}}", snapshot.decoder())
  assert clock.ambience == None
}

pub fn every_offered_pattern_is_a_cadence_test() {
  light.patterns
  |> list.each(fn(pattern) {
    assert light.cadence(pattern.0) |> result.is_ok
  })
  assert list.any(light.patterns, fn(pattern) { pattern.0 == light.coherence })
}
