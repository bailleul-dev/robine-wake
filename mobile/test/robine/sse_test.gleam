import gleam/option.{None, Some}
import robine/sse.{ServerEvent}

pub fn derives_events_endpoint_test() {
  assert sse.events_endpoint("/api/v1/command") == Ok("/api/v1/events")
  assert sse.events_endpoint("http://robine.local:4000/api/v1/command")
    == Ok("http://robine.local:4000/api/v1/events")
  assert sse.events_endpoint(
      "http://robine.local:4000/api/v1/command?ignored=true",
    )
    == Ok("http://robine.local:4000/api/v1/events")
  assert sse.events_endpoint("http://robine.local:4000/state")
    == Error("Adresse Wi-Fi du réveil invalide")
}

pub fn parses_frames_across_network_chunks_test() {
  let #(buffer, first) =
    sse.consume_chunk("", "id: 41\r\nevent: state.changed\r\nda")
  let #(rest, second) =
    sse.consume_chunk(
      buffer,
      "ta: {\"event\":\"state.changed\"}\r\n\r\n: keep-alive\r\n\r\n",
    )
  assert first == []
  assert second
    == [
      ServerEvent(
        id: Some("41"),
        event: "state.changed",
        data: "{\"event\":\"state.changed\"}",
      ),
    ]
  assert rest == ""
}

pub fn joins_multiple_data_lines_test() {
  assert sse.parse_frame("data: hello\ndata: world")
    == Some(ServerEvent(id: None, event: "message", data: "hello\nworld"))
}

pub fn preserves_a_crlf_split_between_chunks_test() {
  let #(buffer, first) = sse.consume_chunk("", "id: 9\r")
  let #(_, second) =
    sse.consume_chunk(buffer, "\nevent: session.changed\r\ndata: {}\r\n\r\n")
  assert first == []
  assert second
    == [ServerEvent(id: Some("9"), event: "session.changed", data: "{}")]
}
