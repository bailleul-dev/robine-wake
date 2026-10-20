//// The programs the clock's LED strip plays on its own: a dawn, a sunset,
//// a reading light, or nothing. A breathing session also plays the ambience: it is a
//// `breathing.start` command, at a cadence of this module.

import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import robine/decoding.{defaulted, number, optional}
import robine/id.{type Id}
import robine/level.{type Percent}
import robine/sound.{type Sound}

pub type Program {
  Dawn(Length)
  Sunset(Length)
  /// Warm amber low on the strip, red high, then a sunset, or dark at once.
  ReadingLight(Length, sunset: Option(Length))
  Off
}

/// How long a program lasts, from 1 minute to 4 hours. A breathing session
/// finishes its last breath, then the strip goes dark.
pub opaque type Length {
  Length(minutes: Int)
}

pub fn length(minutes: Int) -> Length {
  Length(int.clamp(minutes, 1, 240))
}

pub fn minutes(length: Length) -> Int {
  length.minutes
}

/// One breath, written `hold empty-inhale-hold full-exhale` in seconds, as
/// the clock reads it: `0-4-0-6` for cardiac coherence.
pub opaque type Cadence {
  Cadence(text: String)
}

pub const coherence = "0-4-0-6"

/// Breathing patterns offered by name, as cadences.
pub const patterns = [
  #("0-4-0-6", "Détente · inspirez 4 s, expirez 6 s"),
  #("0-5-0-5", "Cohérence cardiaque · 5 s, 5 s"),
  #("4-4-4-4", "Respiration carrée · 4 temps de 4 s"),
  #("0-4-7-8", "4-7-8 · inspirez 4, retenez 7, expirez 8"),
  #("0-4-4-4", "Triangle · inspirez, retenez, expirez 4 s"),
  #("0-4-0-8", "Endormissement · expiration longue de 8 s"),
]

/// Four phases from 0 to 60 s (decimals allowed), with an inhale and an
/// exhale.
pub fn cadence(text: String) -> Result(Cadence, Nil) {
  let text = string.trim(text)
  use seconds <- result.try(
    text
    |> string.split("-")
    |> list.try_map(seconds),
  )
  case seconds {
    [_, inhale, _, exhale] if inhale >. 0.0 && exhale >. 0.0 -> Ok(Cadence(text))
    _ -> Error(Nil)
  }
}

fn seconds(part: String) -> Result(Float, Nil) {
  let part = string.trim(part)
  use value <- result.try(
    float.parse(part)
    |> result.lazy_or(fn() { int.parse(part) |> result.map(int.to_float) }),
  )
  case value >=. 0.0 && value <=. 60.0 {
    True -> Ok(value)
    False -> Error(Nil)
  }
}

pub fn cadence_text(cadence: Cadence) -> String {
  cadence.text
}

/// A sound played along a program, that falls silent with the light.
pub type Ambience {
  Ambience(sound: Id(Sound), volume: Percent)
}

/// The body of `light.program`, with the ambience to play along.
pub fn encode_with(program: Program, ambience: Option(Ambience)) -> Json {
  case program, ambience {
    Off, _ | _, None -> encode(program)
    _, Some(Ambience(sound:, volume:)) ->
      json.object(
        list.append(fields(program), [
          #(
            "ambience",
            json.object([
              #("sound_id", json.string(id.to_string(sound))),
              #("volume_percent", json.int(level.percent_to_int(volume))),
            ]),
          ),
        ]),
      )
  }
}

/// The ambience playing with the strip: `light_ambience` in `state.get`.
pub type Playing {
  Playing(sound: String, volume: Int, gain: Int, audible: Bool)
}

pub fn playing_decoder() -> Decoder(Option(Playing)) {
  use active <- defaulted("active", False, decode.bool)
  use sound <- defaulted("sound_id", "", decode.string)
  use volume <- defaulted("volume_percent", 0, number())
  use gain <- defaulted("gain_percent", 0, number())
  use audible <- defaulted("audio", False, {
    use active <- defaulted("active", False, decode.bool)
    decode.success(active)
  })
  decode.success(case active {
    True -> Some(Playing(sound:, volume:, gain:, audible:))
    False -> None
  })
}

/// The body of `light.program`.
pub fn encode(program: Program) -> Json {
  json.object(fields(program))
}

fn fields(program: Program) -> List(#(String, Json)) {
  case program {
    Dawn(length) -> timed("dawn", length)
    Sunset(length) -> timed("sunset", length)
    ReadingLight(length, sunset:) ->
      list.append(timed("reading", length), [
        #("sunset_ms", json.int(option.map(sunset, ms) |> option.unwrap(0))),
      ])
    Off -> [#("program", json.string("off"))]
  }
}

fn timed(program: String, length: Length) -> List(#(String, Json)) {
  [#("program", json.string(program)), #("duration_ms", json.int(ms(length)))]
}

fn ms(length: Length) -> Int {
  length.minutes * 60_000
}

// Reading -----------------------------------------------------------------------

/// What the strip showed when it was read (`light.get`, and the answer to
/// `light.program`).
pub type Reading {
  Reading(showing: Showing, pixels: List(String))
}

pub type Showing {
  Dark
  /// A plain colour, set by `light.set`.
  Steady
  Running(
    program: String,
    cadence: Option(String),
    elapsed_ms: Int,
    duration_ms: Int,
  )
}

pub fn reading_decoder() -> Decoder(Reading) {
  use program <- optional("program", decode.string)
  use cadence <- optional("cadence", decode.string)
  use elapsed_ms <- defaulted("elapsed_ms", 0, number())
  use duration_ms <- defaulted("duration_ms", 0, number())
  use pixels <- defaulted("pixels", "", decode.string)
  let pixels = colours(pixels, [])
  let showing = case program {
    Some(program) -> Running(program:, cadence:, elapsed_ms:, duration_ms:)
    None ->
      case list.all(pixels, fn(pixel) { pixel == "#000000" }) {
        True -> Dark
        False -> Steady
      }
  }
  decode.success(Reading(showing:, pixels:))
}

/// `rrggbb` after `rrggbb`, as CSS colours.
fn colours(hex: String, acc: List(String)) -> List(String) {
  case string.length(hex) >= 6 {
    True ->
      colours(string.drop_start(hex, 6), ["#" <> string.slice(hex, 0, 6), ..acc])
    False -> list.reverse(acc)
  }
}

pub fn describe(showing: Showing) -> String {
  case showing {
    Dark -> "Éteint"
    Steady -> "Couleur fixe"
    Running(program: "dawn", ..) -> "Lever de soleil"
    Running(program: "sunset", ..) -> "Coucher de soleil"
    Running(program: "reading", ..) -> "Lecture"
    Running(program: "breathing", cadence: Some(cadence), ..) ->
      "Respiration " <> cadence
    Running(program: "breathing", ..) -> "Respiration"
    Running(program:, ..) -> program
  }
}
