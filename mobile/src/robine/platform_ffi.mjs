// Services of the phone used by the transport: storage, HTTP, the app state
// and Bluetooth LE. Everything resolves to Gleam `Result`s.

import AsyncStorage from "@react-native-async-storage/async-storage";
import { fetch as expoFetch } from "expo/fetch";
import { AppState, Platform, Settings } from "react-native";
import { BleManager } from "react-native-ble-plx";
import * as Haptics from "expo-haptics";
import { Ok, Error } from "../gleam.mjs";

const message = (error, fallback) =>
  error instanceof globalThis.Error && error.message ? error.message : fallback;

function request(url, options) {
  return expoFetch.call(globalThis, url, options);
}

export function now() {
  return Date.now();
}

export function storage_get(key) {
  return AsyncStorage.getItem(key)
    .then((value) => (typeof value === "string" ? new Ok(value) : new Error(undefined)))
    .catch(() => new Error(undefined));
}

export function storage_set(key, value) {
  AsyncStorage.setItem(key, value).catch(() => undefined);
}

export function storage_remove(key) {
  AsyncStorage.removeItem(key).catch(() => undefined);
}

/// A value the Swift app kept in NSUserDefaults.
export function legacy_setting(key) {
  const value = Platform.OS === "ios" ? Settings?.get(key) : undefined;
  if (typeof value === "string") return new Ok(value);
  if (typeof value === "number") return new Ok(String(value));
  return new Error(undefined);
}

export async function http_post(url, body) {
  try {
    const response = await request(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body,
    });
    if (!response.ok) return new Error("Le réveil a refusé la connexion Wi-Fi");
    return new Ok(await response.text());
  } catch (error) {
    return new Error(message(error, "Connexion Wi-Fi impossible"));
  }
}

/// Opens an event stream and reports each decoded chunk. `on_end` is called
/// once with whether the stream was aborted on purpose.
export function open_stream(url, last_id, on_open, on_chunk, on_end) {
  const controller = new AbortController();
  const headers = { Accept: "text/event-stream", "Cache-Control": "no-cache" };
  if (last_id !== "") headers["Last-Event-ID"] = last_id;
  (async () => {
    const response = await request(url, { method: "GET", headers, signal: controller.signal });
    if (!response.ok) throw new globalThis.Error("Le flux temps réel du réveil est indisponible");
    if (!response.body) throw new globalThis.Error("Le flux temps réel n’est pas pris en charge");
    on_open();
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    while (true) {
      const result = await reader.read();
      if (result.done) throw new globalThis.Error("Le flux temps réel a été interrompu");
      on_chunk(decoder.decode(result.value, { stream: true }));
    }
  })().catch((error) => on_end(error?.name === "AbortError"));
  return controller;
}

export function close_stream(controller) {
  controller.abort();
}

export function set_timeout(ms, callback) {
  return setTimeout(callback, ms);
}

export function clear_timeout(timer) {
  clearTimeout(timer);
}

export function app_active() {
  return !["background", "inactive"].includes(AppState.currentState);
}

export function on_app_state(callback) {
  const subscription = AppState.addEventListener("change", (state) =>
    callback(state === "active"),
  );
  return () => subscription.remove();
}

// Bluetooth LE ---------------------------------------------------------------

let manager = null;
const bluetooth = () => (manager ??= new BleManager());

export function ble_on_state(callback) {
  const subscription = bluetooth().onStateChange(callback, true);
  return () => subscription.remove();
}

export function ble_scan(service, on_device, on_error) {
  bluetooth().startDeviceScan([service], null, (error, device) => {
    if (error) on_error(message(error, "Recherche Bluetooth impossible"));
    else if (device) on_device(device);
  });
}

export function ble_stop_scan() {
  manager?.stopDeviceScan();
}

export async function ble_connect(device) {
  try {
    const connected = await device.connect();
    return new Ok(await connected.discoverAllServicesAndCharacteristics());
  } catch (error) {
    return new Error(message(error, "Connexion Bluetooth impossible"));
  }
}

export async function ble_write(device, service, characteristic, base64) {
  try {
    await device.writeCharacteristicWithResponseForService(service, characteristic, base64);
    return new Ok(undefined);
  } catch (error) {
    return new Error(message(error, "Écriture Bluetooth impossible"));
  }
}

export async function ble_read(device, service, characteristic) {
  try {
    const result = await device.readCharacteristicForService(service, characteristic);
    return new Ok(result.value ?? "");
  } catch (error) {
    return new Error(message(error, "Lecture Bluetooth impossible"));
  }
}

export function local_timezone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "Europe/Paris";
}

export function set_interval(ms, callback) {
  return setInterval(callback, ms);
}

export function clear_interval(timer) {
  clearInterval(timer);
}

const timeFormat = new Intl.DateTimeFormat("fr-FR", { hour: "2-digit", minute: "2-digit" });
const dayFormat = new Intl.DateTimeFormat("fr-FR", { weekday: "long", day: "numeric", month: "long" });
const dateTimeFormat = new Intl.DateTimeFormat("fr-FR", { dateStyle: "short", timeStyle: "short" });

export function format_time(ms) {
  return timeFormat.format(new Date(ms));
}

export function format_day(ms) {
  return dayFormat.format(new Date(ms));
}

export function format_date_time(ms) {
  return dateTimeFormat.format(new Date(ms));
}

export async function http_get(url) {
  try {
    const response = await fetch(url);
    return new Ok(await response.text());
  } catch (error) {
    return new Error(message(error, "Requête impossible"));
  }
}

export function haptic(success) {
  Haptics.notificationAsync(
    success
      ? Haptics.NotificationFeedbackType.Success
      : Haptics.NotificationFeedbackType.Error,
  ).catch(() => undefined);
}
