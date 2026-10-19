//// The v1 command protocol over HTTP or Bluetooth, and the event stream that
//// tells the app when to refresh.

import gleam/bit_array
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import robine/global.{type Ref}
import robine/native
import robine/platform.{type Device, type Stream, type Timer}
import robine/protocol
import robine/sse.{type ServerEvent}
import robine/store.{
  AppState, Bluetooth, Connected, Connecting, Disconnected, Http, Scanning,
}
import robine/types.{type StateBody}

pub const endpoint_storage_key = "robineWake.httpCommandEndpoint.v1"

pub const web_command_endpoint = "/api/v1/command"

/// What the TypeScript module kept in top-level variables.
type Link {
  Link(
    device: Option(Device),
    pending: Option(String),
    bluetooth_state: Option(fn() -> Nil),
    stream: Option(Stream),
    retry_timer: Option(Timer),
    retry_delay: Int,
    generation: Int,
    last_id: Option(String),
    endpoint: Option(String),
    buffer: String,
    refresh_pending: Bool,
    app_state: Option(fn() -> Nil),
  )
}

fn link() -> Ref(Link) {
  global.named("transport.link", fn() {
    Link(
      device: None,
      pending: None,
      bluetooth_state: None,
      stream: None,
      retry_timer: None,
      retry_delay: 1000,
      generation: 0,
      last_id: None,
      endpoint: None,
      buffer: "",
      refresh_pending: False,
      app_state: None,
    )
  })
}

fn current() -> Link {
  global.get(link())
}

fn change(update: fn(Link) -> Link) -> Nil {
  global.update(link(), update)
}

fn web() -> Bool {
  native.web()
}

pub fn make_request_id() -> String {
  "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  |> string.to_graphemes
  |> list.map(fn(token) {
    let random = int.random(16)
    case token {
      "x" -> hex(random)
      "y" -> hex(int.bitwise_or(int.bitwise_and(random, 0x3), 0x8))
      other -> other
    }
  })
  |> string.concat
}

fn hex(value: Int) -> String {
  string.lowercase(int.to_base16(value))
}

pub fn error_message(code: String) -> String {
  case code {
    "stale_revision" -> "Cette alarme a changé. Actualisez avant de réessayer."
    "not_found" -> "Cet élément n’existe plus sur le réveil."
    "validation_failed" -> "Certains réglages ne sont pas valides."
    "hue_link_button_required" ->
      "Appuyez sur le bouton rond du pont Hue, puis réessayez."
    "invalid_hue_bridge_address" -> "L’adresse du pont Hue n’est pas valide."
    "hue_pairing_failed" -> "Le pont Hue a refusé l’association."
    "hue_target_not_found" -> "Cette pièce ou zone Hue n’est plus disponible."
    "wake_session_active" -> "Une alarme utilise déjà la lumière Hue."
    "unsupported_operation" ->
      "Cette fonction nécessite une version plus récente du réveil."
    "pairing_window_closed" -> "La fenêtre d’association du bouton est fermée."
    "remote_button_not_paired" -> "Ce bouton n’est plus associé au réveil."
    "smartphone_dismiss_disabled" ->
      "L’arrêt depuis le smartphone est désactivé."
    "smartphone_dismiss_setting_locked" ->
      "Ce réglage est verrouillé pendant une alarme."
    _ -> "Le réveil a refusé la commande (" <> code <> ")"
  }
}

// Bluetooth -------------------------------------------------------------------

fn write_chunks(
  device: Device,
  chunks: List(BitArray),
) -> Promise(Result(Nil, String)) {
  case chunks {
    [] -> promise.resolve(Ok(Nil))
    [chunk, ..rest] -> {
      use written <- promise.await(platform.ble_write(
        device,
        protocol.service_uuid,
        protocol.command_uuid,
        bit_array.base64_encode(chunk, True),
      ))
      case written {
        Ok(Nil) -> write_chunks(device, rest)
        Error(reason) -> promise.resolve(Error(reason))
      }
    }
  }
}

fn response_pages(
  device: Device,
  assembly: Result(protocol.Assembly, Nil),
) -> Promise(Result(String, String)) {
  use read <- promise.await(platform.ble_read(
    device,
    protocol.service_uuid,
    protocol.response_uuid,
  ))
  let step = {
    use value <- result.try(read)
    use bytes <- result.try(
      bit_array.base64_decode(value)
      |> result.replace_error("Pages Bluetooth incohérentes"),
    )
    use page <- result.try(protocol.parse_page(bytes))
    protocol.add_page(assembly, page)
  }
  case step {
    Error(reason) -> promise.resolve(Error(reason))
    Ok(protocol.Done(text)) -> promise.resolve(Ok(text))
    Ok(protocol.Continue(next)) -> response_pages(device, Ok(next))
  }
}

fn ble_request(json: String) -> Promise(Result(String, String)) {
  case current().device {
    None -> promise.resolve(Error("Bluetooth indisponible"))
    Some(device) -> {
      use written <- promise.await(write_chunks(
        device,
        protocol.command_chunks(json),
      ))
      case written {
        Error(reason) -> promise.resolve(Error(reason))
        Ok(Nil) -> response_pages(device, Error(Nil))
      }
    }
  }
}

// Responses -------------------------------------------------------------------

fn remember_endpoint(body: StateBody) -> Nil {
  case web(), body.http_endpoints {
    False, [endpoint, ..] -> {
      let changed = Some(endpoint) != store.get_state().http_endpoint
      store.update(fn(state) {
        AppState(..state, http_endpoint: Some(endpoint))
      })
      platform.storage_set(endpoint_storage_key, endpoint)
      case changed {
        True -> start_event_stream(endpoint)
        False -> Nil
      }
    }
    _, _ -> Nil
  }
}

fn apply_state(body: StateBody) -> Nil {
  // Gleam 1.19 takes this call, in a cycle with the event stream, for pure.
  let Nil = remember_endpoint(body)
  let now = platform.now()
  let breathing = case body.hue {
    Some(types.HueState(breathing: types.BreathingState(active: True, ..), ..)) ->
      Some(now)
    _ -> None
  }
  store.update(fn(state) {
    AppState(
      ..state,
      alarms: list.sort(body.alarms, fn(left, right) {
        string.compare(left.local_time, right.local_time)
      }),
      sounds: body.sounds,
      device: body.device,
      recent_sessions: body.recent_sessions,
      active_session: body.active_session,
      smartphone_dismiss: body.smartphone_dismiss,
      hue: body.hue,
      hue_targets: body.hue_targets,
      remote_button: body.remote_button,
      breathing_synchronized_at: breathing,
      last_updated: Some(now),
    )
  })
}

type Envelope {
  Envelope(
    v: Int,
    id: String,
    status: String,
    code: String,
    body: decode.Dynamic,
  )
}

fn envelope_decoder() -> decode.Decoder(Envelope) {
  use v <- decode.field("v", decode.int)
  use id <- decode.field("id", decode.string)
  use status <- decode.field("status", decode.string)
  use code <- decode.optional_field(
    "error",
    "unknown",
    decode.optional_field("code", "unknown", decode.string, decode.success),
  )
  use body <- decode.optional_field(
    "body",
    dynamic.properties([]),
    decode.dynamic,
  )
  decode.success(Envelope(v:, id:, status:, code:, body:))
}

/// Checks the envelope and applies what `state.get` and `session.get` return.
pub fn handle_response(
  operation: String,
  request_id: String,
  text: String,
) -> Result(Nil, String) {
  case json.parse(text, envelope_decoder()) {
    Error(_) -> Error("Réponse illisible du réveil")
    Ok(Envelope(v:, ..)) if v != 1 ->
      Error("Version du protocole non prise en charge")
    Ok(Envelope(id:, ..)) if id != request_id ->
      Error("La réponse ne correspond pas à la commande")
    Ok(Envelope(status:, code:, ..)) if status != "ok" ->
      Error(error_message(code))
    Ok(Envelope(body:, ..)) ->
      case operation {
        "state.get" ->
          decode.run(body, types.state_body_decoder())
          |> result.map(apply_state)
          |> result.replace_error("Réponse illisible du réveil")
        "session.get" ->
          decode.run(body, types.session_body_decoder())
          |> result.map(fn(session) {
            store.update(fn(state) {
              AppState(..state, active_session: session)
            })
          })
          |> result.replace_error("Réponse illisible du réveil")
        _ -> Ok(Nil)
      }
  }
}

// Commands --------------------------------------------------------------------

fn finish_command() -> Nil {
  change(fn(link) { Link(..link, pending: None) })
  store.update(fn(state) { AppState(..state, busy: False) })
  drain_event_refresh()
}

fn connected_over_http() -> Nil {
  store.update(fn(state) {
    AppState(..state, transport: Some(Http), connection: Connected)
  })
}

pub fn command(operation: String, body: Json) -> Promise(Result(Nil, String)) {
  case current().pending {
    Some(_) -> promise.resolve(Error("Une synchronisation est déjà en cours"))
    None -> {
      let request_id = make_request_id()
      let json =
        json.object([
          #("v", json.int(1)),
          #("id", json.string(request_id)),
          #("op", json.string(operation)),
          #("body", body),
        ])
        |> json.to_string
      let endpoint = store.get_state().http_endpoint
      change(fn(link) { Link(..link, pending: Some(operation)) })
      store.update(fn(state) { AppState(..state, busy: True, error: None) })
      use text <- promise.await(case endpoint {
        Some(endpoint) -> {
          use sent <- promise.await(platform.http_post(endpoint, json))
          case sent, web() {
            Ok(text), _ -> {
              connected_over_http()
              promise.resolve(Ok(text))
            }
            Error(reason), True -> promise.resolve(Error(reason))
            Error(_), False -> {
              stop_event_stream()
              platform.storage_remove(endpoint_storage_key)
              store.update(fn(state) { AppState(..state, http_endpoint: None) })
              ble_request(json)
            }
          }
        }
        None -> ble_request(json)
      })
      let handled = result.try(text, handle_response(operation, request_id, _))
      case handled {
        Ok(Nil) -> {
          case operation {
            "state.get" | "session.get" -> Nil
            _ -> change(fn(link) { Link(..link, refresh_pending: True) })
          }
          finish_command()
        }
        Error(reason) -> {
          finish_command()
          store.update(fn(state) { AppState(..state, error: Some(reason)) })
        }
      }
      promise.resolve(handled)
    }
  }
}

pub fn refresh() -> Promise(Result(Nil, String)) {
  case current().pending {
    Some(_) -> promise.resolve(Ok(Nil))
    None -> command("state.get", json.object([]))
  }
}

fn drain_event_refresh() -> Nil {
  let link = current()
  case link.refresh_pending, link.pending {
    True, None -> {
      change(fn(link) { Link(..link, refresh_pending: False) })
      refresh()
      Nil
    }
    _, _ -> Nil
  }
}

fn request_event_refresh() -> Nil {
  change(fn(link) { Link(..link, refresh_pending: True) })
  drain_event_refresh()
}

// Event stream ----------------------------------------------------------------

fn clear_event_retry() -> Nil {
  case current().retry_timer {
    Some(timer) -> platform.clear_timeout(timer)
    None -> Nil
  }
  change(fn(link) { Link(..link, retry_timer: None) })
}

pub fn stop_event_stream() -> Nil {
  change(fn(link) { Link(..link, generation: link.generation + 1) })
  clear_event_retry()
  case current().stream {
    Some(stream) -> platform.close_stream(stream)
    None -> Nil
  }
  change(fn(link) { Link(..link, stream: None) })
}

fn event_stream_active() -> Bool {
  web() || platform.app_active()
}

fn handle_event(event: ServerEvent) -> Nil {
  case event.id, event.event {
    Some(id), name if name != "ready" ->
      change(fn(link) { Link(..link, last_id: Some(id)) })
    _, _ -> Nil
  }
  case event.event {
    "ready" -> {
      change(fn(link) { Link(..link, retry_delay: 1000) })
      connected_over_http()
    }
    "state.changed" | "session.changed" | "breathing.changed" ->
      case json.parse(event.data, decode.at(["v"], decode.int)) {
        Ok(1) -> request_event_refresh()
        _ -> Nil
      }
    _ -> Nil
  }
}

fn schedule_event_reconnect(command_endpoint: String, generation: Int) -> Nil {
  case generation == current().generation && event_stream_active() {
    False -> Nil
    True -> {
      let delay = current().retry_delay
      change(fn(link) { Link(..link, retry_delay: int.min(15_000, delay * 2)) })
      clear_event_retry()
      let timer =
        platform.set_timeout(delay, fn() {
          change(fn(link) { Link(..link, retry_timer: None) })
          case generation == current().generation {
            True -> start_event_stream(command_endpoint)
            False -> Nil
          }
        })
      change(fn(link) { Link(..link, retry_timer: Some(timer)) })
    }
  }
}

pub fn start_event_stream(command_endpoint: String) -> Nil {
  case string.trim(command_endpoint) != "" && event_stream_active() {
    False -> Nil
    True ->
      case sse.events_endpoint(command_endpoint) {
        Error(_) -> Nil
        Ok(next_endpoint) -> {
          let same_endpoint = Some(next_endpoint) == current().endpoint
          stop_event_stream()
          change(fn(link) {
            Link(
              ..link,
              last_id: case same_endpoint {
                True -> link.last_id
                False -> None
              },
              endpoint: Some(next_endpoint),
              buffer: "",
            )
          })
          let generation = current().generation
          let live = fn() { generation == current().generation }
          let stream =
            platform.open_stream(
              next_endpoint,
              option.unwrap(current().last_id, ""),
              fn() {
                case live() {
                  True -> {
                    connected_over_http()
                    change(fn(link) { Link(..link, retry_delay: 1000) })
                  }
                  False -> Nil
                }
              },
              fn(chunk) {
                case live() {
                  True -> {
                    let #(buffer, events) =
                      sse.consume_chunk(current().buffer, chunk)
                    change(fn(link) { Link(..link, buffer:) })
                    list.each(events, handle_event)
                  }
                  False -> Nil
                }
              },
              fn(aborted) {
                case live() && !aborted {
                  True -> {
                    change(fn(link) { Link(..link, stream: None) })
                    schedule_event_reconnect(command_endpoint, generation)
                  }
                  False -> Nil
                }
              },
            )
          change(fn(link) { Link(..link, stream: Some(stream)) })
        }
      }
  }
}

fn install_app_state_listener() -> Nil {
  case web() {
    True -> Nil
    False -> {
      case current().app_state {
        Some(remove) -> remove()
        None -> Nil
      }
      let remove =
        platform.on_app_state(fn(active) {
          case active, store.get_state().http_endpoint {
            True, Some(endpoint) -> {
              start_event_stream(endpoint)
              refresh()
              Nil
            }
            True, None -> Nil
            False, _ -> stop_event_stream()
          }
        })
      change(fn(link) { Link(..link, app_state: Some(remove)) })
    }
  }
}

// Bluetooth discovery ---------------------------------------------------------

fn connect_device(device: Device) -> Nil {
  platform.ble_stop_scan()
  store.update(fn(state) { AppState(..state, connection: Connecting) })
  {
    use connected <- promise.map(platform.ble_connect(device))
    case connected {
      Ok(ready) -> {
        change(fn(link) { Link(..link, device: Some(ready)) })
        store.update(fn(state) {
          AppState(..state, connection: Connected, transport: Some(Bluetooth))
        })
        refresh()
        Nil
      }
      Error(reason) -> {
        change(fn(link) { Link(..link, device: None) })
        store.update(fn(state) {
          AppState(..state, connection: Disconnected, error: Some(reason))
        })
      }
    }
  }
  Nil
}

fn stop_state_listener() -> Nil {
  case current().bluetooth_state {
    Some(remove) -> remove()
    None -> Nil
  }
  change(fn(link) { Link(..link, bluetooth_state: None) })
}

fn begin_scan() -> Nil {
  stop_state_listener()
  platform.ble_stop_scan()
  platform.ble_scan(protocol.service_uuid, connect_device, fn(reason) {
    store.update(fn(state) {
      AppState(..state, connection: Disconnected, error: Some(reason))
    })
  })
}

fn disconnected(error: Option(String)) -> Nil {
  store.update(fn(state) { AppState(..state, connection: Disconnected, error:) })
}

pub fn scan() -> Nil {
  case web() {
    True -> Nil
    False -> {
      store.update(fn(state) {
        AppState(..state, connection: Scanning, error: None)
      })
      platform.ble_stop_scan()
      stop_state_listener()
      let remove =
        platform.ble_on_state(fn(adapter) {
          case adapter {
            "PoweredOn" -> begin_scan()
            "Unauthorized" -> {
              stop_state_listener()
              disconnected(Some(
                "Autorisez le Bluetooth dans Réglages pour joindre le réveil.",
              ))
            }
            "Unsupported" -> {
              stop_state_listener()
              disconnected(None)
            }
            "PoweredOff" -> disconnected(None)
            _ -> Nil
          }
        })
      change(fn(link) { Link(..link, bluetooth_state: Some(remove)) })
    }
  }
}

fn load_endpoint() -> Promise(Option(String)) {
  use stored <- promise.map(platform.storage_get(endpoint_storage_key))
  case stored {
    Ok(endpoint) ->
      case string.trim(endpoint) {
        "" -> legacy_endpoint()
        _ -> Some(endpoint)
      }
    Error(Nil) -> legacy_endpoint()
  }
}

fn legacy_endpoint() -> Option(String) {
  case platform.legacy_setting(endpoint_storage_key) {
    Ok(endpoint) ->
      case string.trim(endpoint) {
        "" -> None
        _ -> {
          platform.storage_set(endpoint_storage_key, endpoint)
          Some(endpoint)
        }
      }
    Error(Nil) -> None
  }
}

fn use_web_endpoint() -> Promise(Result(Nil, String)) {
  store.update(fn(state) {
    AppState(
      ..state,
      http_endpoint: Some(web_command_endpoint),
      transport: Some(Http),
      connection: Connecting,
    )
  })
  start_event_stream(web_command_endpoint)
  refresh()
}

pub fn start() -> Nil {
  install_app_state_listener()
  case web() {
    True -> {
      use_web_endpoint()
      Nil
    }
    False -> {
      {
        use endpoint <- promise.map(load_endpoint())
        case endpoint {
          Some(endpoint) -> {
            store.update(fn(state) {
              AppState(..state, http_endpoint: Some(endpoint))
            })
            start_event_stream(endpoint)
            promise.tap(refresh(), fn(refreshed) {
              case refreshed {
                Ok(Nil) -> Nil
                Error(_) -> scan()
              }
            })
            Nil
          }
          None -> scan()
        }
      }
      Nil
    }
  }
}

pub fn reconnect() -> Nil {
  case web() {
    True -> {
      use_web_endpoint()
      Nil
    }
    False -> {
      stop_event_stream()
      change(fn(link) { Link(..link, device: None) })
      scan()
    }
  }
}
