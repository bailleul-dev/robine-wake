//// An alarm as the clock keeps it: what the user chose, and when it rings.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import robine/calendar.{type Days, type Time}
import robine/decoding.{defaulted, number, optional}

pub type Alarm {
  Alarm(
    id: String,
    revision: Int,
    settings: Settings,
    /// The next times it rings, in milliseconds; none when disabled.
    next_rings: List(Int),
  )
}

/// Everything the editor changes.
pub type Settings {
  Settings(
    label: String,
    enabled: Bool,
    time: Time,
    schedule: Schedule,
    timezone: String,
    sound: String,
    strong_sound: String,
    /// How long the sound rises before `time`, in seconds.
    ramp_seconds: Int,
    volume: Volume,
    light: Light,
  )
}

pub type Schedule {
  Weekly(Days)
  /// A single day, as `YYYY-MM-DD`: the nap.
  Once(date: String)
}

/// Percentages: the sound rises from `start` to `ceiling`, then the strong
/// sound plays at `strong`.
pub type Volume {
  Volume(start: Int, ceiling: Int, strong: Int)
}

/// A Philips Hue sunrise. Its settings are kept while it is off.
pub type Light {
  Light(
    switch: Switch,
    start_brightness: Int,
    end_brightness: Int,
    ramp_seconds: Int,
    afterwards: Afterwards,
  )
}

pub type Switch {
  /// Remembers the room or zone it lit last.
  SwitchedOff(last: Option(Target))
  SwitchedOn(Target)
}

/// A Hue room or zone; the clock may not know its name.
pub type Target {
  Target(id: String, name: Option(String))
}

/// What the light does once the alarm is stopped.
pub type Afterwards {
  Restore
  TurnOff
  Leave
}

pub const nap_id = "nap"

pub const nap_maximum_ramp_minutes = 2

pub fn is_nap(alarm: Alarm) -> Bool {
  alarm.id == nap_id
}

pub fn label(alarm: Alarm) -> String {
  alarm.settings.label
}

pub fn enabled(alarm: Alarm) -> Bool {
  alarm.settings.enabled
}

pub fn time_label(alarm: Alarm) -> String {
  calendar.time_to_string(alarm.settings.time)
}

pub fn schedule_label(schedule: Schedule) -> String {
  case schedule {
    Weekly(days) -> calendar.days_label(days)
    Once(_) -> "Une fois"
  }
}

/// The alarms the user manages, the nap aside.
pub fn regular(alarms: List(Alarm)) -> List(Alarm) {
  list.filter(alarms, fn(alarm) { !is_nap(alarm) })
}

/// Alarms in the order of their time of day.
pub fn by_time(alarms: List(Alarm)) -> List(Alarm) {
  list.sort(alarms, fn(left, right) {
    calendar.compare_times(left.settings.time, right.settings.time)
  })
}

/// The enabled alarm that rings first.
pub fn next(alarms: List(Alarm)) -> Option(Alarm) {
  alarms
  |> list.filter(enabled)
  |> list.sort(fn(left, right) {
    case left.next_rings, right.next_rings {
      [left, ..], [right, ..] -> int.compare(left, right)
      [_, ..], [] -> order.Lt
      [], [_, ..] -> order.Gt
      [], [] -> calendar.compare_times(left.settings.time, right.settings.time)
    }
  })
  |> list.first
  |> option.from_result
}

/// When the nap in progress rings, if there is one.
pub fn pending_nap(alarms: List(Alarm), now: Int) -> Option(Int) {
  case list.find(alarms, fn(alarm) { is_nap(alarm) && enabled(alarm) }) {
    Ok(Alarm(next_rings: [ring, ..], ..)) if ring > now -> Some(ring)
    _ -> None
  }
}

pub fn target_id(target: Target) -> String {
  target.id
}

pub fn afterwards_code(afterwards: Afterwards) -> String {
  case afterwards {
    Restore -> "restore"
    TurnOff -> "off"
    Leave -> "leave"
  }
}

pub fn afterwards_from_code(code: String) -> Result(Afterwards, Nil) {
  case code {
    "restore" -> Ok(Restore)
    "off" -> Ok(TurnOff)
    "leave" -> Ok(Leave)
    _ -> Error(Nil)
  }
}

pub fn afterwards_label(afterwards: Afterwards) -> String {
  case afterwards {
    Restore -> "Après l’arrêt · Restaurer"
    TurnOff -> "Après l’arrêt · Éteindre"
    Leave -> "Après l’arrêt · Laisser"
  }
}

// Encoding --------------------------------------------------------------------

/// The body the clock expects to create or update an alarm. The phone never
/// snoozes and only stops an alarm by hand.
pub fn encode(settings: Settings, revision: Option(Int)) -> Json {
  let schedule = case settings.schedule {
    Weekly(days) -> [
      #(
        "days_of_week",
        json.array(calendar.day_list(days), fn(day) {
          json.int(calendar.number(day))
        }),
      ),
    ]
    Once(date) -> [
      #("days_of_week", json.preprocessed_array([])),
      #("one_shot_date", json.string(date)),
    ]
  }
  json.object(
    list.flatten([
      [
        #("label", json.string(settings.label)),
        #("enabled", json.bool(settings.enabled)),
        #("local_time", json.string(calendar.time_to_string(settings.time))),
      ],
      schedule,
      [
        #("timezone", json.string(settings.timezone)),
        #("sound_id", json.string(settings.sound)),
        #("strong_sound_id", json.string(settings.strong_sound)),
        #("prewake_seconds", json.int(settings.ramp_seconds)),
        #(
          "volume_profile",
          json.object([
            #("start", json.int(settings.volume.start)),
            #("ceiling", json.int(settings.volume.ceiling)),
            #("strong", json.int(settings.volume.strong)),
            #("ramp_seconds", json.int(settings.ramp_seconds)),
          ]),
        ),
        #("light_profile", encode_light(settings.light)),
        #("dismiss_policy", json.string("manual")),
        #("snooze", json.object([#("enabled", json.bool(False))])),
      ],
      case revision {
        Some(revision) -> [#("revision", json.int(revision))]
        None -> []
      },
    ]),
  )
}

fn encode_light(light: Light) -> Json {
  let #(enabled, target) = case light.switch {
    SwitchedOn(target) -> #(True, Some(target))
    SwitchedOff(last) -> #(False, last)
  }
  json.object(
    list.flatten([
      [
        #("enabled", json.bool(enabled)),
        #("start_brightness", json.int(light.start_brightness)),
        #("end_brightness", json.int(light.end_brightness)),
        #("ramp_seconds", json.int(light.ramp_seconds)),
        #("end_behavior", json.string(afterwards_code(light.afterwards))),
      ],
      case target {
        Some(Target(id:, name:)) -> [
          #("target_id", json.string(id)),
          ..case name {
            Some(name) -> [#("target_name", json.string(name))]
            None -> []
          }
        ]
        None -> []
      },
    ]),
  )
}

// Decoding --------------------------------------------------------------------

/// Defaults are the clock's own, for fields older firmware leaves out.
pub fn decoder() -> Decoder(Alarm) {
  use id <- decode.field("id", decode.string)
  use revision <- defaulted("revision", 1, number())
  use label <- defaulted("label", "", decode.string)
  use enabled <- defaulted("enabled", False, decode.bool)
  use time <- defaulted("local_time", "07:00", decode.string)
  use time <- decoding.require(
    calendar.parse_time(time),
    "Time",
    default_time(),
  )
  use schedule <- schedule_decoder()
  use timezone <- defaulted("timezone", "Europe/Paris", decode.string)
  use sound <- defaulted("sound_id", "default", decode.string)
  use strong_sound <- defaulted("strong_sound_id", "default", decode.string)
  use volume <- defaulted("volume_profile", #(Volume(15, 85, 85), 1200), {
    use start <- defaulted("start", 15, number())
    use ceiling <- defaulted("ceiling", 85, number())
    use strong <- defaulted("strong", ceiling, number())
    use ramp <- defaulted("ramp_seconds", 1200, number())
    decode.success(#(Volume(start:, ceiling:, strong:), ramp))
  })
  use ramp_seconds <- defaulted("prewake_seconds", volume.1, number())
  use light <- defaulted("light_profile", no_light, light_decoder())
  use next_rings <- defaulted(
    "next_occurrences",
    [],
    decode.list(decode.string),
  )
  decode.success(Alarm(
    id:,
    revision:,
    settings: Settings(
      label:,
      enabled:,
      time:,
      schedule:,
      timezone:,
      sound:,
      strong_sound:,
      ramp_seconds:,
      volume: volume.0,
      light:,
    ),
    next_rings: list.filter_map(next_rings, calendar.parse_instant),
  ))
}

fn default_time() -> Time {
  let assert Ok(time) = calendar.time(7, 0)
  time
}

/// A date makes a one-off alarm, whatever the days say.
fn schedule_decoder(next: fn(Schedule) -> Decoder(a)) -> Decoder(a) {
  use date <- optional("one_shot_date", decode.string)
  case date {
    Some(date) -> next(Once(date))
    None -> {
      use numbers <- defaulted("days_of_week", [], decode.list(number()))
      let days =
        numbers
        |> list.try_map(calendar.from_number)
        |> result.try(calendar.days)
      use days <- decoding.require(days, "Days", calendar.every_day())
      next(Weekly(days))
    }
  }
}

pub const no_light =
  Light(
    switch: SwitchedOff(None),
    start_brightness: 1,
    end_brightness: 70,
    ramp_seconds: 900,
    afterwards: Restore,
  )

fn light_decoder() -> Decoder(Light) {
  use enabled <- defaulted("enabled", False, decode.bool)
  use target_id <- optional("target_id", decode.string)
  use target_name <- optional("target_name", decode.string)
  use start_brightness <- defaulted("start_brightness", 1, number())
  use end_brightness <- defaulted("end_brightness", 70, number())
  use ramp_seconds <- defaulted("ramp_seconds", 900, number())
  use afterwards <- defaulted("end_behavior", "restore", decode.string)
  let target = case target_id {
    Some(id) if id != "" -> Some(Target(id:, name: target_name))
    _ -> None
  }
  let switch = case enabled, target {
    True, Some(target) -> SwitchedOn(target)
    _, _ -> SwitchedOff(target)
  }
  decode.success(Light(
    switch:,
    start_brightness:,
    end_brightness:,
    ramp_seconds:,
    afterwards: afterwards_from_code(afterwards) |> result.unwrap(Restore),
  ))
}
