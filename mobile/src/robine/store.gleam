//// The app state shared by every screen, and the hook that renders it.

import gleam/list
import gleam/option.{type Option, None}
import redraw
import robine/global.{type Ref}

import robine/types.{
  type Alarm, type AlarmDraft, type DeviceState, type HueState, type HueTarget,
  type RemoteButtonState, type SmartphoneDismiss, type Sound, type Tab,
  type WakeSession, Morning,
}

pub type Connection {
  Scanning
  Connecting
  Connected
  Disconnected
}

pub type Transport {
  Http
  Bluetooth
}

pub type AppState {
  AppState(
    tab: Tab,
    connection: Connection,
    transport: Option(Transport),
    http_endpoint: Option(String),
    busy: Bool,
    error: Option(String),
    alarms: List(Alarm),
    sounds: List(Sound),
    device: Option(DeviceState),
    recent_sessions: List(WakeSession),
    active_session: Option(WakeSession),
    smartphone_dismiss: SmartphoneDismiss,
    hue: Option(HueState),
    hue_targets: List(HueTarget),
    remote_button: Option(RemoteButtonState),
    breathing_synchronized_at: Option(Int),
    editor: Option(AlarmDraft),
    challenge: Option(String),
    last_updated: Option(Int),
  )
}

pub const initial_state =
  AppState(
    tab: Morning,
    connection: Scanning,
    transport: None,
    http_endpoint: None,
    busy: False,
    error: None,
    alarms: [],
    sounds: [],
    device: None,
    recent_sessions: [],
    active_session: None,
    smartphone_dismiss: types.default_smartphone_dismiss,
    hue: None,
    hue_targets: [],
    remote_button: None,
    breathing_synchronized_at: None,
    editor: None,
    challenge: None,
    last_updated: None,
  )

fn state_ref() -> Ref(AppState) {
  global.named("store.state", fn() { initial_state })
}

fn listeners() -> Ref(List(#(Int, fn() -> Nil))) {
  global.named("store.listeners", fn() { [] })
}

fn next_listener() -> Ref(Int) {
  global.named("store.next_listener", fn() { 0 })
}

pub fn get_state() -> AppState {
  global.get(state_ref())
}

pub fn subscribe(listener: fn() -> Nil) -> fn() -> Nil {
  let id = global.get(next_listener())
  global.set(next_listener(), id + 1)
  global.update(listeners(), fn(all) { [#(id, listener), ..all] })
  fn() {
    global.update(listeners(), list.filter(_, fn(entry) { entry.0 != id }))
  }
}

fn emit() -> Nil {
  list.each(global.get(listeners()), fn(entry) { entry.1() })
}

/// Replaces the state with `change` applied to it and re-renders.
pub fn update(change: fn(AppState) -> AppState) -> Nil {
  global.update(state_ref(), change)
  emit()
}

pub fn use_app_state() -> AppState {
  redraw.use_sync_external_store(subscribe, get_state)
}

pub fn clear_error() -> Nil {
  update(fn(state) { AppState(..state, error: None) })
}
