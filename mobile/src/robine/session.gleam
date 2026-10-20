//// Wake-up sessions: the one ringing now, and how the last ones ended.

import gleam/dynamic/decode.{type Decoder}
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/timestamp.{type Timestamp}
import robine/calendar
import robine/decoding.{defaulted, optional}
import robine/id.{type Id}

/// What session ids refer to.
pub type Session

/// The wake-up in progress.
pub type Active {
  Active(
    id: Id(Session),
    stage: Stage,
    phase: Phase,
    test_mode: Bool,
    /// Whether the phone may stop it once the challenge is solved.
    phone_may_dismiss: Bool,
  )
}

pub type Stage {
  Starting
  Ringing
  Snoozed
  /// The sleeper seems to have left the bed.
  LeavingBed
  /// The sound failed; the clock plays its safe fallback.
  FailedSafe
  OtherStage(String)
}

pub type Phase {
  GentlePhase
  StrongPhase
}

/// A wake-up as the history keeps it.
pub type Past {
  Past(id: Id(Session), outcome: Outcome, ended_at: Option(Timestamp))
}

pub type Outcome {
  Dismissed
  TimedOut
  Missed
  /// Kept while it was still at this stage.
  Unfinished(Stage)
}

pub fn outcome_label(outcome: Outcome) -> String {
  case outcome {
    Dismissed -> "Réveil réussi"
    TimedOut -> "Arrêt automatique"
    Missed -> "Manqué"
    Unfinished(stage) -> stage_label(stage)
  }
}

pub fn stage_label(stage: Stage) -> String {
  case stage {
    Starting -> "Démarrage"
    Ringing -> "En cours"
    Snoozed -> "En pause"
    LeavingBed -> "Sortie du lit"
    FailedSafe -> "Son de secours"
    OtherStage(other) -> string.capitalise(other)
  }
}

// Decoding --------------------------------------------------------------------

fn state(text: String) -> Result(Stage, Outcome) {
  case text {
    "starting" -> Ok(Starting)
    "ringing" -> Ok(Ringing)
    "snoozed" -> Ok(Snoozed)
    "exit_candidate" -> Ok(LeavingBed)
    "failed_safe" -> Ok(FailedSafe)
    "dismissed" -> Error(Dismissed)
    "timed_out" -> Error(TimedOut)
    "missed" -> Error(Missed)
    other -> Ok(OtherStage(other))
  }
}

/// A session reported as active but already over is not active any more.
pub fn active_decoder() -> Decoder(Option(Active)) {
  use session_id <- decode.field("id", id.decoder())
  use text <- defaulted("state", "", decode.string)
  use phase <- optional("audio_phase", decode.string)
  use test_mode <- defaulted("test_mode", False, decode.bool)
  use phone_may_dismiss <- defaulted(
    "smartphone_dismiss_allowed",
    True,
    decode.bool,
  )
  let phase = case phase {
    Some("strong") -> StrongPhase
    _ -> GentlePhase
  }
  decode.success(case state(text) {
    Ok(stage) ->
      Some(Active(
        id: session_id,
        stage:,
        phase:,
        test_mode:,
        phone_may_dismiss:,
      ))
    Error(_) -> None
  })
}

pub fn past_decoder() -> Decoder(Past) {
  use session_id <- decode.field("id", id.decoder())
  use text <- defaulted("state", "", decode.string)
  use ended_at <- optional("ended_at", decode.string)
  let outcome = case state(text) {
    Ok(stage) -> Unfinished(stage)
    Error(outcome) -> outcome
  }
  let ended_at =
    option.then(ended_at, fn(text) {
      calendar.parse_instant(text) |> option.from_result
    })
  decode.success(Past(id: session_id, outcome:, ended_at:))
}
