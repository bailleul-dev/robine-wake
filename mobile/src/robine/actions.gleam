//// What the screens ask of the clock.

import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import robine/models
import robine/platform
import robine/store.{AppState}
import robine/transport.{command}
import robine/types.{type Alarm, type AlarmDraft, AlarmDraft}

fn draft_of(alarm: Option(Alarm)) -> AlarmDraft {
  models.alarm_to_draft(
    alarm,
    store.get_state().sounds,
    platform.local_timezone(),
  )
}

fn set_editor(editor: Option(AlarmDraft)) -> Nil {
  store.update(fn(state) { AppState(..state, editor:) })
}

pub fn edit_alarm(alarm: Alarm) -> Nil {
  set_editor(Some(draft_of(Some(alarm))))
}

pub fn create_alarm() -> Nil {
  let draft = draft_of(None)
  set_editor(
    Some(case store.get_state().hue_targets {
      [first, ..] ->
        AlarmDraft(
          ..draft,
          light_enabled: True,
          light_target_id: Some(first.id),
          light_target_name: Some(first.name),
        )
      [] -> draft
    }),
  )
}

pub fn close_editor() -> Nil {
  set_editor(None)
}

pub fn save_alarm(draft: AlarmDraft) -> Nil {
  let payload = models.draft_to_payload(draft)
  close_editor()
  case draft.id {
    Some(id) ->
      command(
        "alarm.update",
        json.object([#("alarm_id", json.string(id)), #("alarm", payload)]),
      )
    None -> command("alarm.create", json.object([#("alarm", payload)]))
  }
  Nil
}

/// Deletes an alarm known by its id and revision.
pub fn delete_alarm(id: Option(String), revision: Option(Int)) -> Nil {
  command(
    "alarm.delete",
    [
      field("alarm_id", id, json.string),
      field("revision", revision, json.int),
    ]
      |> option.values
      |> json.object,
  )
  Nil
}

pub fn set_alarm_enabled(alarm: Alarm, enabled: Bool) -> Nil {
  let draft = AlarmDraft(..draft_of(Some(alarm)), enabled:)
  command(
    "alarm.update",
    json.object([
      #("alarm_id", json.string(alarm.id)),
      #("alarm", models.draft_to_payload(draft)),
    ]),
  )
  Nil
}

/// A JSON field left out when absent, as `JSON.stringify` drops `undefined`.
fn field(
  name: String,
  value: Option(a),
  encode: fn(a) -> Json,
) -> Option(#(String, Json)) {
  option.map(value, fn(value) { #(name, encode(value)) })
}

type Sent =
  Promise(Result(Nil, String))

fn empty() -> Json {
  json.object([])
}

pub fn trigger_alarm(id: Option(String)) -> Sent {
  command(
    "alarm.trigger",
    option.values([field("alarm_id", id, json.string)]) |> json.object,
  )
}

pub fn trigger_strong(id: Option(String)) -> Sent {
  command(
    "alarm.trigger_strong",
    option.values([field("alarm_id", id, json.string)]) |> json.object,
  )
}

pub fn start_nap(minutes: Int) -> Sent {
  command("nap.start", json.object([#("duration_minutes", json.int(minutes))]))
}

pub fn cancel_nap() -> Sent {
  command("nap.cancel", empty())
}

pub fn dismiss() -> Sent {
  command("session.dismiss", empty())
}

pub fn set_smartphone_dismiss(enabled: Bool) -> Sent {
  command(
    "settings.smartphone_dismiss.set",
    json.object([#("enabled", json.bool(enabled))]),
  )
}

pub fn confirm_clock() -> Sent {
  command("clock.confirm", empty())
}

pub fn erase_history() -> Sent {
  command("history.erase", empty())
}

pub fn pair_hue(host: String) -> Sent {
  command("hue.pair", json.object([#("bridge_host", json.string(host))]))
}

pub fn refresh_hue() -> Sent {
  command("hue.refresh", empty())
}

pub fn disconnect_hue() -> Sent {
  command("hue.disconnect", empty())
}

pub fn start_breathing(target_id: String, duration: Int, volume: Int) -> Sent {
  command(
    "breathing.start",
    json.object([
      #("target_id", json.string(target_id)),
      #("duration_minutes", json.int(duration)),
      #("volume_percent", json.int(volume)),
    ]),
  )
}

pub fn breathing_volume(volume: Int) -> Sent {
  command(
    "breathing.volume",
    json.object([#("volume_percent", json.int(volume))]),
  )
}

pub fn stop_breathing() -> Sent {
  command("breathing.stop", empty())
}

pub fn begin_button_pairing() -> Sent {
  command(
    "remote_button.pairing.begin",
    json.object([#("duration_seconds", json.int(120))]),
  )
}

pub fn remove_button(id: String) -> Sent {
  command(
    "remote_button.remove",
    json.object([#("button_id", json.string(id))]),
  )
}
