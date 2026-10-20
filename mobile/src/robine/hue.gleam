//// Philips Hue: the bridge, its rooms and zones, and the evening breathing
//// session the light leads.

import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import robine/calendar
import robine/decoding.{defaulted, number, optional}
import robine/id.{type Id}
import robine/level.{type Percent}

pub type Hue {
  Unpaired
  Paired(bridge: String, reachable: Bool, target_count: Int)
}

/// A room or zone the bridge lights.
pub type HueTarget {
  HueTarget(id: Id(HueTarget), name: String)
}

pub type Breathing {
  Resting
  Guided(
    phase: Phase,
    phase_length: Duration,
    clock: PhaseClock,
    remaining: Option(Duration),
    target: Option(Id(HueTarget)),
    ambience: Bool,
    volume: Option(Percent),
  )
}

pub type Phase {
  Inhale
  Exhale
}

/// How far into its phase the session is: older firmware only tells how long
/// it has been, newer firmware when the phase started.
pub type PhaseClock {
  StartedAt(Timestamp)
  Elapsed(Duration)
}

/// How long a session lasts: the clock offers a few lengths only.
pub opaque type BreathingLength {
  BreathingLength(minutes: Int)
}

pub fn breathing_lengths() -> List(BreathingLength) {
  list.map([3, 5, 10, 15, 20, 30], BreathingLength)
}

pub fn default_breathing_length() -> BreathingLength {
  BreathingLength(10)
}

pub fn breathing_minutes(length: BreathingLength) -> Int {
  length.minutes
}

pub fn is_paired(hue: Hue) -> Bool {
  case hue {
    Paired(..) -> True
    Unpaired -> False
  }
}

pub fn is_ready(hue: Hue) -> Bool {
  case hue {
    Paired(reachable: True, ..) -> True
    _ -> False
  }
}

/// How much of the phase in progress is done, from 0 to 1.
pub fn phase_progress(breathing: Breathing, now: Timestamp) -> Float {
  case breathing {
    Resting -> 0.0
    Guided(phase_length:, clock:, ..) -> {
      let elapsed = case clock {
        StartedAt(started) -> timestamp.difference(started, now)
        Elapsed(elapsed) -> elapsed
      }
      case duration.compare(elapsed, duration.seconds(0)) {
        order.Lt -> 0.0
        _ ->
          float.min(
            1.0,
            duration.to_seconds(elapsed) /. duration.to_seconds(phase_length),
          )
      }
    }
  }
}

// Decoding --------------------------------------------------------------------

pub fn target_decoder() -> Decoder(HueTarget) {
  use target_id <- decode.field("id", decode.string)
  use name <- defaulted("name", target_id, decode.string)
  decode.success(HueTarget(id: id.from_string(target_id), name:))
}

/// The `hue` part of a `state.get` response.
pub fn decoder() -> Decoder(#(Hue, Breathing)) {
  use configured <- defaulted("configured", False, decode.bool)
  use state <- optional("state", decode.string)
  use bridge <- defaulted("bridge_host", "", decode.string)
  use target_count <- defaulted("target_count", 0, number())
  use breathing <- defaulted("breathing", Resting, breathing_decoder())
  let hue = case configured {
    True ->
      Paired(bridge:, reachable: state == Some("available"), target_count:)
    False -> Unpaired
  }
  decode.success(#(hue, breathing))
}

fn breathing_decoder() -> Decoder(Breathing) {
  use active <- defaulted("active", False, decode.bool)
  case active {
    False -> decode.success(Resting)
    True -> {
      use phase <- defaulted("phase", "inhale", decode.string)
      let phase = case phase {
        "exhale" -> Exhale
        _ -> Inhale
      }
      let usual_ms = case phase {
        Inhale -> 4000
        Exhale -> 6000
      }
      use phase_ms <- defaulted("phase_duration_ms", usual_ms, number())
      use started_at <- optional("phase_started_at", decode.string)
      use elapsed_ms <- defaulted("phase_elapsed_ms", 0, number())
      use remaining_seconds <- optional("remaining_seconds", number())
      use target <- optional("target_id", id.decoder())
      use #(ambience, volume) <- defaulted("audio", #(False, None), {
        use active <- defaulted("active", False, decode.bool)
        use volume <- optional("volume_percent", number())
        decode.success(#(active, option.map(volume, level.percent)))
      })
      let clock = case
        option.then(started_at, fn(text) {
          calendar.parse_instant(text) |> option.from_result
        })
      {
        Some(started) -> StartedAt(started)
        None -> Elapsed(duration.milliseconds(elapsed_ms))
      }
      decode.success(Guided(
        phase:,
        phase_length: duration.milliseconds(int.max(1, phase_ms)),
        clock:,
        remaining: option.map(remaining_seconds, duration.seconds),
        target:,
        ambience:,
        volume:,
      ))
    }
  }
}
