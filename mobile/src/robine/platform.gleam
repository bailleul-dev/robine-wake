//// Phone services used by the transport, implemented in `platform_ffi.mjs`.

import gleam/javascript/promise.{type Promise}

pub type Stream

pub type Timer

/// A Bluetooth device found by a scan.
pub type Device

@external(javascript, "./platform_ffi.mjs", "now")
pub fn now() -> Int

@external(javascript, "./platform_ffi.mjs", "storage_get")
pub fn storage_get(key: String) -> Promise(Result(String, Nil))

@external(javascript, "./platform_ffi.mjs", "storage_set")
pub fn storage_set(key: String, value: String) -> Nil

@external(javascript, "./platform_ffi.mjs", "storage_remove")
pub fn storage_remove(key: String) -> Nil

/// A value the former Swift app kept in the iOS user defaults.
@external(javascript, "./platform_ffi.mjs", "legacy_setting")
pub fn legacy_setting(key: String) -> Result(String, Nil)

@external(javascript, "./platform_ffi.mjs", "http_post")
pub fn http_post(url: String, body: String) -> Promise(Result(String, String))

/// `last_id` is empty for a fresh stream; `on_end` gets whether the stream was
/// closed on purpose.
@external(javascript, "./platform_ffi.mjs", "open_stream")
pub fn open_stream(
  url: String,
  last_id: String,
  on_open: fn() -> Nil,
  on_chunk: fn(String) -> Nil,
  on_end: fn(Bool) -> Nil,
) -> Stream

@external(javascript, "./platform_ffi.mjs", "close_stream")
pub fn close_stream(stream: Stream) -> Nil

@external(javascript, "./platform_ffi.mjs", "set_timeout")
pub fn set_timeout(ms: Int, callback: fn() -> Nil) -> Timer

@external(javascript, "./platform_ffi.mjs", "clear_timeout")
pub fn clear_timeout(timer: Timer) -> Nil

@external(javascript, "./platform_ffi.mjs", "app_active")
pub fn app_active() -> Bool

/// Calls back with `True` when the app comes to the foreground; returns the
/// unsubscribe function.
@external(javascript, "./platform_ffi.mjs", "on_app_state")
pub fn on_app_state(callback: fn(Bool) -> Nil) -> fn() -> Nil

/// Reports the Bluetooth adapter state ("PoweredOn", "Unauthorized"…).
@external(javascript, "./platform_ffi.mjs", "ble_on_state")
pub fn ble_on_state(callback: fn(String) -> Nil) -> fn() -> Nil

@external(javascript, "./platform_ffi.mjs", "ble_scan")
pub fn ble_scan(
  service: String,
  on_device: fn(Device) -> Nil,
  on_error: fn(String) -> Nil,
) -> Nil

@external(javascript, "./platform_ffi.mjs", "ble_stop_scan")
pub fn ble_stop_scan() -> Nil

@external(javascript, "./platform_ffi.mjs", "ble_connect")
pub fn ble_connect(device: Device) -> Promise(Result(Device, String))

/// Writes base64 data with response.
@external(javascript, "./platform_ffi.mjs", "ble_write")
pub fn ble_write(
  device: Device,
  service: String,
  characteristic: String,
  base64: String,
) -> Promise(Result(Nil, String))

/// Reads a characteristic as base64.
@external(javascript, "./platform_ffi.mjs", "ble_read")
pub fn ble_read(
  device: Device,
  service: String,
  characteristic: String,
) -> Promise(Result(String, String))

/// The phone's time zone, `Europe/Paris` when unknown.
@external(javascript, "./platform_ffi.mjs", "local_timezone")
pub fn local_timezone() -> String

pub type Interval

@external(javascript, "./platform_ffi.mjs", "set_interval")
pub fn set_interval(ms: Int, callback: fn() -> Nil) -> Interval

@external(javascript, "./platform_ffi.mjs", "clear_interval")
pub fn clear_interval(timer: Interval) -> Nil

/// `07:45`.
@external(javascript, "./platform_ffi.mjs", "format_time")
pub fn format_time(ms: Int) -> String

/// `lundi 19 octobre`.
@external(javascript, "./platform_ffi.mjs", "format_day")
pub fn format_day(ms: Int) -> String

/// `19/10/2026 07:45`.
@external(javascript, "./platform_ffi.mjs", "format_date_time")
pub fn format_date_time(ms: Int) -> String

@external(javascript, "./platform_ffi.mjs", "http_get")
pub fn http_get(url: String) -> Promise(Result(String, String))

/// A success or error vibration.
@external(javascript, "./platform_ffi.mjs", "haptic")
pub fn haptic(success: Bool) -> Nil
