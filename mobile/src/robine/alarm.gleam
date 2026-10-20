//// An alarm as the clock keeps it: what the user chose, and when it rings.
//// Every value here is one the clock accepts.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/time/timestamp.{type Timestamp}
import robine/calendar.{type Days, type Time}
import robine/decoding.{defaulted, number, optional}
import robine/hue.{type HueTarget}
import robine/id.{type Id}
import robine/level.{type Brightness, type Percent, type Rise}
import robine/sound.{type Sound}

pub type Alarm {
  Alarm(
    id: Id(Alarm),
    revision: Int,
    settings: Settings,
    /// The next times it rings; none when disabled.
    next_rings: List(Timestamp),
  )
}

/// Everything the editor changes.
pub type Settings {
  Settings(
    label: String,
    enabled: Bool,
    time: Time,
    days: Days,
    timezone: String,
    sound: Id(Sound),
    strong_sound: Id(Sound),
    /// How long the sound rises before `time`.
    ramp: Ramp,
    volume: Volume,
    light: Light,
  )
}

/// The sound rises over the ramp, then the strong sound plays at `strong`.
pub type Volume {
  Volume(rise: Rise(Percent), strong: Percent)
}

/// A rise of up to an hour.
pub opaque type Ramp {
  Ramp(seconds: Int)
}

/// A Philips Hue sunrise. Its settings are kept while it is off.
pub type Light {
  Light(
    switch: Switch,
    glow: Rise(Brightness),
    ramp: Ramp,
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
  Target(id: Id(HueTarget), name: Option(String))
}

/// What the light does once the alarm is stopped.
pub type Afterwards {
  Restore
  TurnOff
  Leave
}

/// The nearest ramp to these minutes.
pub fn ramp(minutes: Int) -> Ramp {
  Ramp(60 * int.clamp(minutes, 0, 60))
}

pub fn ramp_from_seconds(seconds: Int) -> Result(Ramp, Nil) {
  case seconds >= 0 && seconds <= 3600 {
    True -> Ok(Ramp(seconds))
    False -> Error(Nil)
  }
}

pub fn ramp_minutes(ramp: Ramp) -> Int {
  { ramp.seconds + 30 } / 60
}

pub fn time_label(alarm: Alarm) -> String {
  calendar.time_to_string(alarm.settings.time)
}

pub fn days_label(alarm: Alarm) -> String {
  calendar.days_label(alarm.settings.days)
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
  |> list.filter(fn(alarm) { alarm.settings.enabled })
  |> list.sort(fn(left, right) {
    case left.next_rings, right.next_rings {
      [left, ..], [right, ..] -> timestamp.compare(left, right)
      [_, ..], [] -> order.Lt
      [], [_, ..] -> order.Gt
      [], [] -> calendar.compare_times(left.settings.time, right.settings.time)
    }
  })
  |> list.first
  |> option.from_result
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
  let percent = fn(value) { json.int(level.percent_to_int(value)) }
  json.object(
    list.flatten([
      [
        #("label", json.string(settings.label)),
        #("enabled", json.bool(settings.enabled)),
        #("local_time", json.string(calendar.time_to_string(settings.time))),
        #(
          "days_of_week",
          json.array(calendar.day_list(settings.days), fn(day) {
            json.int(calendar.number(day))
          }),
        ),
        #("timezone", json.string(settings.timezone)),
        #("sound_id", json.string(id.to_string(settings.sound))),
        #("strong_sound_id", json.string(id.to_string(settings.strong_sound))),
        #("prewake_seconds", json.int(settings.ramp.seconds)),
        #(
          "volume_profile",
          json.object([
            #("start", percent(level.from(settings.volume.rise))),
            #("ceiling", percent(level.to(settings.volume.rise))),
            #("strong", percent(settings.volume.strong)),
            #("ramp_seconds", json.int(settings.ramp.seconds)),
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
  let brightness = fn(value) { json.int(level.brightness_to_int(value)) }
  json.object(
    list.flatten([
      [
        #("enabled", json.bool(enabled)),
        #("start_brightness", brightness(level.from(light.glow))),
        #("end_brightness", brightness(level.to(light.glow))),
        #("ramp_seconds", json.int(light.ramp.seconds)),
        #("end_behavior", json.string(afterwards_code(light.afterwards))),
      ],
      case target {
        Some(Target(id: target_id, name:)) -> [
          #("target_id", json.string(id.to_string(target_id))),
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

/// What the clock lists as alarms: the user's alarms, and one-off ones, which
/// are naps.
pub type Entry {
  Recurring(Alarm)
  OneShot(enabled: Bool, next_rings: List(Timestamp))
}

pub fn entry_decoder() -> Decoder(Entry) {
  use date <- optional("one_shot_date", decode.string)
  case date {
    Some(_) -> {
      use enabled <- defaulted("enabled", False, decode.bool)
      use next_rings <- next_rings_decoder()
      decode.success(OneShot(enabled:, next_rings:))
    }
    None -> decode.map(decoder(), Recurring)
  }
}

fn next_rings_decoder(next: fn(List(Timestamp)) -> Decoder(a)) -> Decoder(a) {
  use rings <- defaulted("next_occurrences", [], decode.list(decode.string))
  next(list.filter_map(rings, calendar.parse_instant))
}

/// Defaults are the clock's own, for fields older firmware leaves out.
pub fn decoder() -> Decoder(Alarm) {
  use alarm_id <- decode.field("id", id.decoder())
  use revision <- defaulted("revision", 1, number())
  use label <- defaulted("label", "", decode.string)
  use enabled <- defaulted("enabled", False, decode.bool)
  use time <- defaulted("local_time", "07:00", decode.string)
  use time <- decoding.require(calendar.parse_time(time), "Time", noon())
  use numbers <- defaulted("days_of_week", [], decode.list(number()))
  let days =
    numbers
    |> list.try_map(calendar.from_number)
    |> result.try(calendar.days)
  use days <- decoding.require(days, "Days", calendar.every_day())
  use timezone <- defaulted("timezone", "Europe/Paris", decode.string)
  use sound <- defaulted("sound_id", sound.built_in(), id.decoder())
  use strong_sound <- defaulted(
    "strong_sound_id",
    sound.built_in(),
    id.decoder(),
  )
  use #(volume, volume_ramp) <- defaulted(
    "volume_profile",
    #(default_volume(), Ramp(1200)),
    volume_decoder(),
  )
  use ramp <- defaulted("prewake_seconds", volume_ramp, ramp_decoder())
  use light <- defaulted("light_profile", no_light(), light_decoder())
  use next_rings <- next_rings_decoder()
  decode.success(Alarm(
    id: alarm_id,
    revision:,
    settings: Settings(
      label:,
      enabled:,
      time:,
      days:,
      timezone:,
      sound:,
      strong_sound:,
      ramp:,
      volume:,
      light:,
    ),
    next_rings:,
  ))
}

fn noon() -> Time {
  let assert Ok(time) = calendar.time(12, 0)
  time
}

fn ramp_decoder() -> Decoder(Ramp) {
  use seconds <- decode.then(number())
  decoding.require(ramp_from_seconds(seconds), "Ramp", Ramp(0), decode.success)
}

pub fn default_volume() -> Volume {
  let assert Ok(rise) = level.percent_rise(level.percent(15), level.percent(85))
  Volume(rise:, strong: level.percent(85))
}

fn volume_decoder() -> Decoder(#(Volume, Ramp)) {
  use start <- defaulted("start", level.percent(15), level.percent_decoder())
  use ceiling <- defaulted(
    "ceiling",
    level.percent(85),
    level.percent_decoder(),
  )
  // Alarms saved before the strong level existed ring at the ceiling.
  use strong <- defaulted("strong", ceiling, level.percent_decoder())
  use ramp <- defaulted("ramp_seconds", Ramp(1200), ramp_decoder())
  use rise <- decoding.require(
    level.percent_rise(start, ceiling),
    "Volume",
    default_volume().rise,
  )
  decode.success(#(Volume(rise:, strong:), ramp))
}

/// The light of an alarm that never had one.
pub fn no_light() -> Light {
  let assert Ok(glow) =
    level.brightness_rise(level.brightness(1), level.brightness(70))
  Light(switch: SwitchedOff(None), glow:, ramp: Ramp(900), afterwards: Restore)
}

fn light_decoder() -> Decoder(Light) {
  use enabled <- defaulted("enabled", False, decode.bool)
  use target_id <- optional("target_id", decode.string)
  use target_name <- optional("target_name", decode.string)
  use start <- defaulted(
    "start_brightness",
    level.brightness(1),
    level.brightness_decoder(),
  )
  use end <- defaulted(
    "end_brightness",
    level.brightness(70),
    level.brightness_decoder(),
  )
  use ramp <- defaulted("ramp_seconds", Ramp(900), ramp_decoder())
  use afterwards <- defaulted("end_behavior", "restore", decode.string)
  use glow <- decoding.require(
    level.brightness_rise(start, end),
    "Glow",
    no_light().glow,
  )
  let target = case target_id {
    Some(target_id) if target_id != "" ->
      Some(Target(id: id.from_string(target_id), name: target_name))
    _ -> None
  }
  let switch = case enabled, target {
    True, Some(target) -> SwitchedOn(target)
    _, _ -> SwitchedOff(target)
  }
  decode.success(Light(
    switch:,
    glow:,
    ramp:,
    afterwards: afterwards_from_code(afterwards) |> result.unwrap(Restore),
  ))
}
