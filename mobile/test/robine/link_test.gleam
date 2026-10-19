import gleam/list
import gleam/option.{None, Some}
import gleam/string
import robine/command
import robine/link.{
  type Effect, type Link, type Msg, Browser, Phone, Post, Settle, Write,
}

const clock = "http://192.168.1.3:4000/api/v1/command"

const events = "http://192.168.1.3:4000/api/v1/events"

fn run(
  link: Link(String),
  msgs: List(Msg(String)),
) -> #(Link(String), List(Effect(String))) {
  list.fold(msgs, #(link, []), fn(step, msg) {
    let #(link, effects) = link.update(step.0, msg)
    #(link, list.append(step.1, effects))
  })
}

fn phone() -> Link(String) {
  link.new(Phone(foreground: True), "seed")
}

fn state_reply(id: String, endpoints: List(String)) -> String {
  "{\"v\":1,\"id\":\""
  <> id
  <> "\",\"status\":\"ok\",\"body\":{\"transport\":{\"http_endpoints\":["
  <> endpoints |> list.map(fn(url) { "\"" <> url <> "\"" }) |> string.join(",")
  <> "]}}}"
}

fn ok(id: String) -> String {
  "{\"v\":1,\"id\":\"" <> id <> "\",\"status\":\"ok\",\"body\":{}}"
}

fn posted(effects: List(Effect(String))) -> List(String) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Post(id:, ..) | Write(id:, ..) -> Ok(id)
      _ -> Error(Nil)
    }
  })
}

pub fn a_stored_endpoint_is_tried_over_wifi_with_its_events_test() {
  let #(link, effects) = link.update(phone(), link.Started(Some(clock)))
  assert effects
    == [
      link.OpenStream(epoch: 1, url: events, last_id: None),
      Post(
        id: "seed-0",
        url: clock,
        line: command.encode(command.GetState, "seed-0"),
      ),
    ]
  assert link.connection(link) == link.Joining
  assert link.busy(link)
  let #(link, effects) =
    link.update(
      link,
      link.WifiAnswered("seed-0", Ok(state_reply("seed-0", [clock]))),
    )
  assert link.connection(link) == link.Online(link.Wifi)
  assert !link.busy(link)
  let assert [Settle("seed-0", Ok(command.StateReply(_)))] = effects
}

pub fn without_an_endpoint_the_phone_scans_and_pairs_test() {
  let #(link, effects) = link.update(phone(), link.Started(None))
  assert effects == [link.StopScan, link.WatchAdapter]
  assert link.connection(link) == link.Searching
  let #(link, effects) =
    run(link, [
      link.AdapterChanged(link.PoweredOn),
      link.DeviceFound("clock"),
      link.DeviceFound("other clock"),
    ])
  assert effects
    == [
      link.UnwatchAdapter,
      link.StartScan,
      link.StopScan,
      link.Connect("clock"),
    ]
  assert link.connection(link) == link.Joining
  let #(link, effects) = link.update(link, link.DeviceConnected(Ok("clock")))
  assert link.connection(link) == link.Online(link.Nearby)
  assert posted(effects) == ["seed-0"]
  // The clock tells its Wi-Fi endpoint: kept, and its events followed.
  let #(link, effects) =
    link.update(
      link,
      link.RadioAnswered("seed-0", Ok(state_reply("seed-0", [clock]))),
    )
  let assert [
    link.SaveEndpoint(saved),
    link.OpenStream(epoch: 1, ..),
    Settle("seed-0", Ok(_)),
  ] = effects
  assert saved == clock
  // Bluetooth still answers until the clock is reached over Wi-Fi.
  assert link.connection(link) == link.Online(link.Nearby)
  let #(link, _) = link.update(link, link.StreamOpened(1))
  assert link.connection(link) == link.Online(link.Wifi)
}

pub fn bluetooth_takes_over_when_wifi_fails_on_the_phone_test() {
  let #(link, _) =
    run(phone(), [
      link.Started(None),
      link.AdapterChanged(link.PoweredOn),
      link.DeviceFound("clock"),
      link.DeviceConnected(Ok("clock")),
      link.RadioAnswered("seed-0", Ok(state_reply("seed-0", [clock]))),
    ])
  let #(link, effects) = link.update(link, link.Send(command.CancelNap))
  assert posted(effects) == ["seed-1"]
  let #(link, effects) =
    link.update(link, link.WifiAnswered("seed-1", Error("offline")))
  let line = command.encode(command.CancelNap, "seed-1")
  assert effects
    == [link.CloseStream, link.ForgetEndpoint, Write("seed-1", "clock", line)]
  assert link.endpoint(link) == None
  // Once done, the change is read back.
  let #(_, effects) =
    link.update(link, link.RadioAnswered("seed-1", Ok(ok("seed-1"))))
  let assert [Settle("seed-1", Ok(command.Done)), Write(id: "seed-2", ..)] =
    effects
}

pub fn one_command_at_a_time_test() {
  let #(link, _) = link.update(phone(), link.Started(Some(clock)))
  assert link.next_id(link) == "seed-1"
  let #(link, effects) = link.update(link, link.Send(command.CancelNap))
  assert effects == [Settle("seed-1", Error(command.Busy))]
  // A refresh asked meanwhile waits for the command on its way.
  let #(link, effects) = link.update(link, link.Refresh)
  assert effects == [Settle("seed-2", Ok(command.Done))]
  let #(_, effects) =
    link.update(
      link,
      link.WifiAnswered("seed-0", Ok(state_reply("seed-0", []))),
    )
  assert posted(effects) == ["seed-3"]
}

pub fn failures_show_only_for_what_the_user_did_test() {
  let browser = link.new(Browser, "seed")
  let #(link, effects) = link.update(browser, link.Started(None))
  assert posted(effects) == ["seed-0"]
  let #(link, effects) =
    link.update(link, link.WifiAnswered("seed-0", Error("offline")))
  assert effects == [Settle("seed-0", Error(command.Unreachable("offline")))]
  let #(link, _) = link.update(link, link.Send(command.ConfirmClock))
  let #(_, effects) =
    link.update(link, link.WifiAnswered("seed-1", Error("offline")))
  assert effects
    == [
      Settle("seed-1", Error(command.Unreachable("offline"))),
      link.Report(command.Unreachable("offline")),
    ]
}

pub fn the_answer_of_another_request_is_ignored_test() {
  let #(link, _) = link.update(phone(), link.Started(Some(clock)))
  let #(after, effects) =
    link.update(link, link.WifiAnswered("old", Ok(state_reply("old", []))))
  assert effects == []
  assert after == link
}

pub fn events_ask_for_a_refresh_and_resume_after_their_last_id_test() {
  let #(link, _) =
    run(phone(), [
      link.Started(Some(clock)),
      link.WifiAnswered("seed-0", Ok(state_reply("seed-0", [clock]))),
      link.StreamOpened(1),
    ])
  let #(link, effects) =
    link.update(
      link,
      link.StreamChunk(1, "id: 41\nevent: state.changed\ndata: {\"v\":1}\n\n"),
    )
  assert posted(effects) == ["seed-1"]
  // A stream dropped waits a second, then two, and resumes after event 41.
  let #(link, effects) = link.update(link, link.StreamEnded(1, aborted: False))
  assert effects == [link.WaitToRetry(epoch: 1, delay: 1000)]
  assert link.connection(link) == link.Joining
  let #(link, effects) = link.update(link, link.RetryElapsed(1))
  assert effects
    == [link.OpenStream(epoch: 2, url: events, last_id: Some("41"))]
  let #(link, effects) = link.update(link, link.StreamEnded(2, aborted: False))
  assert effects == [link.WaitToRetry(epoch: 2, delay: 2000)]
  // Callbacks of an earlier stream change nothing.
  let #(_, effects) =
    link.update(
      link,
      link.StreamChunk(1, "event: state.changed\ndata: {\"v\":1}\n\n"),
    )
  assert effects == []
}

pub fn the_background_closes_the_stream_and_the_foreground_refreshes_test() {
  let #(link, _) =
    run(phone(), [
      link.Started(Some(clock)),
      link.WifiAnswered("seed-0", Ok(state_reply("seed-0", [clock]))),
    ])
  let #(link, effects) = link.update(link, link.ForegroundChanged(False))
  assert effects == [link.CloseStream]
  let #(_, effects) = link.update(link, link.ForegroundChanged(True))
  let assert [link.OpenStream(epoch: 2, ..), Post(id: "seed-1", ..)] = effects
}

pub fn denied_bluetooth_is_reported_test() {
  let #(link, effects) =
    run(phone(), [link.Started(None), link.AdapterChanged(link.Unauthorized)])
  assert list.contains(effects, link.Report(command.BluetoothDenied))
  assert link.connection(link) == link.Offline
}

pub fn a_refresh_due_while_busy_follows_the_command_test() {
  let #(link, _) =
    run(phone(), [
      link.Started(Some(clock)),
      link.WifiAnswered("seed-0", Ok(state_reply("seed-0", [clock]))),
      link.Send(command.CancelNap),
      link.ForegroundChanged(False),
      link.ForegroundChanged(True),
    ])
  let #(_, effects) =
    link.update(link, link.WifiAnswered("seed-1", Ok(ok("seed-1"))))
  assert posted(effects) == ["seed-3"]
}
