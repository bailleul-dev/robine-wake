//// Levels the clock bounds: volumes.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import robine/decoding

/// From 0 to 100.
pub opaque type Percent {
  Percent(Int)
}

/// The nearest percentage: sliders and steppers never fail.
pub fn percent(value: Int) -> Percent {
  Percent(int.clamp(value, 0, 100))
}

pub fn percent_from_int(value: Int) -> Result(Percent, Nil) {
  case value >= 0 && value <= 100 {
    True -> Ok(Percent(value))
    False -> Error(Nil)
  }
}

pub fn percent_to_int(percent: Percent) -> Int {
  let Percent(value) = percent
  value
}

pub fn percent_decoder() -> Decoder(Percent) {
  use value <- decode.then(decoding.number())
  case percent_from_int(value) {
    Ok(percent) -> decode.success(percent)
    Error(Nil) -> decode.failure(Percent(0), "Percent")
  }
}

/// Two levels, the second at least the first: a sound that rises.
pub opaque type Rise(level) {
  Rise(from: level, to: level)
}

pub fn percent_rise(from: Percent, to: Percent) -> Result(Rise(Percent), Nil) {
  rise(from, to, percent_to_int)
}

fn rise(from: a, to: a, as_int: fn(a) -> Int) -> Result(Rise(a), Nil) {
  case as_int(from) <= as_int(to) {
    True -> Ok(Rise(from:, to:))
    False -> Error(Nil)
  }
}

pub fn from(rise: Rise(a)) -> a {
  rise.from
}

pub fn to(rise: Rise(a)) -> a {
  rise.to
}
