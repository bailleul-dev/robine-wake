//// The app state shared by every screen, and the hook that renders it.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/time/timestamp.{type Timestamp}
import redraw
import robine/command.{type Failure}
import robine/draft.{type Draft}
import robine/global.{type Ref}
import robine/id.{type Id}
import robine/link.{type Connection}
import robine/routes.{type Tab, Morning}
import robine/session.{type Active, type Session}
import robine/snapshot.{type Snapshot}

pub type AppState {
  AppState(
    tab: Tab,
    connection: Connection,
    /// The clock's Wi-Fi command endpoint, once known.
    endpoint: Option(String),
    /// A command is on its way.
    busy: Bool,
    failure: Option(Failure),
    clock: Snapshot,
    /// When the clock last answered `state.get`.
    synced_at: Option(Timestamp),
    editor: Option(Draft),
    /// The wake-up session whose challenge is open.
    challenge: Option(Id(Session)),
  )
}

pub const initial_state =
  AppState(
    tab: Morning,
    connection: link.Searching,
    endpoint: None,
    busy: False,
    failure: None,
    clock: snapshot.empty,
    synced_at: None,
    editor: None,
    challenge: None,
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

/// The session whose challenge is open, while it is still ringing: a challenge
/// left open after its alarm stopped elsewhere shows nothing and stops nothing.
pub fn challenged(state: AppState) -> Option(Active) {
  case state.challenge, state.clock.active_session {
    Some(wanted), Some(active) if active.id == wanted -> Some(active)
    _, _ -> None
  }
}

pub fn clear_failure() -> Nil {
  update(fn(state) { AppState(..state, failure: None) })
}
