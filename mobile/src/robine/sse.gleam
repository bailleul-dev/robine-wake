//// Server-sent events of `/api/v1/events`, parsed across network chunks.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub const command_path = "/api/v1/command"

pub const events_path = "/api/v1/events"

pub type ServerEvent {
  ServerEvent(id: Option(String), event: String, data: String)
}

pub fn events_endpoint(command_endpoint: String) -> Result(String, String) {
  let endpoint = case string.split_once(command_endpoint, "?") {
    Ok(#(endpoint, _)) -> endpoint
    Error(Nil) -> command_endpoint
  }
  case string.ends_with(endpoint, command_path) {
    True ->
      Ok(string.drop_end(endpoint, string.length(command_path)) <> events_path)
    False -> Error("Adresse Wi-Fi du réveil invalide")
  }
}

pub fn parse_frame(frame: String) -> Option(ServerEvent) {
  let #(id, event, data) =
    frame
    |> string.split("\n")
    |> list.fold(#(None, "message", []), fn(parsed, line) {
      let #(id, event, data) = parsed
      case string.trim(line) == "" || string.starts_with(line, ":") {
        True -> parsed
        False -> {
          let #(field, value) = case string.split_once(line, ":") {
            Ok(#(field, value)) -> #(field, drop_space(value))
            Error(Nil) -> #(line, "")
          }
          case field {
            "event" ->
              case string.trim(value) {
                "" -> #(id, "message", data)
                _ -> #(id, value, data)
              }
            "data" -> #(id, event, [value, ..data])
            "id" ->
              case string.contains(value, "\u{0000}") {
                True -> parsed
                False -> #(Some(value), event, data)
              }
            _ -> parsed
          }
        }
      }
    })
  case data {
    [] -> None
    _ ->
      Some(ServerEvent(
        id:,
        event:,
        data: data |> list.reverse |> string.join("\n"),
      ))
  }
}

fn drop_space(value: String) -> String {
  case value {
    " " <> rest -> rest
    _ -> value
  }
}

/// Appends a chunk to the pending text; returns what remains and the
/// complete events.
pub fn consume_chunk(
  buffer: String,
  chunk: String,
) -> #(String, List(ServerEvent)) {
  let combined = buffer <> chunk
  let trailing_carriage_return = string.ends_with(combined, "\r")
  let complete = case trailing_carriage_return {
    True -> string.drop_end(combined, 1)
    False -> combined
  }
  let normalized =
    complete
    |> string.replace("\r\n", "\n")
    |> string.replace("\r", "\n")
  let remaining = case trailing_carriage_return {
    True -> normalized <> "\r"
    False -> normalized
  }
  frames(remaining, [])
}

fn frames(
  remaining: String,
  events: List(ServerEvent),
) -> #(String, List(ServerEvent)) {
  case string.split_once(remaining, "\n\n") {
    Ok(#(frame, rest)) ->
      case parse_frame(frame) {
        Some(event) -> frames(rest, [event, ..events])
        None -> frames(rest, events)
      }
    Error(Nil) -> #(remaining, list.reverse(events))
  }
}
