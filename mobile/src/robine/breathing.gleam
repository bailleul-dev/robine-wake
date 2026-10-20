//// The evening breathing session: the clock's LED strip breathes at a
//// cadence while the speaker plays the meditation ambience.

import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import robine/calendar
import robine/decoding.{defaulted, number, optional}
import robine/level.{type Percent}

pub type Breathing {
  Resting
  Guided(
    cadence: String,
    breath: Breath,
    /// When the first breath began, on the clock.
    started: Timestamp,
    /// When the last breath ends.
    ends: Option(Timestamp),
    volume: Percent,
    /// Whether the ambience plays, and the strip answers.
    ambience: Bool,
    strip: Bool,
  )
}

/// Phase durations of one breath, in milliseconds.
pub type Breath {
  Breath(hold_empty: Int, inhale: Int, hold_full: Int, exhale: Int)
}

pub type Phase {
  HoldEmpty
  Inhale
  HoldFull
  Exhale
}

/// The phase `elapsed_ms` into a session, how much of it is done (0 to 1),
/// and how full the lungs are (0 to 1).
pub fn phase_at(breath: Breath, elapsed_ms: Int) -> #(Phase, Float, Float) {
  let length =
    breath.hold_empty + breath.inhale + breath.hold_full + breath.exhale
  let t = int.max(elapsed_ms, 0) % int.max(length, 1)
  let share = fn(t, of) { int.to_float(t) /. int.to_float(int.max(of, 1)) }
  case t {
    t if t < breath.hold_empty -> #(HoldEmpty, share(t, breath.hold_empty), 0.0)
    t if t < breath.hold_empty + breath.inhale -> {
      let done = share(t - breath.hold_empty, breath.inhale)
      #(Inhale, done, done)
    }
    t if t < breath.hold_empty + breath.inhale + breath.hold_full -> #(
      HoldFull,
      share(t - breath.hold_empty - breath.inhale, breath.hold_full),
      1.0,
    )
    t -> {
      let done =
        share(
          t - breath.hold_empty - breath.inhale - breath.hold_full,
          breath.exhale,
        )
      #(Exhale, done, 1.0 -. done)
    }
  }
}

/// How long the phase in progress lasts.
pub fn phase_ms(breath: Breath, phase: Phase) -> Int {
  case phase {
    HoldEmpty -> breath.hold_empty
    Inhale -> breath.inhale
    HoldFull -> breath.hold_full
    Exhale -> breath.exhale
  }
}

pub fn elapsed_ms(started: Timestamp, now: Timestamp) -> Int {
  timestamp.difference(started, now)
  |> duration.to_seconds
  |> float.multiply(1000.0)
  |> float.round
}

// Decoding --------------------------------------------------------------------

/// The `breathing` part of a `state.get` response.
pub fn decoder() -> Decoder(Breathing) {
  use active <- defaulted("active", False, decode.bool)
  case active {
    False -> decode.success(Resting)
    True -> {
      use cadence <- defaulted("cadence", "", decode.string)
      use hold_empty <- defaulted("hold_empty_ms", 0, number())
      use inhale <- defaulted("inhale_ms", 4000, number())
      use hold_full <- defaulted("hold_full_ms", 0, number())
      use exhale <- defaulted("exhale_ms", 6000, number())
      use started_at <- optional("started_at", decode.string)
      use server_time <- optional("server_time", decode.string)
      use remaining <- optional("remaining_seconds", number())
      use volume <- defaulted(
        "volume_percent",
        level.percent(60),
        level.percent_decoder(),
      )
      use ambience <- defaulted("audio", False, active_decoder())
      use strip <- defaulted("light", False, active_decoder())
      let instant = fn(text) {
        option.then(text, fn(text) {
          calendar.parse_instant(text) |> option.from_result
        })
      }
      case instant(started_at) {
        None -> decode.success(Resting)
        Some(started) ->
          decode.success(Guided(
            cadence:,
            breath: Breath(hold_empty:, inhale:, hold_full:, exhale:),
            started:,
            ends: case instant(server_time), remaining {
              Some(at), Some(seconds) ->
                Some(timestamp.add(at, duration.seconds(seconds)))
              _, _ -> None
            },
            volume:,
            ambience:,
            strip:,
          ))
      }
    }
  }
}

fn active_decoder() -> Decoder(Bool) {
  use active <- defaulted("active", False, decode.bool)
  decode.success(active)
}
