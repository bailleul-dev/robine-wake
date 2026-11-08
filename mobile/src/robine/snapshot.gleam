//// What the clock reports of itself in a `state.get` response.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/timestamp.{type Timestamp}
import robine/alarm.{type Alarm}
import robine/breathing.{type Breathing}
import robine/calendar
import robine/decoding.{defaulted, optional}
import robine/id.{type Id}
import robine/light
import robine/nap.{type Nap}
import robine/session.{type Active, type Past}
import robine/sound.{type Sound}

pub type Snapshot {
  Snapshot(
    /// The user's alarms, by time of day.
    alarms: List(Alarm),
    nap: Option(Nap),
    sounds: List(Sound),
    device: Option(Device),
    recent_sessions: List(Past),
    active_session: Option(Active),
    smartphone_dismiss: SmartphoneDismiss,
    night_radio: NightRadio,
    breathing: Breathing,
    /// The sound playing along the strip's program.
    ambience: Option(light.Playing),
    remote: RemoteButtons,
    /// Where the clock answers commands over Wi-Fi, best first.
    http_endpoints: List(String),
  )
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

pub type SmartphoneDismiss {
  SmartphoneDismiss(enabled: Bool, locked: Bool)
}

/// The nightly window during which the clock turns its Wi-Fi and Bluetooth
/// off. The alarm keeps working; the app cannot reach the clock meanwhile.
pub type NightRadio {
  NightRadio(
    enabled: Bool,
    /// Local "HH:MM" times; the window may span midnight.
    start: String,
    until: String,
    silenced: Bool,
  )
}

pub type RemoteButtons {
  RemoteButtons(pairing: Bool, buttons: List(RemoteButton))
}

pub type RemoteButton {
  RemoteButton(
    id: Id(RemoteButton),
    name: String,
    last_seen_at: Option(Timestamp),
  )
}

pub const empty =
  Snapshot(
    alarms: [],
    nap: None,
    sounds: [],
    device: None,
    recent_sessions: [],
    active_session: None,
    smartphone_dismiss: SmartphoneDismiss(enabled: True, locked: False),
    night_radio: NightRadio(
      enabled: False,
      start: "23:00",
      until: "07:00",
      silenced: False,
    ),
    breathing: breathing.Resting,
    ambience: None,
    remote: RemoteButtons(pairing: False, buttons: []),
    http_endpoints: [],
  )

pub fn health_label(health: Health) -> String {
  case health {
    Available -> "Disponible"
    Unavailable -> "Indisponible"
    Unreported -> "—"
    OtherHealth(other) -> string.capitalise(other)
  }
}

// Decoding --------------------------------------------------------------------

pub fn decoder() -> Decoder(Snapshot) {
  use entries <- defaulted("alarms", [], decode.list(alarm.entry_decoder()))
  use sounds <- defaulted("sounds", [], decode.list(sound.decoder()))
  use device <- optional("device", device_decoder())
  use recent_sessions <- defaulted(
    "recent_sessions",
    [],
    decode.list(session.past_decoder()),
  )
  use active_session <- optional("active_session", session.active_decoder())
  use smartphone_dismiss <- defaulted(
    "smartphone_dismiss",
    empty.smartphone_dismiss,
    {
      use enabled <- defaulted("enabled", True, decode.bool)
      use locked <- defaulted("locked", False, decode.bool)
      decode.success(SmartphoneDismiss(enabled:, locked:))
    },
  )
  use night_radio <- defaulted(
    "night_radio",
    empty.night_radio,
    night_radio_decoder(),
  )
  use breathing <- defaulted(
    "breathing",
    breathing.Resting,
    breathing.decoder(),
  )
  use ambience <- defaulted("light_ambience", None, light.playing_decoder())
  use remote <- defaulted("remote_button", empty.remote, remote_decoder())
  use http_endpoints <- defaulted("transport", [], {
    use endpoints <- defaulted("http_endpoints", [], decode.list(decode.string))
    decode.success(endpoints)
  })
  let #(alarms, nap) = split(entries)
  decode.success(Snapshot(
    alarms: alarm.by_time(alarms),
    nap:,
    sounds:,
    device:,
    recent_sessions:,
    active_session: option.flatten(active_session),
    smartphone_dismiss:,
    night_radio:,
    breathing:,
    ambience:,
    remote:,
    http_endpoints:,
  ))
}

/// The user's alarms, and the nap when one is set to ring.
fn split(entries: List(alarm.Entry)) -> #(List(Alarm), Option(Nap)) {
  let alarms =
    list.filter_map(entries, fn(entry) {
      case entry {
        alarm.Recurring(alarm) -> Ok(alarm)
        alarm.OneShot(..) -> Error(Nil)
      }
    })
  let nap =
    list.find_map(entries, fn(entry) {
      case entry {
        alarm.OneShot(enabled: True, next_rings: [rings_at, ..]) ->
          Ok(nap.Nap(rings_at:))
        _ -> Error(Nil)
      }
    })
  #(alarms, option.from_result(nap))
}

/// The body of a `session.get` response.
pub fn active_session_decoder() -> Decoder(Option(Active)) {
  use active <- optional("active_session", session.active_decoder())
  decode.success(option.flatten(active))
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

/// Moves a local "HH:MM" time by `minutes`, wrapping around midnight; an
/// unreadable time is returned unchanged.
pub fn shift_time(time: String, minutes: Int) -> String {
  case string.split(time, ":") {
    [hours, mins] ->
      case int.parse(hours), int.parse(mins) {
        Ok(h), Ok(m) -> {
          let total = { h * 60 + m + minutes } % 1440
          let total = case total < 0 {
            True -> total + 1440
            False -> total
          }
          two_digits(total / 60) <> ":" <> two_digits(total % 60)
        }
        _, _ -> time
      }
    _ -> time
  }
}

fn two_digits(value: Int) -> String {
  string.pad_start(int.to_string(value), 2, "0")
}

fn night_radio_decoder() -> Decoder(NightRadio) {
  let default = empty.night_radio
  use enabled <- defaulted("enabled", default.enabled, decode.bool)
  use start <- defaulted("start", default.start, decode.string)
  use until <- defaulted("end", default.until, decode.string)
  use state <- defaulted("state", "radios_on", decode.string)
  decode.success(NightRadio(
    enabled:,
    start:,
    until:,
    silenced: state == "silenced",
  ))
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
      use button_id <- decode.field("id", decode.string)
      use name <- defaulted("name", button_id, decode.string)
      use last_seen_at <- optional("last_seen_at", decode.string)
      decode.success(RemoteButton(
        id: id.from_string(button_id),
        name:,
        last_seen_at: option.then(last_seen_at, fn(text) {
          calendar.parse_instant(text) |> option.from_result
        }),
      ))
    }),
  )
  decode.success(RemoteButtons(pairing:, buttons:))
}
