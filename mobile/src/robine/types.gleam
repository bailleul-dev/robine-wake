//// Data the alarm clock sends, decoded from the v1 command protocol. Absent
//// and `null` fields decode alike, as optional chaining did in the former app.

import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/option.{type Option, None}
import gleam/set.{type Set}

pub type Tab {
  Morning
  Evening
  Alarms
  System
}

pub type Sound {
  Sound(
    id: String,
    title: String,
    artist: Option(String),
    intensity: Option(String),
  )
}

pub type HueTarget {
  HueTarget(id: String, name: String)
}

pub type VolumeProfile {
  VolumeProfile(
    start: Option(Int),
    ceiling: Option(Int),
    strong: Option(Int),
    ramp_seconds: Option(Int),
  )
}

pub type LightProfile {
  LightProfile(
    enabled: Bool,
    target_id: Option(String),
    target_name: Option(String),
    start_brightness: Option(Int),
    end_brightness: Option(Int),
    ramp_seconds: Option(Int),
    end_behavior: Option(String),
  )
}

pub type Alarm {
  Alarm(
    id: String,
    label: String,
    enabled: Bool,
    local_time: String,
    days_of_week: List(Int),
    timezone: String,
    sound_id: String,
    strong_sound_id: String,
    prewake_seconds: Option(Int),
    revision: Option(Int),
    next_occurrences: List(String),
    volume_profile: VolumeProfile,
    light_profile: LightProfile,
  )
}

/// An alarm while it is edited.
pub type AlarmDraft {
  AlarmDraft(
    id: Option(String),
    label: String,
    enabled: Bool,
    hour: Int,
    minute: Int,
    days: Set(Int),
    timezone: String,
    sound_id: String,
    strong_sound_id: String,
    start_volume: Int,
    ceiling_volume: Int,
    strong_volume: Int,
    prewake_minutes: Int,
    revision: Option(Int),
    light_enabled: Bool,
    light_target_id: Option(String),
    light_target_name: Option(String),
    light_start_brightness: Int,
    light_end_brightness: Int,
    light_ramp_minutes: Int,
    light_end_behavior: String,
  )
}

pub type WakeSession {
  WakeSession(
    id: String,
    state: Option(String),
    audio_phase: Option(String),
    test_mode: Bool,
    smartphone_dismiss_allowed: Bool,
    ended_at: Option(String),
  )
}

pub type BreathingState {
  BreathingState(
    active: Bool,
    phase: Option(String),
    phase_duration_ms: Option(Int),
    phase_started_at: Option(String),
    phase_elapsed_ms: Option(Int),
    remaining_seconds: Option(Int),
    target_id: Option(String),
    audio_active: Bool,
    audio_volume_percent: Option(Int),
  )
}

pub type HueState {
  HueState(
    configured: Bool,
    state: Option(String),
    bridge_host: Option(String),
    target_count: Int,
    breathing: BreathingState,
  )
}

pub type RemoteButton {
  RemoteButton(id: String, name: String, last_seen_at: Option(String))
}

pub type RemoteButtonState {
  RemoteButtonState(pairing_active: Bool, buttons: List(RemoteButton))
}

pub type DeviceState {
  DeviceState(
    clock_trusted: Option(Bool),
    network_state: Option(String),
    audio_state: Option(String),
    firmware_version: Option(String),
  )
}

pub type SmartphoneDismiss {
  SmartphoneDismiss(enabled: Bool, locked: Bool)
}

/// Body of a `state.get` response.
pub type StateBody {
  StateBody(
    alarms: List(Alarm),
    sounds: List(Sound),
    device: Option(DeviceState),
    recent_sessions: List(WakeSession),
    active_session: Option(WakeSession),
    smartphone_dismiss: SmartphoneDismiss,
    hue: Option(HueState),
    hue_targets: List(HueTarget),
    remote_button: Option(RemoteButtonState),
    http_endpoints: List(String),
  )
}

// Decoders --------------------------------------------------------------------

/// A field that may be absent or `null`.
fn optional(
  key: String,
  decoder: Decoder(a),
  next: fn(Option(a)) -> Decoder(b),
) -> Decoder(b) {
  decode.optional_field(key, None, decode.optional(decoder), next)
}

/// A field that may be absent or `null`, replaced by `default`.
fn defaulted(
  key: String,
  default: a,
  decoder: Decoder(a),
  next: fn(a) -> Decoder(b),
) -> Decoder(b) {
  use value <- optional(key, decoder)
  next(option.unwrap(value, default))
}

/// Integers, also when the clock sends them as floats.
pub fn number() -> Decoder(Int) {
  decode.one_of(decode.int, [decode.float |> decode.map(float.round)])
}

pub fn sound_decoder() -> Decoder(Sound) {
  use id <- decode.field("id", decode.string)
  use title <- defaulted("title", id, decode.string)
  use artist <- optional("artist", decode.string)
  use intensity <- optional("intensity", decode.string)
  decode.success(Sound(id:, title:, artist:, intensity:))
}

pub fn hue_target_decoder() -> Decoder(HueTarget) {
  use id <- decode.field("id", decode.string)
  use name <- defaulted("name", id, decode.string)
  decode.success(HueTarget(id:, name:))
}

fn volume_profile_decoder() -> Decoder(VolumeProfile) {
  use start <- optional("start", number())
  use ceiling <- optional("ceiling", number())
  use strong <- optional("strong", number())
  use ramp_seconds <- optional("ramp_seconds", number())
  decode.success(VolumeProfile(start:, ceiling:, strong:, ramp_seconds:))
}

pub const no_volume_profile = VolumeProfile(None, None, None, None)

fn light_profile_decoder() -> Decoder(LightProfile) {
  use enabled <- defaulted("enabled", False, decode.bool)
  use target_id <- optional("target_id", decode.string)
  use target_name <- optional("target_name", decode.string)
  use start_brightness <- optional("start_brightness", number())
  use end_brightness <- optional("end_brightness", number())
  use ramp_seconds <- optional("ramp_seconds", number())
  use end_behavior <- optional("end_behavior", decode.string)
  decode.success(LightProfile(
    enabled:,
    target_id:,
    target_name:,
    start_brightness:,
    end_brightness:,
    ramp_seconds:,
    end_behavior:,
  ))
}

pub const no_light_profile =
  LightProfile(False, None, None, None, None, None, None)

pub fn alarm_decoder() -> Decoder(Alarm) {
  use id <- decode.field("id", decode.string)
  use label <- defaulted("label", "", decode.string)
  use enabled <- defaulted("enabled", False, decode.bool)
  use local_time <- defaulted("local_time", "07:00", decode.string)
  use days_of_week <- defaulted("days_of_week", [], decode.list(number()))
  use timezone <- defaulted("timezone", "Europe/Paris", decode.string)
  use sound_id <- defaulted("sound_id", "", decode.string)
  use strong_sound_id <- defaulted("strong_sound_id", "", decode.string)
  use prewake_seconds <- optional("prewake_seconds", number())
  use revision <- optional("revision", number())
  use next_occurrences <- defaulted(
    "next_occurrences",
    [],
    decode.list(decode.string),
  )
  use volume_profile <- defaulted(
    "volume_profile",
    no_volume_profile,
    volume_profile_decoder(),
  )
  use light_profile <- defaulted(
    "light_profile",
    no_light_profile,
    light_profile_decoder(),
  )
  decode.success(Alarm(
    id:,
    label:,
    enabled:,
    local_time:,
    days_of_week:,
    timezone:,
    sound_id:,
    strong_sound_id:,
    prewake_seconds:,
    revision:,
    next_occurrences:,
    volume_profile:,
    light_profile:,
  ))
}

pub fn session_decoder() -> Decoder(WakeSession) {
  use id <- decode.field("id", decode.string)
  use state <- optional("state", decode.string)
  use audio_phase <- optional("audio_phase", decode.string)
  use test_mode <- defaulted("test_mode", False, decode.bool)
  use smartphone_dismiss_allowed <- defaulted(
    "smartphone_dismiss_allowed",
    True,
    decode.bool,
  )
  use ended_at <- optional("ended_at", decode.string)
  decode.success(WakeSession(
    id:,
    state:,
    audio_phase:,
    test_mode:,
    smartphone_dismiss_allowed:,
    ended_at:,
  ))
}

pub const no_breathing =
  BreathingState(False, None, None, None, None, None, None, False, None)

fn breathing_decoder() -> Decoder(BreathingState) {
  use active <- defaulted("active", False, decode.bool)
  use phase <- optional("phase", decode.string)
  use phase_duration_ms <- optional("phase_duration_ms", number())
  use phase_started_at <- optional("phase_started_at", decode.string)
  use phase_elapsed_ms <- optional("phase_elapsed_ms", number())
  use remaining_seconds <- optional("remaining_seconds", number())
  use target_id <- optional("target_id", decode.string)
  use audio <- defaulted("audio", #(False, None), {
    use active <- defaulted("active", False, decode.bool)
    use volume <- optional("volume_percent", number())
    decode.success(#(active, volume))
  })
  decode.success(BreathingState(
    active:,
    phase:,
    phase_duration_ms:,
    phase_started_at:,
    phase_elapsed_ms:,
    remaining_seconds:,
    target_id:,
    audio_active: audio.0,
    audio_volume_percent: audio.1,
  ))
}

fn hue_decoder() -> Decoder(HueState) {
  use configured <- defaulted("configured", False, decode.bool)
  use state <- optional("state", decode.string)
  use bridge_host <- optional("bridge_host", decode.string)
  use target_count <- defaulted("target_count", 0, number())
  use breathing <- defaulted("breathing", no_breathing, breathing_decoder())
  decode.success(HueState(
    configured:,
    state:,
    bridge_host:,
    target_count:,
    breathing:,
  ))
}

fn remote_button_decoder() -> Decoder(RemoteButtonState) {
  use pairing_active <- defaulted(
    "pairing",
    False,
    decode.optional_field("active", False, decode.bool, decode.success),
  )
  use buttons <- defaulted(
    "buttons",
    [],
    decode.list({
      use id <- decode.field("id", decode.string)
      use name <- defaulted("name", id, decode.string)
      use last_seen_at <- optional("last_seen_at", decode.string)
      decode.success(RemoteButton(id:, name:, last_seen_at:))
    }),
  )
  decode.success(RemoteButtonState(pairing_active:, buttons:))
}

fn state_of(key: String, next: fn(Option(String)) -> Decoder(a)) -> Decoder(a) {
  use value <- defaulted(
    key,
    None,
    decode.optional_field("state", None, decode.optional(decode.string), {
      decode.success
    }),
  )
  next(value)
}

fn device_decoder() -> Decoder(DeviceState) {
  use clock_trusted <- optional("clock_trusted", decode.bool)
  use network_state <- state_of("network")
  use audio_state <- state_of("audio")
  use firmware_version <- defaulted(
    "firmware",
    None,
    decode.optional_field(
      "version",
      None,
      decode.optional(decode.string),
      decode.success,
    ),
  )
  decode.success(DeviceState(
    clock_trusted:,
    network_state:,
    audio_state:,
    firmware_version:,
  ))
}

pub const default_smartphone_dismiss =
  SmartphoneDismiss(enabled: True, locked: False)

fn smartphone_dismiss_decoder() -> Decoder(SmartphoneDismiss) {
  use enabled <- defaulted("enabled", True, decode.bool)
  use locked <- defaulted("locked", False, decode.bool)
  decode.success(SmartphoneDismiss(enabled:, locked:))
}

pub fn state_body_decoder() -> Decoder(StateBody) {
  use alarms <- defaulted("alarms", [], decode.list(alarm_decoder()))
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
    default_smartphone_dismiss,
    smartphone_dismiss_decoder(),
  )
  use hue <- optional("hue", hue_decoder())
  use hue_targets <- defaulted(
    "hue_targets",
    [],
    decode.list(hue_target_decoder()),
  )
  use remote_button <- optional("remote_button", remote_button_decoder())
  use http_endpoints <- defaulted(
    "transport",
    [],
    decode.optional_field(
      "http_endpoints",
      [],
      decode.list(decode.string),
      decode.success,
    ),
  )
  decode.success(StateBody(
    alarms:,
    sounds:,
    device:,
    recent_sessions:,
    active_session:,
    smartphone_dismiss:,
    hue:,
    hue_targets:,
    remote_button:,
    http_endpoints:,
  ))
}

/// Body of a `session.get` response.
pub fn session_body_decoder() -> Decoder(Option(WakeSession)) {
  use active_session <- optional("active_session", session_decoder())
  decode.success(active_session)
}
