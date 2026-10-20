//// The commands of the v1 protocol, their replies and how they fail.

import gleam/dynamic
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{type Option}
import gleam/result
import robine/alarm.{type Alarm, type Settings}
import robine/id.{type Id}
import robine/level.{type Percent}
import robine/light
import robine/nap
import robine/session.{type Active}
import robine/snapshot.{type RemoteButton, type Snapshot}

pub type Command {
  GetState
  GetSession
  CreateAlarm(Settings)
  /// Changes the alarm as it was read: the clock refuses it if it changed
  /// meanwhile.
  UpdateAlarm(alarm: Alarm, settings: Settings)
  DeleteAlarm(Alarm)
  TriggerAlarm(Id(Alarm))
  TriggerStrong(Id(Alarm))
  StartNap(nap.Length)
  CancelNap
  Dismiss
  SetSmartphoneDismiss(enabled: Bool)
  ConfirmClock
  EraseHistory
  StartBreathing(cadence: light.Cadence, length: light.Length, volume: Percent)
  SetBreathingVolume(Percent)
  StopBreathing
  StartLightProgram(program: light.Program, ambience: Option(light.Ambience))
  SetAmbienceVolume(Percent)
  /// What the strip shows, pixel by pixel.
  GetLight
  BeginButtonPairing
  RemoveButton(Id(RemoteButton))
}

pub type Reply {
  StateReply(Snapshot)
  SessionReply(Option(Active))
  /// What the strip shows, after a light command.
  LightReply(light.Reading)
  /// The clock did it; a later `state.get` shows the result.
  Done
}

pub type Failure {
  /// Another command is on its way.
  Busy
  /// Neither Wi-Fi nor Bluetooth reach the clock.
  NoRoute
  Unreachable(reason: String)
  BluetoothDenied
  BluetoothFailed(reason: String)
  Unreadable
  UnsupportedVersion
  Mismatched
  Refused(Refusal)
}

pub type Refusal {
  StaleRevision
  NotFound
  ValidationFailed
  WakeSessionActive
  UnsupportedOperation
  PairingWindowClosed
  RemoteButtonNotPaired
  SmartphoneDismissDisabled
  SmartphoneDismissLocked
  /// The clock cannot reach the ESP32 that drives the LED strip.
  LightUnavailable
  OtherRefusal(code: String)
}

/// Whether the clock's state may differ after the command.
pub fn changes_state(command: Command) -> Bool {
  case command {
    GetState | GetSession | GetLight -> False
    _ -> True
  }
}

pub fn operation(command: Command) -> String {
  case command {
    GetState -> "state.get"
    GetSession -> "session.get"
    CreateAlarm(..) -> "alarm.create"
    UpdateAlarm(..) -> "alarm.update"
    DeleteAlarm(..) -> "alarm.delete"
    TriggerAlarm(..) -> "alarm.trigger"
    TriggerStrong(..) -> "alarm.trigger_strong"
    StartNap(..) -> "nap.start"
    CancelNap -> "nap.cancel"
    Dismiss -> "session.dismiss"
    SetSmartphoneDismiss(..) -> "settings.smartphone_dismiss.set"
    ConfirmClock -> "clock.confirm"
    EraseHistory -> "history.erase"
    StartBreathing(..) -> "breathing.start"
    SetBreathingVolume(..) -> "breathing.volume"
    StopBreathing -> "breathing.stop"
    StartLightProgram(..) -> "light.program"
    GetLight -> "light.get"
    SetAmbienceVolume(..) -> "light.ambience.volume"
    BeginButtonPairing -> "remote_button.pairing.begin"
    RemoveButton(..) -> "remote_button.remove"
  }
}

pub fn body(command: Command) -> Json {
  case command {
    GetState
    | GetSession
    | CancelNap
    | Dismiss
    | ConfirmClock
    | EraseHistory
    | StopBreathing
    | GetLight -> json.object([])
    CreateAlarm(settings) ->
      json.object([#("alarm", alarm.encode(settings, option.None))])
    UpdateAlarm(alarm:, settings:) ->
      json.object([
        #("alarm_id", json.string(id.to_string(alarm.id))),
        #("alarm", alarm.encode(settings, option.Some(alarm.revision))),
      ])
    DeleteAlarm(alarm) ->
      json.object([
        #("alarm_id", json.string(id.to_string(alarm.id))),
        #("revision", json.int(alarm.revision)),
      ])
    TriggerAlarm(alarm_id) | TriggerStrong(alarm_id) ->
      json.object([#("alarm_id", json.string(id.to_string(alarm_id)))])
    StartNap(length) ->
      json.object([#("duration_minutes", json.int(nap.minutes(length)))])
    SetSmartphoneDismiss(enabled) ->
      json.object([#("enabled", json.bool(enabled))])
    StartBreathing(cadence:, length:, volume:) ->
      json.object([
        #("cadence", json.string(light.cadence_text(cadence))),
        #("duration_minutes", json.int(light.minutes(length))),
        #("volume_percent", json.int(level.percent_to_int(volume))),
      ])
    SetBreathingVolume(volume) ->
      json.object([#("volume_percent", json.int(level.percent_to_int(volume)))])
    StartLightProgram(program:, ambience:) ->
      light.encode_with(program, ambience)
    SetAmbienceVolume(volume) ->
      json.object([#("volume_percent", json.int(level.percent_to_int(volume)))])
    BeginButtonPairing -> json.object([#("duration_seconds", json.int(120))])
    RemoveButton(button) ->
      json.object([#("button_id", json.string(id.to_string(button)))])
  }
}

/// The request line sent to the clock.
pub fn encode(command: Command, id: String) -> String {
  json.object([
    #("v", json.int(1)),
    #("id", json.string(id)),
    #("op", json.string(operation(command))),
    #("body", body(command)),
  ])
  |> json.to_string
}

type Envelope {
  Accepted(id: String, body: dynamic.Dynamic)
  Rejected(id: String, code: String)
}

fn envelope_decoder() -> decode.Decoder(Result(Envelope, Failure)) {
  use version <- decode.field("v", decode.int)
  use id <- decode.field("id", decode.string)
  use status <- decode.field("status", decode.string)
  case version, status {
    1, "ok" -> {
      use body <- decode.optional_field(
        "body",
        dynamic.properties([]),
        decode.dynamic,
      )
      decode.success(Ok(Accepted(id:, body:)))
    }
    1, _ -> {
      use code <- decode.optional_field(
        "error",
        "unknown",
        decode.optional_field("code", "unknown", decode.string, decode.success),
      )
      decode.success(Ok(Rejected(id:, code:)))
    }
    _, _ -> decode.success(Error(UnsupportedVersion))
  }
}

/// Reads the clock's answer to the command sent with this id.
pub fn reply(
  command: Command,
  id: String,
  text: String,
) -> Result(Reply, Failure) {
  use envelope <- result.try(
    json.parse(text, envelope_decoder())
    |> result.replace_error(Unreadable)
    |> result.flatten,
  )
  case envelope {
    Accepted(id: answered, ..) | Rejected(id: answered, ..) if answered != id ->
      Error(Mismatched)
    Rejected(code:, ..) -> Error(Refused(refusal(code)))
    Accepted(body:, ..) ->
      case command {
        GetState ->
          decode.run(body, snapshot.decoder())
          |> result.map(StateReply)
          |> result.replace_error(Unreadable)
        GetSession ->
          decode.run(body, snapshot.active_session_decoder())
          |> result.map(SessionReply)
          |> result.replace_error(Unreadable)
        GetLight | StartLightProgram(..) ->
          decode.run(body, light.reading_decoder())
          |> result.map(LightReply)
          |> result.replace_error(Unreadable)
        _ -> Ok(Done)
      }
  }
}

pub fn refusal(code: String) -> Refusal {
  case code {
    "stale_revision" -> StaleRevision
    "not_found" -> NotFound
    "validation_failed" -> ValidationFailed
    "wake_session_active" -> WakeSessionActive
    "unsupported_operation" -> UnsupportedOperation
    "pairing_window_closed" -> PairingWindowClosed
    "remote_button_not_paired" -> RemoteButtonNotPaired
    "smartphone_dismiss_disabled" -> SmartphoneDismissDisabled
    "smartphone_dismiss_setting_locked" -> SmartphoneDismissLocked
    "light_unavailable" -> LightUnavailable
    other -> OtherRefusal(other)
  }
}

pub fn describe(failure: Failure) -> String {
  case failure {
    Busy -> "Une synchronisation est déjà en cours"
    NoRoute -> "Bluetooth indisponible"
    Unreachable(reason) -> reason
    BluetoothDenied ->
      "Autorisez le Bluetooth dans Réglages pour joindre le réveil."
    BluetoothFailed(reason) -> reason
    Unreadable -> "Réponse illisible du réveil"
    UnsupportedVersion -> "Version du protocole non prise en charge"
    Mismatched -> "La réponse ne correspond pas à la commande"
    Refused(refusal) -> describe_refusal(refusal)
  }
}

fn describe_refusal(refusal: Refusal) -> String {
  case refusal {
    StaleRevision -> "Cette alarme a changé. Actualisez avant de réessayer."
    NotFound -> "Cet élément n’existe plus sur le réveil."
    ValidationFailed -> "Certains réglages ne sont pas valides."
    WakeSessionActive -> "Une alarme est en cours sur le réveil."
    UnsupportedOperation ->
      "Cette fonction nécessite une version plus récente du réveil."
    PairingWindowClosed -> "La fenêtre d’association du bouton est fermée."
    RemoteButtonNotPaired -> "Ce bouton n’est plus associé au réveil."
    SmartphoneDismissDisabled -> "L’arrêt depuis le smartphone est désactivé."
    SmartphoneDismissLocked -> "Ce réglage est verrouillé pendant une alarme."
    LightUnavailable -> "Le réveil ne joint pas le ruban lumineux."
    OtherRefusal(code) -> "Le réveil a refusé la commande (" <> code <> ")"
  }
}
