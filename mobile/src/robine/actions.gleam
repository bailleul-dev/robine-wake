//// What the screens ask of the clock and of the editor.

import gleam/javascript/promise.{type Promise}
import gleam/option.{None, Some}
import robine/alarm.{type Alarm, Settings}
import robine/command.{type Command, type Failure, type Reply}
import robine/draft.{type Draft}
import robine/platform
import robine/store.{AppState}
import robine/transport

pub type Sent =
  Promise(Result(Reply, Failure))

pub fn send(command: Command) -> Sent {
  transport.send(command)
}

pub fn refresh() -> Sent {
  transport.refresh()
}

fn set_editor(editor) -> Nil {
  store.update(fn(state) { AppState(..state, editor:) })
}

pub fn edit_alarm(alarm: Alarm) -> Nil {
  set_editor(Some(draft.from_alarm(alarm)))
}

pub fn create_alarm() -> Nil {
  let clock = store.get_state().clock
  set_editor(
    Some(draft.new(clock.sounds, clock.hue_targets, platform.local_timezone())),
  )
}

pub fn close_editor() -> Nil {
  set_editor(None)
}

/// Sends the draft when it is valid; the editor stays open otherwise.
pub fn save_alarm(draft: Draft) -> Nil {
  case draft.validate(draft) {
    Error(_) -> Nil
    Ok(settings) -> {
      close_editor()
      send(case draft.origin {
        draft.Existing(id:, revision:) ->
          command.UpdateAlarm(id:, revision:, settings:)
        draft.New -> command.CreateAlarm(settings)
      })
      Nil
    }
  }
}

pub fn delete_alarm(id: String, revision: Int) -> Nil {
  close_editor()
  send(command.DeleteAlarm(id:, revision:))
  Nil
}

pub fn set_alarm_enabled(alarm: Alarm, enabled: Bool) -> Nil {
  send(command.UpdateAlarm(
    id: alarm.id,
    revision: alarm.revision,
    settings: Settings(..alarm.settings, enabled:),
  ))
  Nil
}

pub fn open_challenge(session_id: String) -> Nil {
  store.update(fn(state) { AppState(..state, challenge: Some(session_id)) })
}

pub fn close_challenge() -> Nil {
  store.update(fn(state) { AppState(..state, challenge: None) })
}
