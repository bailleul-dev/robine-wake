//// What the clock reports of itself in a `state.get` response.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import robine/alarm.{type Alarm}
import robine/calendar
import robine/decoding.{defaulted, number, optional}

pub type Snapshot {
  Snapshot(
    alarms: List(Alarm),
    sounds: List(Sound),
    device: Option(Device),
    recent_sessions: List(Session),
    active_session: Option(Session),
    smartphone_dismiss: SmartphoneDismiss,
    hue: Hue,
    breathing: Breathing,
    hue_targets: List(HueTarget),
    remote: RemoteButtons,
    /// Where the clock answers commands over Wi-Fi, best first.
    http_endpoints: List(String),
  )
}

pub type Sound {
  Sound(id: String, title: String, artist: Option(String), intensity: Intensity)
}

pub type Intensity {
  Gentle
  Bright
  Strong
  Meditation
  Custom
  Unrated
  OtherIntensity(String)
}

pub type Device {
  Device(
    clock_trusted: Bool,
    network: Health,
    audio: Health,
    firmware: Option(String),
  )
}

pub type Health {
  Available
  Unavailable
  Unreported
  OtherHealth(String)
}

/// A wake-up, ringing or finished.
pub type Session {
  Session(
    id: String,
    state: SessionState,
    phase: AudioPhase,
    test_mode: Bool,
    phone_may_dismiss: Bool,
    ended_at: Option(Int),
  )
}

pub type SessionState {
  Starting
  Ringing
  Snoozed
  /// The sleeper seems to have left the bed.
  LeavingBed
  /// The sound failed; the clock plays its safe fallback.
  FailedSafe
  Dismissed
  TimedOut
  Missed
  OtherState(String)
}

pub type AudioPhase {
  GentlePhase
  StrongPhase
}

pub type SmartphoneDismiss {
  SmartphoneDismiss(enabled: Bool, locked: Bool)
}

pub type Hue {
  Unpaired
  Paired(bridge: String, reachable: Bool, target_count: Int)
}

pub type HueTarget {
  HueTarget(id: String, name: String)
}

/// The evening breathing session, led by the Hue light.
pub type Breathing {
  Resting
  Guided(
    phase: BreathingPhase,
    phase_ms: Int,
    phase_started_at: Option(Int),
    phase_elapsed_ms: Int,
    remaining_seconds: Option(Int),
    target_id: Option(String),
    ambience: Bool,
    volume: Option(Int),
  )
}

pub type BreathingPhase {
  Inhale
  Exhale
}

pub type RemoteButtons {
  RemoteButtons(pairing: Bool, buttons: List(RemoteButton))
}

pub type RemoteButton {
  RemoteButton(id: String, name: String, last_seen_at: Option(Int))
}

pub const empty =
  Snapshot(
    alarms: [],
    sounds: [],
    device: None,
    recent_sessions: [],
    active_session: None,
    smartphone_dismiss: SmartphoneDismiss(enabled: True, locked: False),
    hue: Unpaired,
    breathing: Resting,
    hue_targets: [],
    remote: RemoteButtons(pairing: False, buttons: []),
    http_endpoints: [],
  )

pub fn is_strong(sound: Sound) -> Bool {
  sound.intensity == Strong
}

pub fn intensity_label(intensity: Intensity) -> String {
  case intensity {
    Gentle -> "Doux"
    Bright -> "Lumineux"
    Strong -> "Fort"
    Meditation -> "Méditation"
    Custom -> "Personnel"
    Unrated -> ""
    OtherIntensity(other) -> string.capitalise(other)
  }
}

/// The first sound of this intensity, or the first sound at all.
pub fn default_sound(sounds: List(Sound), intensity: Intensity) -> String {
  case list.find(sounds, fn(sound) { sound.intensity == intensity }), sounds {
    Ok(sound), _ -> sound.id
    Error(Nil), [first, ..] -> first.id
    Error(Nil), [] -> "default"
  }
}

pub fn health_label(health: Health) -> String {
  case health {
    Available -> "Disponible"
    Unavailable -> "Indisponible"
    Unreported -> "—"
    OtherHealth(other) -> string.capitalise(other)
  }
}

pub fn hue_paired(hue: Hue) -> Bool {
  case hue {
    Paired(..) -> True
    Unpaired -> False
  }
}

pub fn hue_ready(hue: Hue) -> Bool {
  case hue {
    Paired(reachable: True, ..) -> True
    _ -> False
  }
}

pub fn finished(state: SessionState) -> Bool {
  case state {
    Dismissed | TimedOut | Missed -> True
    _ -> False
  }
}

pub fn state_label(state: SessionState) -> String {
  case state {
    Starting -> "Démarrage"
    Ringing -> "En cours"
    Snoozed -> "En pause"
    LeavingBed -> "Sortie du lit"
    FailedSafe -> "Son de secours"
    Dismissed -> "Réveil réussi"
    TimedOut -> "Arrêt automatique"
    Missed -> "Manqué"
    OtherState(other) -> string.capitalise(other)
  }
}

// Decoding --------------------------------------------------------------------

pub fn decoder() -> Decoder(Snapshot) {
  use alarms <- defaulted("alarms", [], decode.list(alarm.decoder()))
  use sounds <- defaulted("sounds", [], decode.list(sound_decoder()))
  use device <- optional("device", device_decoder())
  use recent_sessions <- defaulted(
    "recent_sessions",
    [],
    decode.list(session_decoder()),
  )
  use active_session <- optional("active_session", session_decoder())
  use smartphone_dismiss <- defaulted(
    "smartphone_dismiss",
    empty.smartphone_dismiss,
    {
      use enabled <- defaulted("enabled", True, decode.bool)
      use locked <- defaulted("locked", False, decode.bool)
      decode.success(SmartphoneDismiss(enabled:, locked:))
    },
  )
  use #(hue, breathing) <- defaulted("hue", #(Unpaired, Resting), hue_decoder())
  use hue_targets <- defaulted(
    "hue_targets",
    [],
    decode.list({
      use id <- decode.field("id", decode.string)
      use name <- defaulted("name", id, decode.string)
      decode.success(HueTarget(id:, name:))
    }),
  )
  use remote <- defaulted("remote_button", empty.remote, remote_decoder())
  use http_endpoints <- defaulted("transport", [], {
    use endpoints <- defaulted("http_endpoints", [], decode.list(decode.string))
    decode.success(endpoints)
  })
  decode.success(Snapshot(
    alarms: alarm.by_time(alarms),
    sounds:,
    device:,
    recent_sessions:,
    active_session:,
    smartphone_dismiss:,
    hue:,
    breathing:,
    hue_targets:,
    remote:,
    http_endpoints:,
  ))
}

/// The body of a `session.get` response.
pub fn active_session_decoder() -> Decoder(Option(Session)) {
  use session <- optional("active_session", session_decoder())
  decode.success(session)
}

fn instant(text: Option(String)) -> Option(Int) {
  option.then(text, fn(text) {
    calendar.parse_instant(text) |> option.from_result
  })
}

fn sound_decoder() -> Decoder(Sound) {
  use id <- decode.field("id", decode.string)
  use title <- defaulted("title", id, decode.string)
  use artist <- optional("artist", decode.string)
  use intensity <- optional("intensity", decode.string)
  let artist =
    option.then(artist, fn(artist) {
      case string.trim(artist) {
        "" -> None
        _ -> Some(artist)
      }
    })
  let intensity = case intensity {
    None | Some("") -> Unrated
    Some("gentle") -> Gentle
    Some("bright") -> Bright
    Some("strong") -> Strong
    Some("meditation") -> Meditation
    Some("custom") -> Custom
    Some(other) -> OtherIntensity(other)
  }
  decode.success(Sound(id:, title:, artist:, intensity:))
}

fn session_decoder() -> Decoder(Session) {
  use id <- decode.field("id", decode.string)
  use state <- defaulted("state", "", decode.string)
  use phase <- optional("audio_phase", decode.string)
  use test_mode <- defaulted("test_mode", False, decode.bool)
  use phone_may_dismiss <- defaulted(
    "smartphone_dismiss_allowed",
    True,
    decode.bool,
  )
  use ended_at <- optional("ended_at", decode.string)
  let state = case state {
    "starting" -> Starting
    "ringing" -> Ringing
    "snoozed" -> Snoozed
    "exit_candidate" -> LeavingBed
    "failed_safe" -> FailedSafe
    "dismissed" -> Dismissed
    "timed_out" -> TimedOut
    "missed" -> Missed
    other -> OtherState(other)
  }
  let phase = case phase {
    Some("strong") -> StrongPhase
    _ -> GentlePhase
  }
  decode.success(Session(
    id:,
    state:,
    phase:,
    test_mode:,
    phone_may_dismiss:,
    ended_at: instant(ended_at),
  ))
}

/// The state of a part of the clock, as `{"state": "available"}`.
fn health(key: String, next: fn(Health) -> Decoder(a)) -> Decoder(a) {
  use state <- defaulted(key, None, {
    use state <- optional("state", decode.string)
    decode.success(state)
  })
  next(case state {
    Some("available") -> Available
    Some("unavailable") -> Unavailable
    None | Some("") -> Unreported
    Some(other) -> OtherHealth(other)
  })
}

fn device_decoder() -> Decoder(Device) {
  // Older firmware did not judge the clock: no reason to worry then.
  use clock_trusted <- defaulted("clock_trusted", True, decode.bool)
  use network <- health("network")
  use audio <- health("audio")
  use firmware <- defaulted("firmware", None, {
    use version <- optional("version", decode.string)
    decode.success(version)
  })
  decode.success(Device(clock_trusted:, network:, audio:, firmware:))
}

fn hue_decoder() -> Decoder(#(Hue, Breathing)) {
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
      use phase_started_at <- optional("phase_started_at", decode.string)
      use phase_elapsed_ms <- defaulted("phase_elapsed_ms", 0, number())
      use remaining_seconds <- optional("remaining_seconds", number())
      use target_id <- optional("target_id", decode.string)
      use #(ambience, volume) <- defaulted("audio", #(False, None), {
        use active <- defaulted("active", False, decode.bool)
        use volume <- optional("volume_percent", number())
        decode.success(#(active, volume))
      })
      decode.success(Guided(
        phase:,
        phase_ms: int.max(1, phase_ms),
        phase_started_at: instant(phase_started_at),
        phase_elapsed_ms:,
        remaining_seconds:,
        target_id:,
        ambience:,
        volume:,
      ))
    }
  }
}

fn remote_decoder() -> Decoder(RemoteButtons) {
  use pairing <- defaulted("pairing", False, {
    use active <- defaulted("active", False, decode.bool)
    decode.success(active)
  })
  use buttons <- defaulted(
    "buttons",
    [],
    decode.list({
      use id <- decode.field("id", decode.string)
      use name <- defaulted("name", id, decode.string)
      use last_seen_at <- optional("last_seen_at", decode.string)
      decode.success(RemoteButton(
        id:,
        name:,
        last_seen_at: instant(last_seen_at),
      ))
    }),
  )
  decode.success(RemoteButtons(pairing:, buttons:))
}
