//// The nap: a one-off alarm a chosen number of minutes from now.

import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/time/timestamp.{type Timestamp}

/// A nap the clock will ring.
pub type Nap {
  Nap(rings_at: Timestamp)
}

/// How long a nap lasts, from 1 to 180 minutes.
pub opaque type Length {
  Length(minutes: Int)
}

pub fn length(minutes: Int) -> Length {
  Length(int.clamp(minutes, 1, 180))
}

pub fn minutes(length: Length) -> Int {
  length.minutes
}

/// The sound rises during the last two minutes, or the whole nap if shorter.
pub fn ramp_minutes(length: Length) -> Int {
  int.min(2, length.minutes)
}

/// When the nap rings, unless that time is past.
pub fn pending(nap: Option(Nap), now: Timestamp) -> Option(Timestamp) {
  case nap {
    Some(Nap(rings_at:)) ->
      case timestamp.compare(rings_at, now) {
        order.Gt -> Some(rings_at)
        _ -> None
      }
    None -> None
  }
}
