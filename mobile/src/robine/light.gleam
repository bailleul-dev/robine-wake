//// The programs the clock's LED strip plays on its own: a dawn, a sunset,
//// or nothing. A breathing session also plays the ambience: it is a
//// `breathing.start` command, at a cadence of this module.

import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string

pub type Program {
  Dawn(Length)
  Sunset(Length)
  Off
}

/// How long a program lasts, from 1 to 120 minutes. A breathing session
/// finishes its last breath, then the strip goes dark.
pub opaque type Length {
  Length(minutes: Int)
}

pub fn length(minutes: Int) -> Length {
  Length(int.clamp(minutes, 1, 120))
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

/// The body of `light.program`.
pub fn encode(program: Program) -> Json {
  case program {
    Dawn(length) -> timed("dawn", length)
    Sunset(length) -> timed("sunset", length)
    Off -> json.object([#("program", json.string("off"))])
  }
}

fn timed(program: String, length: Length) -> Json {
  json.object([
    #("program", json.string(program)),
    #("duration_ms", json.int(length.minutes * 60_000)),
  ])
}
