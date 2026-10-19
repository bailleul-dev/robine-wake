//// Alarm schedules, drafts and the wake-up challenges, without any I/O.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleam/string
import gleam/time/timestamp
import robine/types.{
  type Alarm, type AlarmDraft, type HueTarget, type Sound, AlarmDraft,
}

pub type Weekday {
  Weekday(id: Int, short: String, name: String)
}

pub const weekdays = [
  Weekday(1, "L", "Lundi"),
  Weekday(2, "M", "Mardi"),
  Weekday(3, "M", "Mercredi"),
  Weekday(4, "J", "Jeudi"),
  Weekday(5, "V", "Vendredi"),
  Weekday(6, "S", "Samedi"),
  Weekday(7, "D", "Dimanche"),
]

pub const nap_alarm_id = "nap"

pub const nap_maximum_ramp_minutes = 2

/// `[0, 1, …, count - 1]`.
pub fn indices(count: Int) -> List(Int) {
  int.range(from: count - 1, to: -1, with: [], run: list.prepend)
}

pub fn two_digits(value: Int) -> String {
  string.pad_start(int.to_string(value), 2, "0")
}

pub fn local_time(hour: Int, minute: Int) -> String {
  two_digits(hour) <> ":" <> two_digits(minute)
}

/// `HH:MM` of a `HH:MM[:SS]` time.
pub fn short_time(local_time: String) -> String {
  string.slice(local_time, 0, 5)
}

pub fn schedule_label(days_of_week: List(Int)) -> String {
  let days = set.from_list(days_of_week)
  let same = fn(expected) { days == set.from_list(expected) }
  case same([1, 2, 3, 4, 5]), same([6, 7]), same([1, 2, 3, 4, 5, 6, 7]) {
    True, _, _ -> "En semaine"
    _, True, _ -> "Le week-end"
    _, _, True -> "Tous les jours"
    _, _, _ ->
      weekdays
      |> list.filter(fn(day) { set.contains(days, day.id) })
      |> list.map(fn(day) { day.short })
      |> string.join(" · ")
  }
}

pub fn regular_alarms(alarms: List(Alarm)) -> List(Alarm) {
  list.filter(alarms, fn(alarm) { alarm.id != nap_alarm_id })
}

/// Milliseconds since the Unix epoch of an RFC 3339 date.
pub fn parse_time(value: String) -> Option(Int) {
  case timestamp.parse_rfc3339(value) {
    Ok(parsed) -> {
      let #(seconds, nanoseconds) =
        timestamp.to_unix_seconds_and_nanoseconds(parsed)
      Some(seconds * 1000 + nanoseconds / 1_000_000)
    }
    Error(Nil) -> None
  }
}

/// Wake time of the nap in progress, if any, in milliseconds.
pub fn pending_nap_wake_time(alarms: List(Alarm), now: Int) -> Option(Int) {
  let nap =
    list.find(alarms, fn(alarm) { alarm.id == nap_alarm_id && alarm.enabled })
  case nap {
    Ok(types.Alarm(next_occurrences: [next, ..], ..)) ->
      case parse_time(next) {
        Some(wake) if wake > now -> Some(wake)
        _ -> None
      }
    _ -> None
  }
}

/// The enabled alarm that rings first.
pub fn next_alarm(alarms: List(Alarm)) -> Option(Alarm) {
  let key = fn(alarm: Alarm) {
    case alarm.next_occurrences {
      [next, ..] -> next
      [] -> alarm.local_time
    }
  }
  alarms
  |> list.filter(fn(alarm) { alarm.enabled })
  |> list.sort(fn(left, right) { string.compare(key(left), key(right)) })
  |> list.first
  |> option.from_result
}

/// Alarms in the order of their time of day.
pub fn sort_alarms(alarms: List(Alarm)) -> List(Alarm) {
  list.sort(alarms, fn(left, right) {
    string.compare(left.local_time, right.local_time)
  })
}

/// Seconds the progressive ramp starts before the alarm.
pub fn ramp_seconds(alarm: Alarm) -> Int {
  alarm.prewake_seconds
  |> option.lazy_or(fn() { alarm.volume_profile.ramp_seconds })
  |> option.unwrap(0)
}

fn default_sound(sounds: List(Sound), intensity: String) -> String {
  case list.find(sounds, fn(sound) { sound.intensity == Some(intensity) }) {
    Ok(sound) -> sound.id
    Error(Nil) ->
      case sounds {
        [first, ..] -> first.id
        [] -> "default"
      }
  }
}

fn parse_hour_minute(local_time: String) -> #(Int, Int) {
  case string.split(local_time, ":") {
    [hour, minute, ..] -> #(
      int.parse(hour) |> result_or(7),
      int.parse(minute) |> result_or(0),
    )
    _ -> #(7, 0)
  }
}

fn result_or(result: Result(a, b), default: a) -> a {
  case result {
    Ok(value) -> value
    Error(_) -> default
  }
}

fn minutes_of(seconds: Int) -> Int {
  int.max(1, seconds / 60)
}

/// The draft for an existing alarm, or for a new one when `alarm` is `None`.
pub fn alarm_to_draft(
  alarm: Option(Alarm),
  sounds: List(Sound),
  timezone: String,
) -> AlarmDraft {
  case alarm {
    None ->
      AlarmDraft(
        id: None,
        label: "Mon réveil",
        enabled: True,
        hour: 7,
        minute: 0,
        days: set.from_list([1, 2, 3, 4, 5]),
        timezone:,
        sound_id: default_sound(sounds, "gentle"),
        strong_sound_id: default_sound(sounds, "strong"),
        start_volume: 15,
        ceiling_volume: 85,
        strong_volume: 85,
        prewake_minutes: 20,
        revision: None,
        light_enabled: False,
        light_target_id: None,
        light_target_name: None,
        light_start_brightness: 1,
        light_end_brightness: 70,
        light_ramp_minutes: 15,
        light_end_behavior: "restore",
      )
    Some(alarm) -> {
      let #(hour, minute) = parse_hour_minute(alarm.local_time)
      let volume = alarm.volume_profile
      let light = alarm.light_profile
      let ceiling = option.unwrap(volume.ceiling, 85)
      AlarmDraft(
        id: Some(alarm.id),
        label: alarm.label,
        enabled: alarm.enabled,
        hour:,
        minute:,
        days: set.from_list(alarm.days_of_week),
        timezone: alarm.timezone,
        sound_id: alarm.sound_id,
        strong_sound_id: alarm.strong_sound_id,
        start_volume: option.unwrap(volume.start, 15),
        ceiling_volume: ceiling,
        strong_volume: option.unwrap(volume.strong, ceiling),
        prewake_minutes: alarm.prewake_seconds
          |> option.lazy_or(fn() { volume.ramp_seconds })
          |> option.unwrap(1200)
          |> minutes_of,
        revision: alarm.revision,
        light_enabled: light.enabled,
        light_target_id: light.target_id,
        light_target_name: light.target_name,
        light_start_brightness: option.unwrap(light.start_brightness, 1),
        light_end_brightness: option.unwrap(light.end_brightness, 70),
        light_ramp_minutes: light.ramp_seconds
          |> option.unwrap(900)
          |> minutes_of,
        light_end_behavior: option.unwrap(light.end_behavior, "restore"),
      )
    }
  }
}

/// A new alarm, lit by the first Hue target when there is one.
pub fn new_draft(
  sounds: List(Sound),
  targets: List(HueTarget),
  timezone: String,
) -> AlarmDraft {
  let draft = alarm_to_draft(None, sounds, timezone)
  case targets {
    [first, ..] ->
      AlarmDraft(
        ..draft,
        light_enabled: True,
        light_target_id: Some(first.id),
        light_target_name: Some(first.name),
      )
    [] -> draft
  }
}

pub fn draft_valid(draft: AlarmDraft) -> Bool {
  string.trim(draft.label) != ""
  && set.size(draft.days) > 0
  && draft.start_volume <= draft.ceiling_volume
  && string.trim(draft.sound_id) != ""
  && string.trim(draft.strong_sound_id) != ""
  && { !draft.light_enabled || option.is_some(draft.light_target_id) }
}

fn optional_entry(
  key: String,
  value: Option(a),
  encode: fn(a) -> Json,
) -> List(#(String, Json)) {
  case value {
    Some(value) -> [#(key, encode(value))]
    None -> []
  }
}

pub fn draft_to_payload(draft: AlarmDraft) -> Json {
  let ramp = 60 * draft.prewake_minutes
  json.object(
    list.flatten([
      [
        #("label", json.string(string.trim(draft.label))),
        #("enabled", json.bool(draft.enabled)),
        #("local_time", json.string(local_time(draft.hour, draft.minute))),
        #(
          "days_of_week",
          json.array(
            draft.days |> set.to_list |> list.sort(int.compare),
            json.int,
          ),
        ),
        #("timezone", json.string(draft.timezone)),
        #("sound_id", json.string(draft.sound_id)),
        #("strong_sound_id", json.string(draft.strong_sound_id)),
        #("prewake_seconds", json.int(ramp)),
        #(
          "volume_profile",
          json.object([
            #("start", json.int(draft.start_volume)),
            #("ceiling", json.int(draft.ceiling_volume)),
            #("strong", json.int(draft.strong_volume)),
            #("ramp_seconds", json.int(ramp)),
          ]),
        ),
        #(
          "light_profile",
          json.object(
            list.flatten([
              [
                #("enabled", json.bool(draft.light_enabled)),
                #("start_brightness", json.int(draft.light_start_brightness)),
                #("end_brightness", json.int(draft.light_end_brightness)),
                #("ramp_seconds", json.int(60 * draft.light_ramp_minutes)),
                #("end_behavior", json.string(draft.light_end_behavior)),
              ],
              optional_entry("target_id", draft.light_target_id, json.string),
              optional_entry(
                "target_name",
                draft.light_target_name,
                json.string,
              ),
            ]),
          ),
        ),
        #("dismiss_policy", json.string("manual")),
        #("snooze", json.object([#("enabled", json.bool(False))])),
      ],
      optional_entry("revision", draft.revision, json.int),
    ]),
  )
}

// Wake-up challenge -----------------------------------------------------------

pub type ChallengeKind {
  Calculation
  Sequence
  Attention
}

pub type Challenge {
  Challenge(
    kind: ChallengeKind,
    prompt: String,
    instruction: String,
    answer: Int,
    options: List(Int),
  )
}

pub fn kind_label(kind: ChallengeKind) -> String {
  case kind {
    Calculation -> "Calcul"
    Sequence -> "Suite logique"
    Attention -> "Attention"
  }
}

/// Four distinct choices around the answer, including it.
fn choices_around(answer: Int) -> List(Int) {
  [-8, -6, -5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 6, 8]
  |> list.shuffle
  |> list.take(3)
  |> list.map(fn(offset) { answer + offset })
  |> list.prepend(answer)
  |> list.shuffle
}

pub fn make_challenge(step: Int) -> Challenge {
  case step % 3 {
    0 -> {
      let left = 14 + int.random(25)
      let right = 6 + int.random(19)
      let subtract = int.random(2) == 0
      let answer = case subtract {
        True -> left - right
        False -> left + right
      }
      let operator = case subtract {
        True -> " − "
        False -> " + "
      }
      Challenge(
        kind: Calculation,
        prompt: int.to_string(left)
          <> operator
          <> int.to_string(right)
          <> " = ?",
        instruction: "Choisissez le résultat",
        answer:,
        options: choices_around(answer),
      )
    }
    1 -> {
      let start = 2 + int.random(11)
      let increment = 2 + int.random(6)
      let values =
        indices(4)
        |> list.map(fn(index) { int.to_string(start + index * increment) })
      let answer = start + 4 * increment
      Challenge(
        kind: Sequence,
        prompt: string.join(values, "  ·  ") <> "  ·  ?",
        instruction: "Quel nombre vient ensuite ?",
        answer:,
        options: choices_around(answer),
      )
    }
    _ -> {
      let target = 3 + int.random(6)
      let amount = 2 + int.random(3)
      let other =
        list.repeat(Nil, 7 - amount)
        |> list.map(fn(_) { other_digit(target) })
      let digits = list.shuffle(list.append(list.repeat(target, amount), other))
      Challenge(
        kind: Attention,
        prompt: digits |> list.map(int.to_string) |> string.join("  "),
        instruction: "Combien de fois voyez-vous le chiffre "
          <> int.to_string(target)
          <> " ?",
        answer: amount,
        options: list.shuffle([1, 2, 3, 4]),
      )
    }
  }
}

fn other_digit(target: Int) -> Int {
  let digit = 1 + int.random(9)
  case digit == target {
    True -> other_digit(target)
    False -> digit
  }
}
