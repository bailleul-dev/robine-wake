import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import robine/alarm.{Alarm, Light, Settings, SwitchedOff, SwitchedOn, Target}
import robine/calendar.{Friday, Monday, Saturday, Sunday, Tuesday}
import robine/command
import robine/draft.{Draft}
import robine/hue
import robine/id
import robine/level
import robine/sound

pub fn week_alarm() -> alarm.Alarm {
  let assert Ok(time) = calendar.time(6, 45)
  let assert Ok(days) =
    calendar.days([
      Monday,
      Tuesday,
      calendar.Wednesday,
      calendar.Thursday,
      Friday,
    ])
  let assert Ok(rise) = level.percent_rise(level.percent(1), level.percent(80))
  let assert Ok(ramp) = alarm.ramp_from_seconds(1200)
  Alarm(
    id: id.from_string("alarm-1"),
    revision: 4,
    next_rings: [],
    settings: Settings(
      label: "Semaine",
      enabled: True,
      time:,
      days:,
      timezone: "Europe/Paris",
      sound: id.from_string("rain"),
      strong_sound: id.from_string("storm"),
      ramp:,
      volume: alarm.Volume(rise:, strong: level.percent(80)),
      light: Light(
        ..alarm.no_light(),
        switch: SwitchedOff(
          Some(Target(id: id.from_string("room"), name: None)),
        ),
      ),
    ),
  )
}

pub fn an_alarm_survives_the_editor_test() {
  let alarm = week_alarm()
  assert draft.validate(draft.from_alarm(alarm)) == Ok(alarm.settings)
}

/// A ramp the editor cannot show to the second is kept as the clock has it.
pub fn an_odd_ramp_survives_the_editor_test() {
  let alarm = week_alarm()
  let assert Ok(ramp) = alarm.ramp_from_seconds(90)
  let alarm = Alarm(..alarm, settings: Settings(..alarm.settings, ramp:))
  let assert Ok(settings) = draft.validate(draft.from_alarm(alarm))
  assert settings.ramp == ramp
  assert alarm.ramp_minutes(ramp) == 2
}

pub fn the_update_body_is_what_the_clock_expects_test() {
  let alarm = week_alarm()
  let body = command.body(command.UpdateAlarm(alarm:, settings: alarm.settings))
  assert json.to_string(body)
    == "{\"alarm_id\":\"alarm-1\",\"alarm\":{\"label\":\"Semaine\",\"enabled\":true,\"local_time\":\"06:45\",\"days_of_week\":[1,2,3,4,5],\"timezone\":\"Europe/Paris\",\"sound_id\":\"rain\",\"strong_sound_id\":\"storm\",\"prewake_seconds\":1200,\"volume_profile\":{\"start\":1,\"ceiling\":80,\"strong\":80,\"ramp_seconds\":1200},\"light_profile\":{\"enabled\":false,\"start_brightness\":1,\"end_brightness\":70,\"ramp_seconds\":900,\"end_behavior\":\"restore\",\"target_id\":\"room\"},\"dismiss_policy\":\"manual\",\"snooze\":{\"enabled\":false},\"revision\":4}}"
}

pub fn every_problem_is_reported_test() {
  let editing = draft.from_alarm(week_alarm())
  let broken =
    Draft(
      ..editing,
      label: "  ",
      days: set.new(),
      start_volume: level.percent(90),
      light_start: level.brightness(80),
      light_end: level.brightness(20),
    )
  assert draft.validate(broken)
    == Error([
      draft.NoLabel,
      draft.NoDay,
      draft.StartAboveCeiling,
      draft.LightDimming,
    ])
}

pub fn levels_and_ramps_stay_in_bounds_test() {
  assert level.percent_to_int(level.percent(140)) == 100
  assert level.percent_to_int(level.percent(-3)) == 0
  assert level.brightness_to_int(level.brightness(0)) == 1
  assert level.percent_from_int(101) == Error(Nil)
  assert alarm.ramp_minutes(alarm.ramp(90)) == 60
  assert alarm.ramp_from_seconds(3601) == Error(Nil)
}

pub fn a_new_alarm_lights_the_first_room_test() {
  let bedroom = hue.HueTarget(id: id.from_string("bedroom"), name: "Chambre")
  let fresh = draft.new([], [bedroom], "Europe/Paris")
  assert fresh.light
    == SwitchedOn(Target(id: id.from_string("bedroom"), name: Some("Chambre")))
  let assert Ok(settings) = draft.validate(fresh)
  assert settings.sound == sound.built_in()
  let none = draft.new([], [], "Europe/Paris")
  assert !draft.light_on(none)
  let assert Ok(_) = draft.validate(none)
}

pub fn the_light_cannot_be_on_without_a_room_test() {
  let none = draft.new([], [], "Europe/Paris")
  assert !draft.light_on(draft.switch_light(none, True, []))
  // Switched off, it remembers its room and finds it again.
  let bedroom = hue.HueTarget(id: id.from_string("bedroom"), name: "Chambre")
  let lit = draft.new([], [bedroom], "Europe/Paris")
  let off = draft.switch_light(lit, False, [])
  assert draft.light_target(off) == draft.light_target(lit)
  assert draft.switch_light(off, True, []).light == lit.light
}

pub fn days_read_like_a_calendar_test() {
  let label = fn(days) {
    let assert Ok(days) = calendar.days(days)
    calendar.days_label(days)
  }
  assert label([Friday, Monday, Tuesday, calendar.Wednesday, calendar.Thursday])
    == "En semaine"
  assert label([Sunday, Saturday]) == "Le week-end"
  assert label([Friday, Monday, Tuesday]) == "L · M · V"
  assert calendar.days([]) == Error(Nil)
  assert list.map(calendar.week, calendar.number) == [1, 2, 3, 4, 5, 6, 7]
}
