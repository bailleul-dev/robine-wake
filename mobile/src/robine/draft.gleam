//// An alarm while it is edited. Each control already holds a value the clock
//// accepts; what remains is whether they agree with each other.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string
import robine/alarm.{
  type Afterwards, type Alarm, type Ramp, type Settings, type Switch, Light,
  Settings, SwitchedOff, SwitchedOn, Target, Volume,
}
import robine/calendar.{type Time, type Weekday}
import robine/hue.{type HueTarget}
import robine/id.{type Id}
import robine/level.{type Brightness, type Percent}
import robine/sound.{type Sound}

pub type Draft {
  Draft(
    origin: Origin,
    label: String,
    enabled: Bool,
    time: Time,
    /// May be empty while editing.
    days: Set(Weekday),
    timezone: String,
    sound: Id(Sound),
    strong_sound: Id(Sound),
    start_volume: Percent,
    ceiling_volume: Percent,
    strong_volume: Percent,
    ramp: Ramp,
    light: Switch,
    light_start: Brightness,
    light_end: Brightness,
    light_ramp: Ramp,
    afterwards: Afterwards,
  )
}

pub type Origin {
  New
  /// The alarm as it was read, which the clock checks the change against.
  Existing(Alarm)
}

/// Why a draft cannot be saved yet.
pub type Problem {
  NoLabel
  NoDay
  StartAboveCeiling
  LightDimming
}

fn first_target(targets: List(HueTarget)) -> Option(alarm.Target) {
  case targets {
    [first, ..] -> Some(Target(id: first.id, name: Some(first.name)))
    [] -> None
  }
}

pub fn new(
  sounds: List(Sound),
  targets: List(HueTarget),
  timezone: String,
) -> Draft {
  let assert Ok(time) = calendar.time(7, 0)
  Draft(
    origin: New,
    label: "Mon réveil",
    enabled: True,
    time:,
    days: set.from_list(calendar.weekdays),
    timezone:,
    sound: sound.default_sound(sounds, sound.Gentle),
    strong_sound: sound.default_sound(sounds, sound.Strong),
    start_volume: level.percent(15),
    ceiling_volume: level.percent(85),
    strong_volume: level.percent(85),
    ramp: alarm.ramp(20),
    light: case first_target(targets) {
      Some(target) -> SwitchedOn(target)
      None -> SwitchedOff(None)
    },
    light_start: level.brightness(1),
    light_end: level.brightness(70),
    light_ramp: alarm.ramp(15),
    afterwards: alarm.Restore,
  )
}

pub fn from_alarm(alarm: Alarm) -> Draft {
  let settings = alarm.settings
  let light = settings.light
  Draft(
    origin: Existing(alarm),
    label: settings.label,
    enabled: settings.enabled,
    time: settings.time,
    days: set.from_list(calendar.day_list(settings.days)),
    timezone: settings.timezone,
    sound: settings.sound,
    strong_sound: settings.strong_sound,
    start_volume: level.from(settings.volume.rise),
    ceiling_volume: level.to(settings.volume.rise),
    strong_volume: settings.volume.strong,
    ramp: settings.ramp,
    light: light.switch,
    light_start: level.from(light.glow),
    light_end: level.to(light.glow),
    light_ramp: light.ramp,
    afterwards: light.afterwards,
  )
}

pub fn editing(draft: Draft) -> Bool {
  draft.origin != New
}

pub fn light_on(draft: Draft) -> Bool {
  case draft.light {
    SwitchedOn(_) -> True
    SwitchedOff(_) -> False
  }
}

pub fn light_target(draft: Draft) -> Option(alarm.Target) {
  case draft.light {
    SwitchedOn(target) -> Some(target)
    SwitchedOff(last) -> last
  }
}

/// Turns the light on, on the room it lit last or else the first one; it
/// stays off when there is no room to light.
pub fn switch_light(draft: Draft, on: Bool, targets: List(HueTarget)) -> Draft {
  let target = option.or(light_target(draft), first_target(targets))
  let light = case on, target {
    True, Some(target) -> SwitchedOn(target)
    True, None -> draft.light
    False, last -> SwitchedOff(last)
  }
  Draft(..draft, light:)
}

pub fn choose_target(draft: Draft, target: HueTarget) -> Draft {
  let target = Target(id: target.id, name: Some(target.name))
  Draft(..draft, light: case draft.light {
    SwitchedOn(_) -> SwitchedOn(target)
    SwitchedOff(_) -> SwitchedOff(Some(target))
  })
}

pub fn toggle_day(draft: Draft, day: Weekday) -> Draft {
  Draft(..draft, days: case set.contains(draft.days, day) {
    True -> set.delete(draft.days, day)
    False -> set.insert(draft.days, day)
  })
}

/// The settings to send, or every reason the draft is not ready.
pub fn validate(draft: Draft) -> Result(Settings, List(Problem)) {
  let label = string.trim(draft.label)
  let days = calendar.days(set.to_list(draft.days))
  let rise = level.percent_rise(draft.start_volume, draft.ceiling_volume)
  let glow = level.brightness_rise(draft.light_start, draft.light_end)
  case label, days, rise, glow {
    _, Ok(days), Ok(rise), Ok(glow) if label != "" ->
      Ok(Settings(
        label:,
        enabled: draft.enabled,
        time: draft.time,
        days:,
        timezone: draft.timezone,
        sound: draft.sound,
        strong_sound: draft.strong_sound,
        ramp: draft.ramp,
        volume: Volume(rise:, strong: draft.strong_volume),
        light: Light(
          switch: draft.light,
          glow:,
          ramp: draft.light_ramp,
          afterwards: draft.afterwards,
        ),
      ))
    _, _, _, _ ->
      [
        #(label == "", NoLabel),
        #(days == Error(Nil), NoDay),
        #(rise == Error(Nil), StartAboveCeiling),
        #(glow == Error(Nil), LightDimming),
      ]
      |> list.filter_map(fn(check) {
        case check.0 {
          True -> Ok(check.1)
          False -> Error(Nil)
        }
      })
      |> Error
  }
}

pub fn describe(problem: Problem) -> String {
  case problem {
    NoLabel -> "Donnez un nom à ce réveil."
    NoDay -> "Choisissez au moins un jour."
    StartAboveCeiling -> "Le volume de départ dépasse le plafond."
    LightDimming -> "La lumière finale doit être au moins la première lueur."
  }
}
