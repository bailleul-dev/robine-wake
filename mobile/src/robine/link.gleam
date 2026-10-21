//// The way to the clock: Wi-Fi or Bluetooth, the event stream that tells when
//// to refresh, and the single command on its way.
////
//// Everything here is pure. `update` takes what happened and returns the next
//// link with the effects to perform, which `transport` carries out and turns
//// back into messages. Each event stream gets a new epoch, so the callbacks
//// of a stream closed since are recognised and ignored.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import robine/command.{type Command, type Failure, type Reply}
import robine/sse.{type ServerEvent}

pub const web_endpoint = "/api/v1/command"

const first_backoff = 1000

const last_backoff = 15_000

pub type Link(device) {
  Link(
    host: Host,
    wifi: Wifi,
    radio: Radio(device),
    events: Option(Events),
    request: Option(Request),
    /// The clock changed since the last `state.get`.
    stale: Bool,
    epoch: Int,
    /// Request ids are the seed and a count, unique across launches.
    seed: String,
    sent: Int,
  )
}

/// Where the app runs. The web app is served by the clock itself.
pub type Host {
  Browser
  Phone(foreground: Bool)
}

pub type Wifi {
  NoEndpoint
  /// `reached` once the clock answered there.
  Endpoint(url: String, reached: Bool)
}

pub type Radio(device) {
  /// Not looking for the clock over Bluetooth.
  Idle
  AwaitingAdapter(powered_off: Bool)
  Scanning
  Pairing
  Paired(device)
  /// Bluetooth is denied, missing or failed: only a new attempt changes that.
  Unavailable
}

/// The server-sent events of the clock, resumed after the last id received.
pub type Events {
  Events(url: String, last_id: Option(String), stream: Stream)
}

pub type Stream {
  Stopped
  /// `backoff` is the wait before reopening it if it drops.
  Open(epoch: Int, buffer: String, backoff: Int)
  Retrying(epoch: Int, backoff: Int)
}

pub type Request {
  Request(id: String, command: Command, line: String, origin: Origin, via: Via)
}

/// Who asked: failures are only shown for what the user did.
pub type Origin {
  User
  Automatic
}

pub type Via {
  ViaWifi
  ViaRadio
}

pub type Adapter {
  PoweredOn
  PoweredOff
  Unauthorized
  Unsupported
  Transitioning
}

pub type Msg(device) {
  /// The endpoint kept from the last launch, if any.
  Started(stored: Option(String))
  Send(Command)
  /// Sent on the app's own initiative: its failures are not reported.
  Read(Command)
  Refresh
  Reconnect
  WifiAnswered(id: String, result: Result(String, String))
  RadioAnswered(id: String, result: Result(String, String))
  StreamOpened(epoch: Int)
  StreamChunk(epoch: Int, chunk: String)
  StreamEnded(epoch: Int, aborted: Bool)
  RetryElapsed(epoch: Int)
  ForegroundChanged(foreground: Bool)
  AdapterChanged(Adapter)
  DeviceFound(device)
  DeviceConnected(Result(device, String))
  ScanFailed(reason: String)
}

pub type Effect(device) {
  Post(id: String, url: String, line: String)
  Write(id: String, device: device, line: String)
  OpenStream(epoch: Int, url: String, last_id: Option(String))
  CloseStream
  WaitToRetry(epoch: Int, delay: Int)
  CancelRetry
  SaveEndpoint(url: String)
  /// Replaces any adapter listener.
  WatchAdapter
  UnwatchAdapter
  StartScan
  StopScan
  Connect(device)
  /// The outcome of a request, the next id `next_id` gave.
  Settle(id: String, result: Result(Reply, Failure))
  Report(Failure)
  ClearReport
}

/// What the screens show of the link.
pub type Connection {
  Searching
  Joining
  Online(Channel)
  Offline
}

pub type Channel {
  Wifi
  Nearby
}

pub fn new(host: Host, seed: String) -> Link(device) {
  Link(
    host:,
    wifi: NoEndpoint,
    radio: Idle,
    events: None,
    request: None,
    stale: False,
    epoch: 0,
    seed:,
    sent: 0,
  )
}

/// The id of the next request, so a caller can wait for its `Settle`.
pub fn next_id(link: Link(device)) -> String {
  link.seed <> "-" <> int.to_string(link.sent)
}

pub fn busy(link: Link(device)) -> Bool {
  option.is_some(link.request)
}

pub fn endpoint(link: Link(device)) -> Option(String) {
  case link.wifi {
    Endpoint(url:, ..) -> Some(url)
    NoEndpoint -> None
  }
}

pub fn connection(link: Link(device)) -> Connection {
  case link.wifi, link.radio {
    Endpoint(reached: True, ..), _ -> Online(Wifi)
    _, Paired(_) -> Online(Nearby)
    Endpoint(reached: False, ..), _ | NoEndpoint, Pairing -> Joining
    NoEndpoint, Idle | NoEndpoint, Scanning -> Searching
    NoEndpoint, AwaitingAdapter(powered_off:) ->
      case powered_off {
        True -> Offline
        False -> Searching
      }
    NoEndpoint, Unavailable -> Offline
  }
}

// Steps -----------------------------------------------------------------------

type Step(device) =
  #(Link(device), List(Effect(device)))

fn done(link: Link(device)) -> Step(device) {
  #(link, [])
}

fn emit(link: Link(device), effects: List(Effect(device))) -> Step(device) {
  #(link, effects)
}

fn then(
  step: Step(device),
  next: fn(Link(device)) -> Step(device),
) -> Step(device) {
  let #(link, effects) = step
  let #(link, more) = next(link)
  #(link, list.append(effects, more))
}

pub fn update(link: Link(device), msg: Msg(device)) -> Step(device) {
  case msg {
    Started(stored:) ->
      case link.host, stored {
        Browser, _ -> join(link, web_endpoint)
        Phone(_), Some(url) -> join(link, url)
        Phone(_), None -> scan(link)
      }
    Send(command) -> send(link, command, User)
    Read(command) -> send(link, command, Automatic)
    Refresh ->
      case link.request {
        Some(_) ->
          emit(mark_stale(link), [Settle(next_id(link), Ok(command.Done))])
          |> skip_id
        None -> send(link, command.GetState, User)
      }
    Reconnect ->
      case link.host, link.wifi {
        Browser, _ -> join(link, web_endpoint)
        Phone(_), NoEndpoint -> scan(link)
        Phone(_), Endpoint(url:, ..) -> scan(link) |> then(join(_, url))
      }
    WifiAnswered(id:, result:) ->
      case link.request {
        Some(Request(via: ViaWifi, ..) as request) if request.id == id ->
          wifi_answered(link, request, result)
        _ -> done(link)
      }
    RadioAnswered(id:, result:) ->
      case link.request, result {
        Some(Request(via: ViaRadio, ..) as request), Ok(text)
          if request.id == id
        -> answered(link, request, text)
        Some(Request(via: ViaRadio, ..) as request), Error(reason)
          if request.id == id
        -> finish(link, request, Error(command.Unreachable(reason)))
        _, _ -> done(link)
      }
    StreamOpened(epoch:) ->
      case link.events {
        Some(Events(stream: Open(epoch: current, buffer:, ..), ..) as events)
          if current == epoch
        ->
          done(
            Link(
              ..link,
              wifi: reached(link.wifi),
              events: Some(
                Events(
                  ..events,
                  stream: Open(epoch:, buffer:, backoff: first_backoff),
                ),
              ),
            ),
          )
        _ -> done(link)
      }
    StreamChunk(epoch:, chunk:) ->
      case link.events {
        Some(
          Events(stream: Open(epoch: current, buffer:, backoff:), ..) as events,
        )
          if current == epoch
        -> {
          let #(buffer, received) = sse.consume_chunk(buffer, chunk)
          let events = Events(..events, stream: Open(epoch:, buffer:, backoff:))
          list.fold(received, Link(..link, events: Some(events)), handle_event)
          |> drain
        }
        _ -> done(link)
      }
    StreamEnded(epoch:, aborted:) ->
      case link.events {
        Some(Events(stream: Open(epoch: current, backoff:, ..), ..) as events)
          if current == epoch && !aborted
        -> {
          let link = Link(..link, wifi: unreached(link.wifi))
          case active(link) {
            True ->
              emit(
                Link(
                  ..link,
                  events: Some(
                    Events(
                      ..events,
                      stream: Retrying(
                        epoch:,
                        backoff: int.min(last_backoff, backoff * 2),
                      ),
                    ),
                  ),
                ),
                [WaitToRetry(epoch:, delay: backoff)],
              )
            False ->
              done(
                Link(..link, events: Some(Events(..events, stream: Stopped))),
              )
          }
        }
        _ -> done(link)
      }
    RetryElapsed(epoch:) ->
      case link.events {
        Some(Events(stream: Retrying(epoch: current, backoff:), ..) as events)
          if current == epoch
        -> open(link, events, backoff)
        _ -> done(link)
      }
    ForegroundChanged(foreground:) ->
      case link.host, foreground {
        Browser, _ -> done(link)
        Phone(_), True -> {
          let link = Link(..link, host: Phone(foreground: True))
          case link.wifi {
            Endpoint(..) ->
              start_events(link) |> then(send(_, command.GetState, Automatic))
            NoEndpoint -> done(link)
          }
        }
        Phone(_), False ->
          stop_events(Link(..link, host: Phone(foreground: False)))
      }
    AdapterChanged(adapter) ->
      case link.radio, adapter {
        AwaitingAdapter(_), PoweredOn ->
          emit(Link(..link, radio: Scanning), [UnwatchAdapter, StartScan])
        AwaitingAdapter(_), PoweredOff ->
          done(Link(..link, radio: AwaitingAdapter(powered_off: True)))
        AwaitingAdapter(_), Unauthorized ->
          emit(Link(..link, radio: Unavailable), [
            UnwatchAdapter,
            Report(command.BluetoothDenied),
          ])
        AwaitingAdapter(_), Unsupported ->
          emit(Link(..link, radio: Unavailable), [UnwatchAdapter])
        _, _ -> done(link)
      }
    DeviceFound(device) ->
      case link.radio {
        Scanning ->
          emit(Link(..link, radio: Pairing), [StopScan, Connect(device)])
        _ -> done(link)
      }
    DeviceConnected(result) ->
      case link.radio, result {
        Pairing, Ok(device) ->
          send(Link(..link, radio: Paired(device)), command.GetState, Automatic)
        Pairing, Error(reason) ->
          emit(Link(..link, radio: Unavailable), [
            Report(command.BluetoothFailed(reason)),
          ])
        _, _ -> done(link)
      }
    ScanFailed(reason:) ->
      case link.radio {
        Scanning ->
          emit(Link(..link, radio: Unavailable), [
            Report(command.BluetoothFailed(reason)),
          ])
        _ -> done(link)
      }
  }
}

/// Consumes the id `next_id` announced without sending anything.
fn skip_id(step: Step(device)) -> Step(device) {
  let #(link, effects) = step
  #(Link(..link, sent: link.sent + 1), effects)
}

fn mark_stale(link: Link(device)) -> Link(device) {
  Link(..link, stale: True)
}

fn active(link: Link(device)) -> Bool {
  case link.host {
    Browser -> True
    Phone(foreground:) -> foreground
  }
}

fn reached(wifi: Wifi) -> Wifi {
  case wifi {
    Endpoint(url:, ..) -> Endpoint(url:, reached: True)
    NoEndpoint -> NoEndpoint
  }
}

fn unreached(wifi: Wifi) -> Wifi {
  case wifi {
    Endpoint(url:, ..) -> Endpoint(url:, reached: False)
    NoEndpoint -> NoEndpoint
  }
}

/// Tries the clock over Wi-Fi at this endpoint.
fn join(link: Link(device), url: String) -> Step(device) {
  let wifi = case link.wifi {
    Endpoint(url: current, ..) as wifi if current == url -> wifi
    _ -> Endpoint(url:, reached: False)
  }
  Link(..link, wifi:)
  |> start_events
  |> then(send(_, command.GetState, Automatic))
}

/// Looks for the clock over Bluetooth, on the phone.
fn scan(link: Link(device)) -> Step(device) {
  case link.host {
    Browser -> done(link)
    Phone(_) ->
      emit(Link(..link, radio: AwaitingAdapter(powered_off: False)), [
        StopScan,
        WatchAdapter,
      ])
  }
}

// Requests --------------------------------------------------------------------

fn send(link: Link(device), command: Command, origin: Origin) -> Step(device) {
  let id = next_id(link)
  let link = Link(..link, sent: link.sent + 1)
  case link.request {
    // Only refreshes are automatic: one follows the command on its way.
    Some(_) ->
      case origin {
        User -> emit(link, [Settle(id, Error(command.Busy))])
        Automatic -> emit(mark_stale(link), [Settle(id, Error(command.Busy))])
      }
    None -> {
      let line = command.encode(command, id)
      let request = fn(via) {
        Some(Request(id:, command:, line:, origin:, via:))
      }
      let clear = case origin {
        User -> [ClearReport]
        Automatic -> []
      }
      case link.wifi, link.radio {
        // Away from the clock's network, Bluetooth answers without waiting
        // for Wi-Fi to fail again.
        Endpoint(reached: False, ..), Paired(device) ->
          emit(Link(..link, request: request(ViaRadio)), [
            Write(id:, device:, line:),
            ..clear
          ])
        Endpoint(url:, ..), _ ->
          emit(Link(..link, request: request(ViaWifi)), [
            Post(id:, url:, line:),
            ..clear
          ])
        NoEndpoint, Paired(device) ->
          emit(Link(..link, request: request(ViaRadio)), [
            Write(id:, device:, line:),
            ..clear
          ])
        NoEndpoint, _ ->
          emit(link, [
            Settle(id, Error(command.NoRoute)),
            ..report(origin, command.NoRoute)
          ])
      }
    }
  }
}

fn report(origin: Origin, failure: Failure) -> List(Effect(device)) {
  case origin {
    User -> [Report(failure)]
    Automatic -> []
  }
}

fn wifi_answered(
  link: Link(device),
  request: Request,
  result: Result(String, String),
) -> Step(device) {
  case result, link.host {
    Ok(text), _ ->
      answered(Link(..link, wifi: reached(link.wifi)), request, text)
    Error(reason), Browser ->
      finish(
        Link(..link, wifi: unreached(link.wifi)),
        request,
        Error(command.Unreachable(reason)),
      )
    // The phone may have left the clock's network: Bluetooth takes over. The
    // endpoint is kept, a single failure is no proof the clock moved.
    Error(reason), Phone(_) -> {
      let link = Link(..link, wifi: unreached(link.wifi))
      case link.radio {
        Paired(device) ->
          emit(Link(..link, request: Some(Request(..request, via: ViaRadio))), [
            Write(request.id, device, request.line),
          ])
        Idle ->
          finish(link, request, Error(command.Unreachable(reason)))
          |> then(scan)
        _ -> finish(link, request, Error(command.Unreachable(reason)))
      }
    }
  }
}

fn answered(
  link: Link(device),
  request: Request,
  text: String,
) -> Step(device) {
  case command.reply(request.command, request.id, text) {
    Ok(reply) -> {
      let link = case command.changes_state(request.command) {
        True -> mark_stale(link)
        False -> link
      }
      case reply {
        command.StateReply(snapshot) ->
          learn_endpoints(link, snapshot.http_endpoints)
        _ -> done(link)
      }
      |> then(finish(_, request, Ok(reply)))
    }
    Error(failure) -> finish(link, request, Error(failure))
  }
}

fn finish(
  link: Link(device),
  request: Request,
  result: Result(Reply, Failure),
) -> Step(device) {
  let failure = case result {
    Ok(_) -> []
    Error(failure) -> report(request.origin, failure)
  }
  emit(Link(..link, request: None), [Settle(request.id, result), ..failure])
  |> then(drain)
}

/// Refreshes once nothing else is on its way, if the clock changed.
fn drain(link: Link(device)) -> Step(device) {
  case link.stale, link.request {
    True, None -> send(Link(..link, stale: False), command.GetState, Automatic)
    _, _ -> done(link)
  }
}

/// The phone keeps the clock's first Wi-Fi endpoint for the next launch.
fn learn_endpoints(
  link: Link(device),
  endpoints: List(String),
) -> Step(device) {
  case link.host, endpoints, link.wifi {
    Browser, _, _ | Phone(_), [], _ -> done(link)
    Phone(_), [url, ..], Endpoint(url: current, ..) if current == url ->
      done(link)
    Phone(_), [url, ..], _ ->
      emit(Link(..link, wifi: Endpoint(url:, reached: False)), [
        SaveEndpoint(url),
      ])
      |> then(start_events)
  }
}

// Events ----------------------------------------------------------------------

fn start_events(link: Link(device)) -> Step(device) {
  case link.wifi, active(link) {
    Endpoint(url:, ..), True ->
      case sse.events_endpoint(url) {
        Ok(url) -> {
          let last_id = case link.events {
            Some(Events(url: current, last_id:, ..)) if current == url -> last_id
            _ -> None
          }
          let #(link, effects) = stop_events(link)
          let #(link, more) =
            open(link, Events(url:, last_id:, stream: Stopped), first_backoff)
          #(link, list.append(effects, more))
        }
        Error(_) -> done(link)
      }
    _, _ -> done(link)
  }
}

fn open(link: Link(device), events: Events, backoff: Int) -> Step(device) {
  let epoch = link.epoch + 1
  emit(
    Link(
      ..link,
      epoch:,
      events: Some(Events(..events, stream: Open(epoch:, buffer: "", backoff:))),
    ),
    [OpenStream(epoch:, url: events.url, last_id: events.last_id)],
  )
}

fn stop_events(link: Link(device)) -> Step(device) {
  case link.events {
    Some(Events(stream: Open(..), ..) as events) ->
      emit(Link(..link, events: Some(Events(..events, stream: Stopped))), [
        CloseStream,
      ])
    Some(Events(stream: Retrying(..), ..) as events) ->
      emit(Link(..link, events: Some(Events(..events, stream: Stopped))), [
        CancelRetry,
      ])
    _ -> done(link)
  }
}

fn handle_event(link: Link(device), event: ServerEvent) -> Link(device) {
  let link = case event.id, link.events {
    Some(id), Some(events) if event.event != "ready" ->
      Link(..link, events: Some(Events(..events, last_id: Some(id))))
    _, _ -> link
  }
  case event.event {
    "ready" ->
      Link(..link, wifi: reached(link.wifi), events: case link.events {
        Some(Events(stream: Open(epoch:, buffer:, ..), ..) as events) ->
          Some(
            Events(
              ..events,
              stream: Open(epoch:, buffer:, backoff: first_backoff),
            ),
          )
        events -> events
      })
    "state.changed" | "session.changed" | "breathing.changed" ->
      case json.parse(event.data, decode.at(["v"], decode.int)) {
        Ok(1) -> mark_stale(link)
        _ -> link
      }
    _ -> link
  }
}
