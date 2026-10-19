//// An alarm while it is edited: free to be incomplete until it is checked into
//// the settings the clock accepts.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import robine/alarm.{
  type Afterwards, type Alarm, type Settings, type Target, Light, Settings,
  SwitchedOff, SwitchedOn, Target, Volume, Weekly,
}
import robine/calendar.{type Weekday}
import robine/snapshot.{type HueTarget, type Sound}

pub type Draft {
  Draft(
    origin: Origin,
    label: String,
    enabled: Bool,
    hour: Int,
    minute: Int,
    days: Set(Weekday),
    timezone: String,
    sound: String,
    strong_sound: String,
    start_volume: Int,
    ceiling_volume: Int,
    strong_volume: Int,
    ramp_minutes: Int,
    light_on: Bool,
    light_target: Option(Target),
    light_start: Int,
    light_end: Int,
    light_ramp_minutes: Int,
    afterwards: Afterwards,
  )
}

pub type Origin {
  New
  Existing(id: String, revision: Int)
}

/// Why a draft cannot be saved yet.
pub type Problem {
  NoLabel
  NoDay
  StartAboveCeiling
  NoSound
  NoStrongSound
  NoLightTarget
  LightDimming
  OutOfRange
}

pub fn new(
  sounds: List(Sound),
  targets: List(HueTarget),
  timezone: String,
) -> Draft {
  let target = case targets {
    [first, ..] -> Some(Target(id: first.id, name: Some(first.name)))
    [] -> None
  }
  Draft(
    origin: New,
    label: "Mon réveil",
    enabled: True,
    hour: 7,
    minute: 0,
    days: set.from_list(calendar.weekdays),
    timezone:,
    sound: snapshot.default_sound(sounds, snapshot.Gentle),
    strong_sound: snapshot.default_sound(sounds, snapshot.Strong),
    start_volume: 15,
    ceiling_volume: 85,
    strong_volume: 85,
    ramp_minutes: 20,
    light_on: option.is_some(target),
    light_target: target,
    light_start: 1,
    light_end: 70,
    light_ramp_minutes: 15,
    afterwards: alarm.Restore,
  )
}

fn minutes(seconds: Int) -> Int {
  int.max(1, seconds / 60)
}

pub fn from_alarm(alarm: Alarm) -> Draft {
  let settings = alarm.settings
  let light = settings.light
  let #(light_on, light_target) = case light.switch {
    SwitchedOn(target) -> #(True, Some(target))
    SwitchedOff(last) -> #(False, last)
  }
  Draft(
    origin: Existing(id: alarm.id, revision: alarm.revision),
    label: settings.label,
    enabled: settings.enabled,
    hour: calendar.hour(settings.time),
    minute: calendar.minute(settings.time),
    days: case settings.schedule {
      Weekly(days) -> set.from_list(calendar.day_list(days))
      alarm.Once(_) -> set.new()
    },
    timezone: settings.timezone,
    sound: settings.sound,
    strong_sound: settings.strong_sound,
    start_volume: settings.volume.start,
    ceiling_volume: settings.volume.ceiling,
    strong_volume: settings.volume.strong,
    ramp_minutes: minutes(settings.ramp_seconds),
    light_on:,
    light_target:,
    light_start: light.start_brightness,
    light_end: light.end_brightness,
    light_ramp_minutes: minutes(light.ramp_seconds),
    afterwards: light.afterwards,
  )
}

pub fn editing(draft: Draft) -> Bool {
  draft.origin != New
}

/// Turns the light on, on the first target when it had none.
pub fn switch_light(draft: Draft, on: Bool, targets: List(HueTarget)) -> Draft {
  let light_target = case on, draft.light_target, targets {
    True, None, [first, ..] ->
      Some(Target(id: first.id, name: Some(first.name)))
    _, target, _ -> target
  }
  Draft(..draft, light_on: on, light_target:)
}

pub fn choose_target(
  draft: Draft,
  id: String,
  targets: List(HueTarget),
) -> Draft {
  let name = case list.find(targets, fn(target) { target.id == id }) {
    Ok(target) -> Some(target.name)
    Error(Nil) -> None
  }
  Draft(..draft, light_target: Some(Target(id:, name:)))
}

pub fn toggle_day(draft: Draft, day: Weekday) -> Draft {
  Draft(..draft, days: case set.contains(draft.days, day) {
    True -> set.delete(draft.days, day)
    False -> set.insert(draft.days, day)
  })
}

fn percentage(value: Int) -> Bool {
  value >= 0 && value <= 100
}

/// The settings to send, or every reason the draft is not ready.
pub fn validate(draft: Draft) -> Result(Settings, List(Problem)) {
  let label = string.trim(draft.label)
  let time = calendar.time(draft.hour, draft.minute)
  let days = calendar.days(set.to_list(draft.days))
  let switch = case draft.light_on, draft.light_target {
    True, Some(target) -> Ok(SwitchedOn(target))
    True, None -> Error(Nil)
    False, last -> Ok(SwitchedOff(last))
  }
  let problems =
    [
      #(label == "", NoLabel),
      #(result.is_error(days), NoDay),
      #(draft.start_volume > draft.ceiling_volume, StartAboveCeiling),
      #(string.trim(draft.sound) == "", NoSound),
      #(string.trim(draft.strong_sound) == "", NoStrongSound),
      #(result.is_error(switch), NoLightTarget),
      #(draft.light_on && draft.light_end < draft.light_start, LightDimming),
      #(
        result.is_error(time)
          || !list.all(
          [draft.start_volume, draft.ceiling_volume, draft.strong_volume],
          percentage,
        )
          || draft.light_start < 1
          || draft.light_end > 100
          || draft.ramp_minutes < 0
          || draft.ramp_minutes > 60
          || draft.light_ramp_minutes < 0
          || draft.light_ramp_minutes > 60,
        OutOfRange,
      ),
    ]
    |> list.filter_map(fn(check) {
      case check.0 {
        True -> Ok(check.1)
        False -> Error(Nil)
      }
    })
  case problems, time, days, switch {
    [], Ok(time), Ok(days), Ok(switch) ->
      Ok(Settings(
        label:,
        enabled: draft.enabled,
        time:,
        schedule: Weekly(days),
        timezone: draft.timezone,
        sound: draft.sound,
        strong_sound: draft.strong_sound,
        ramp_seconds: 60 * draft.ramp_minutes,
        volume: Volume(
          start: draft.start_volume,
          ceiling: draft.ceiling_volume,
          strong: draft.strong_volume,
        ),
        light: Light(
          switch:,
          start_brightness: draft.light_start,
          end_brightness: draft.light_end,
          ramp_seconds: 60 * draft.light_ramp_minutes,
          afterwards: draft.afterwards,
        ),
      ))
    _, _, _, _ -> Error(problems)
  }
}

pub fn describe(problem: Problem) -> String {
  case problem {
    NoLabel -> "Donnez un nom à ce réveil."
    NoDay -> "Choisissez au moins un jour."
    StartAboveCeiling -> "Le volume de départ dépasse le plafond."
    NoSound -> "Choisissez un son doux."
    NoStrongSound -> "Choisissez un son de renfort."
    NoLightTarget -> "Choisissez la pièce à éclairer."
    LightDimming -> "La lumière finale doit être au moins la première lueur."
    OutOfRange -> "Un réglage sort des limites du réveil."
  }
}
