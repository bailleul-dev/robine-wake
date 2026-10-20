//// An alarm while it is edited. Each control already holds a value the clock
//// accepts; what remains is whether they agree with each other.

import gleam/list
import gleam/set.{type Set}
import gleam/string
import robine/alarm.{
  type Afterwards, type Alarm, type Ramp, type Settings, Light, Settings, Volume,
}
import robine/calendar.{type Time, type Weekday}
import robine/id.{type Id}
import robine/level.{type Percent}
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
    /// A dawn on the strip over the ramp.
    dawn: Bool,
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
}

pub fn new(sounds: List(Sound), timezone: String) -> Draft {
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
    dawn: alarm.default_light().dawn,
    afterwards: alarm.default_light().afterwards,
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
    dawn: light.dawn,
    afterwards: light.afterwards,
  )
}

pub fn editing(draft: Draft) -> Bool {
  draft.origin != New
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
  case label, days, rise {
    _, Ok(days), Ok(rise) if label != "" ->
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
        light: Light(dawn: draft.dawn, afterwards: draft.afterwards),
      ))
    _, _, _ ->
      [
        #(label == "", NoLabel),
        #(days == Error(Nil), NoDay),
        #(rise == Error(Nil), StartAboveCeiling),
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
  }
}
