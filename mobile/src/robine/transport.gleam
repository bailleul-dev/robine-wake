//// Runs the link to the clock: performs the effects `link.update` asks for
//// with the phone's services, and turns what they report back into messages.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import robine/command.{type Command, type Failure, type Reply}
import robine/global.{type Ref}
import robine/link.{type Effect, type Link, type Msg}
import robine/native
import robine/platform.{type Device, type Stream, type Timer}
import robine/protocol
import robine/snapshot.{Snapshot}
import robine/store.{AppState}

pub const endpoint_storage_key = "robineWake.httpCommandEndpoint.v1"

type Runtime {
  Runtime(
    link: Link(Device),
    stream: Option(Stream),
    retry: Option(Timer),
    adapter: Option(fn() -> Nil),
    app_state: Option(fn() -> Nil),
    waiters: Dict(String, fn(Result(Reply, Failure)) -> Nil),
    /// Messages sent while an update runs wait their turn here.
    queue: List(Msg(Device)),
    running: Bool,
  )
}

fn host() -> link.Host {
  case native.web() {
    True -> link.Browser
    False -> link.Phone(foreground: platform.app_active())
  }
}

fn runtime() -> Ref(Runtime) {
  global.named("transport.runtime", fn() {
    Runtime(
      link: link.new(host(), make_seed()),
      stream: None,
      retry: None,
      adapter: None,
      app_state: None,
      waiters: dict.new(),
      queue: [],
      running: False,
    )
  })
}

fn current() -> Runtime {
  global.get(runtime())
}

fn change(update: fn(Runtime) -> Runtime) -> Nil {
  global.update(runtime(), update)
}

/// A random version 4 UUID.
fn make_seed() -> String {
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

// Dispatch --------------------------------------------------------------------

fn dispatch(msg: Msg(Device)) -> Nil {
  change(fn(runtime) {
    Runtime(..runtime, queue: list.append(runtime.queue, [msg]))
  })
  case current().running {
    True -> Nil
    False -> run()
  }
}

fn run() -> Nil {
  case current().queue {
    [] -> change(fn(runtime) { Runtime(..runtime, running: False) })
    [msg, ..rest] -> {
      let #(next, effects) = link.update(current().link, msg)
      change(fn(runtime) {
        Runtime(..runtime, link: next, queue: rest, running: True)
      })
      publish(next)
      list.each(effects, perform)
      run()
    }
  }
}

/// Shows the link in the app state when the screens would see a change.
fn publish(link: Link(Device)) -> Nil {
  let connection = link.connection(link)
  let endpoint = link.endpoint(link)
  let busy = link.busy(link)
  let state = store.get_state()
  case
    state.connection == connection
    && state.endpoint == endpoint
    && state.busy == busy
  {
    True -> Nil
    False ->
      store.update(fn(state) {
        AppState(..state, connection:, endpoint:, busy:)
      })
  }
}

fn perform(effect: Effect(Device)) -> Nil {
  case effect {
    link.Post(id:, url:, line:) -> {
      promise.map(platform.http_post(url, line), fn(sent) {
        dispatch(link.WifiAnswered(id, sent))
      })
      Nil
    }
    link.Write(id:, device:, line:) -> {
      promise.map(ble_request(device, line), fn(sent) {
        dispatch(link.RadioAnswered(id, sent))
      })
      Nil
    }
    link.OpenStream(epoch:, url:, last_id:) -> {
      close_stream()
      let stream =
        platform.open_stream(
          url,
          option.unwrap(last_id, ""),
          fn() { dispatch(link.StreamOpened(epoch)) },
          fn(chunk) { dispatch(link.StreamChunk(epoch, chunk)) },
          fn(aborted) { dispatch(link.StreamEnded(epoch, aborted)) },
        )
      change(fn(runtime) { Runtime(..runtime, stream: Some(stream)) })
    }
    link.CloseStream -> close_stream()
    link.WaitToRetry(epoch:, delay:) -> {
      cancel_retry()
      let timer =
        platform.set_timeout(delay, fn() { dispatch(link.RetryElapsed(epoch)) })
      change(fn(runtime) { Runtime(..runtime, retry: Some(timer)) })
    }
    link.CancelRetry -> cancel_retry()
    link.SaveEndpoint(url) -> platform.storage_set(endpoint_storage_key, url)
    link.WatchAdapter -> {
      unwatch_adapter()
      let remove =
        platform.ble_on_state(fn(state) {
          dispatch(link.AdapterChanged(adapter(state)))
        })
      change(fn(runtime) { Runtime(..runtime, adapter: Some(remove)) })
    }
    link.UnwatchAdapter -> unwatch_adapter()
    link.StartScan -> {
      platform.ble_stop_scan()
      platform.ble_scan(
        protocol.service_uuid,
        fn(device) { dispatch(link.DeviceFound(device)) },
        fn(reason) { dispatch(link.ScanFailed(reason)) },
      )
    }
    link.StopScan -> platform.ble_stop_scan()
    link.Connect(device) -> {
      promise.map(platform.ble_connect(device), fn(connected) {
        dispatch(link.DeviceConnected(connected))
      })
      Nil
    }
    link.Settle(id:, result:) -> settle(id, result)
    link.Report(failure) ->
      store.update(fn(state) { AppState(..state, failure: Some(failure)) })
    link.ClearReport ->
      store.update(fn(state) { AppState(..state, failure: None) })
  }
}

fn adapter(state: String) -> link.Adapter {
  case state {
    "PoweredOn" -> link.PoweredOn
    "PoweredOff" -> link.PoweredOff
    "Unauthorized" -> link.Unauthorized
    "Unsupported" -> link.Unsupported
    _ -> link.Transitioning
  }
}

fn close_stream() -> Nil {
  case current().stream {
    Some(stream) -> platform.close_stream(stream)
    None -> Nil
  }
  change(fn(runtime) { Runtime(..runtime, stream: None) })
}

fn cancel_retry() -> Nil {
  case current().retry {
    Some(timer) -> platform.clear_timeout(timer)
    None -> Nil
  }
  change(fn(runtime) { Runtime(..runtime, retry: None) })
}

fn unwatch_adapter() -> Nil {
  case current().adapter {
    Some(remove) -> remove()
    None -> Nil
  }
  change(fn(runtime) { Runtime(..runtime, adapter: None) })
}

/// Shows what the clock said, then answers whoever waits for this request.
fn settle(id: String, result: Result(Reply, Failure)) -> Nil {
  case result {
    Ok(command.StateReply(clock)) -> {
      let synced_at = Some(platform.now())
      store.update(fn(state) { AppState(..state, clock:, synced_at:) })
    }
    Ok(command.SessionReply(active_session)) ->
      store.update(fn(state) {
        AppState(..state, clock: Snapshot(..state.clock, active_session:))
      })
    Ok(command.LightReply(_)) | Ok(command.Done) | Error(_) -> Nil
  }
  let waiters = current().waiters
  case dict.get(waiters, id) {
    Ok(waiter) -> {
      change(fn(runtime) {
        Runtime(..runtime, waiters: dict.delete(waiters, id))
      })
      waiter(result)
    }
    Error(Nil) -> Nil
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

fn ble_request(
  device: Device,
  line: String,
) -> Promise(Result(String, String)) {
  use written <- promise.await(write_chunks(
    device,
    protocol.command_chunks(line),
  ))
  case written {
    Error(reason) -> promise.resolve(Error(reason))
    Ok(Nil) -> response_pages(device, Error(Nil))
  }
}

// Endpoint --------------------------------------------------------------------

fn load_endpoint() -> Promise(Option(String)) {
  use stored <- promise.map(platform.storage_get(endpoint_storage_key))
  case result.map(stored, string.trim) {
    Ok("") | Error(Nil) -> legacy_endpoint()
    Ok(_) -> option.from_result(stored)
  }
}

/// The endpoint the former Swift app kept, moved to the app storage.
fn legacy_endpoint() -> Option(String) {
  case result.map(platform.legacy_setting(endpoint_storage_key), string.trim) {
    Ok("") | Error(Nil) -> None
    Ok(endpoint) -> {
      platform.storage_set(endpoint_storage_key, endpoint)
      Some(endpoint)
    }
  }
}

// Public ----------------------------------------------------------------------

/// Starts looking for the clock; called once, when the app mounts.
pub fn start() -> Nil {
  case current().link.host {
    link.Browser -> dispatch(link.Started(None))
    link.Phone(_) -> {
      case current().app_state {
        Some(remove) -> remove()
        None -> Nil
      }
      let remove =
        platform.on_app_state(fn(active) {
          dispatch(link.ForegroundChanged(active))
        })
      change(fn(runtime) { Runtime(..runtime, app_state: Some(remove)) })
      promise.map(load_endpoint(), fn(stored) { dispatch(link.Started(stored)) })
      Nil
    }
  }
}

/// Waits for the request `msg` makes. Screens call this outside any update,
/// so the id `next_id` announces is the one `msg` uses.
fn request(msg: Msg(Device)) -> Promise(Result(Reply, Failure)) {
  promise.new(fn(resolve) {
    let id = link.next_id(current().link)
    change(fn(runtime) {
      Runtime(..runtime, waiters: dict.insert(runtime.waiters, id, resolve))
    })
    dispatch(msg)
  })
}

pub fn send(command: Command) -> Promise(Result(Reply, Failure)) {
  request(link.Send(command))
}

/// Like `send`, for what the app asks on its own.
pub fn read(command: Command) -> Promise(Result(Reply, Failure)) {
  request(link.Read(command))
}

pub fn refresh() -> Promise(Result(Reply, Failure)) {
  request(link.Refresh)
}

pub fn reconnect() -> Nil {
  dispatch(link.Reconnect)
}
