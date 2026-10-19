import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import robine/alarm.{Alarm, Light, Settings, SwitchedOff, Target, Volume, Weekly}
import robine/calendar.{Friday, Monday, Saturday, Sunday, Tuesday}
import robine/command
import robine/draft.{Draft}
import robine/snapshot

fn week_alarm() -> alarm.Alarm {
  let assert Ok(time) = calendar.time(6, 45)
  let assert Ok(days) =
    calendar.days([
      Monday,
      Tuesday,
      calendar.Wednesday,
      calendar.Thursday,
      Friday,
    ])
  Alarm(
    id: "alarm-1",
    revision: 4,
    next_rings: [],
    settings: Settings(
      label: "Semaine",
      enabled: True,
      time:,
      schedule: Weekly(days),
      timezone: "Europe/Paris",
      sound: "rain",
      strong_sound: "storm",
      ramp_seconds: 1200,
      volume: Volume(start: 1, ceiling: 80, strong: 80),
      light: Light(
        ..alarm.no_light,
        switch: SwitchedOff(Some(Target(id: "room", name: None))),
      ),
    ),
  )
}

pub fn an_alarm_survives_the_editor_test() {
  let alarm = week_alarm()
  assert draft.validate(draft.from_alarm(alarm)) == Ok(alarm.settings)
}

pub fn the_update_body_is_what_the_clock_expects_test() {
  let alarm = week_alarm()
  let body =
    command.body(command.UpdateAlarm(
      id: alarm.id,
      revision: alarm.revision,
      settings: alarm.settings,
    ))
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
      start_volume: 90,
      light_on: True,
      light_target: None,
    )
  assert draft.validate(broken)
    == Error([
      draft.NoLabel,
      draft.NoDay,
      draft.StartAboveCeiling,
      draft.NoLightTarget,
    ])
  let dimming = Draft(..editing, light_on: True, light_start: 80, light_end: 20)
  assert draft.validate(dimming) == Error([draft.LightDimming])
  let late = Draft(..editing, hour: 24)
  assert draft.validate(late) == Error([draft.OutOfRange])
}

pub fn a_new_alarm_lights_the_first_room_test() {
  let fresh =
    draft.new(
      [],
      [snapshot.HueTarget(id: "bedroom", name: "Chambre")],
      "Europe/Paris",
    )
  assert fresh.light_on
  assert fresh.light_target
    == Some(Target(id: "bedroom", name: Some("Chambre")))
  let assert Ok(settings) = draft.validate(fresh)
  assert settings.sound == "default"
  let none = draft.new([], [], "Europe/Paris")
  assert !none.light_on
  let assert Ok(_) = draft.validate(none)
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
