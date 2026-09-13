import AsyncStorage from "@react-native-async-storage/async-storage";
import { fetch as expoFetch } from "expo/fetch";
import { AppState as NativeAppState, Platform, Settings } from "react-native";
import type { NativeEventSubscription } from "react-native";
import {
  BleManager,
  type Device,
  type Subscription,
} from "react-native-ble-plx";
import {
  bytesToBase64,
  bytesToString,
  concatBytes,
  crc32,
  parsePage,
  utf8Bytes,
} from "./protocol";
import { consumeChunk, eventsEndpoint, type ServerEvent } from "./sse";
import { getState, mergeState, setState } from "./store";
import type {
  Alarm,
  CommandBody,
  DeviceState,
  HueState,
  HueTarget,
  RemoteButtonState,
  Sound,
  WakeSession,
} from "./types";

export const serviceUuid = "8AD00001-A7A9-4EF7-A259-67C9C65E4C10";
export const commandUuid = "8AD00002-A7A9-4EF7-A259-67C9C65E4C10";
export const responseUuid = "8AD00003-A7A9-4EF7-A259-67C9C65E4C10";
export const endpointStorageKey = "robineWake.httpCommandEndpoint.v1";
export const web = Platform.OS === "web";
export const webCommandEndpoint = "/api/v1/command";

const manager = web ? null : new BleManager();
let connectedDevice: Device | null = null;
let pendingCommand: string | null = null;
let bluetoothStateSubscription: Subscription | null = null;
let eventController: AbortController | null = null;
let eventRetryTimer: ReturnType<typeof setTimeout> | null = null;
let eventRetryDelay = 1_000;
let eventGeneration = 0;
let eventLastId: string | null = null;
let eventEndpoint: string | null = null;
let eventRefreshPending = false;
let appStateSubscription: NativeEventSubscription | null = null;

const errorMessages: Record<string, string> = {
  stale_revision: "Cette alarme a changé. Actualisez avant de réessayer.",
  not_found: "Cet élément n’existe plus sur le réveil.",
  validation_failed: "Certains réglages ne sont pas valides.",
  hue_link_button_required:
    "Appuyez sur le bouton rond du pont Hue, puis réessayez.",
  invalid_hue_bridge_address: "L’adresse du pont Hue n’est pas valide.",
  hue_pairing_failed: "Le pont Hue a refusé l’association.",
  hue_target_not_found: "Cette pièce ou zone Hue n’est plus disponible.",
  wake_session_active: "Une alarme utilise déjà la lumière Hue.",
  unsupported_operation:
    "Cette fonction nécessite une version plus récente du réveil.",
  pairing_window_closed: "La fenêtre d’association du bouton est fermée.",
  remote_button_not_paired: "Ce bouton n’est plus associé au réveil.",
  smartphone_dismiss_disabled: "L’arrêt depuis le smartphone est désactivé.",
  smartphone_dismiss_setting_locked:
    "Ce réglage est verrouillé pendant une alarme.",
};

interface StateBody {
  alarms?: Alarm[];
  sounds?: Sound[];
  device?: DeviceState | null;
  recent_sessions?: WakeSession[];
  active_session?: WakeSession | null;
  smartphone_dismiss?: { enabled?: boolean; locked?: boolean };
  hue?: HueState | null;
  hue_targets?: HueTarget[];
  remote_button?: RemoteButtonState | null;
  transport?: { http_endpoints?: string[] };
}

interface ResponseEnvelope {
  v: number;
  id: string;
  status: string;
  error?: { code?: string };
  body: StateBody & { active_session?: WakeSession | null };
}

export function makeRequestId(): string {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (token) => {
    const random = Math.floor(Math.random() * 16);
    return (token === "x" ? random : (random & 0x3) | 0x8).toString(16);
  });
}

function request(url: string, options: RequestInit): Promise<Response> {
  return (expoFetch as unknown as typeof fetch).call(globalThis, url, options);
}

async function responsePages(device: Device): Promise<string> {
  let assembled: Uint8Array<ArrayBufferLike> = new Uint8Array(0);
  let expectedIndex = 0;
  let metadata: Pick<
    ReturnType<typeof parsePage>,
    "sequence" | "count" | "total" | "crc"
  > | null = null;
  while (true) {
    const characteristic = await device.readCharacteristicForService(
      serviceUuid,
      responseUuid,
    );
    const page = parsePage(characteristic.value ?? "");
    const expected: Pick<
      ReturnType<typeof parsePage>,
      "sequence" | "count" | "total" | "crc"
    > = metadata ?? {
      sequence: page.sequence,
      count: page.count,
      total: page.total,
      crc: page.crc,
    };
    if (
      expectedIndex !== page.index ||
      expected.sequence !== page.sequence ||
      expected.count !== page.count ||
      expected.total !== page.total ||
      expected.crc !== page.crc ||
      page.count === 0 ||
      page.total > 1_048_576
    ) {
      throw new Error("Pages Bluetooth incohérentes");
    }
    metadata = expected;
    assembled = concatBytes(assembled, page.payload);
    if (page.final) {
      if (
        expectedIndex + 1 !== page.count ||
        assembled.length !== page.total ||
        crc32(assembled) !== page.crc
      ) {
        throw new Error("Réponse Bluetooth incomplète ou corrompue");
      }
      return bytesToString(assembled);
    }
    expectedIndex += 1;
  }
}

async function writeChunks(device: Device, payload: string): Promise<void> {
  const bytes = utf8Bytes(`${payload}\n`);
  for (let offset = 0; offset < bytes.length; offset += 180) {
    await device.writeCharacteristicWithResponseForService(
      serviceUuid,
      commandUuid,
      bytesToBase64(bytes.slice(offset, Math.min(bytes.length, offset + 180))),
    );
  }
}

async function bleRequest(json: string): Promise<string> {
  if (!connectedDevice) throw new Error("Bluetooth indisponible");
  await writeChunks(connectedDevice, json);
  return responsePages(connectedDevice);
}

async function httpRequest(endpoint: string, json: string): Promise<string> {
  const response = await request(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: json,
  });
  if (!response.ok) throw new Error("Le réveil a refusé la connexion Wi-Fi");
  return response.text();
}

function rememberEndpoint(body: StateBody): void {
  if (web) return;
  const endpoint = body.transport?.http_endpoints?.[0];
  if (!endpoint) return;
  const changed = endpoint !== getState().httpEndpoint;
  setState("httpEndpoint", endpoint);
  void AsyncStorage.setItem(endpointStorageKey, endpoint);
  if (changed) startEventStream(endpoint);
}

function applyState(body: StateBody): void {
  rememberEndpoint(body);
  mergeState({
    alarms: [...(body.alarms ?? [])].sort((left, right) =>
      left.local_time.localeCompare(right.local_time),
    ),
    sounds: body.sounds ?? [],
    device: body.device ?? null,
    recentSessions: body.recent_sessions ?? [],
    activeSession: body.active_session ?? null,
    smartphoneDismiss: body.smartphone_dismiss ?? {
      enabled: true,
      locked: false,
    },
    hue: body.hue ?? null,
    hueTargets: body.hue_targets ?? [],
    remoteButton: body.remote_button ?? null,
    breathingSynchronizedAt: body.hue?.breathing?.active ? new Date() : null,
    lastUpdated: new Date(),
  });
}

function handleResponse(
  operation: string,
  requestId: string,
  text: string,
): StateBody {
  const envelope = JSON.parse(text) as ResponseEnvelope;
  if (envelope.v !== 1)
    throw new Error("Version du protocole non prise en charge");
  if (envelope.id !== requestId)
    throw new Error("La réponse ne correspond pas à la commande");
  if (envelope.status !== "ok") {
    const code = envelope.error?.code ?? "unknown";
    throw new Error(
      errorMessages[code] ?? `Le réveil a refusé la commande (${code})`,
    );
  }
  if (operation === "state.get") applyState(envelope.body);
  else if (operation === "session.get")
    setState("activeSession", envelope.body.active_session ?? null);
  return envelope.body;
}

function finishCommand(): void {
  pendingCommand = null;
  setState("busy", false);
  drainEventRefresh();
}

export async function command(
  operation: string,
  body: CommandBody = {},
): Promise<StateBody> {
  if (pendingCommand) throw new Error("Une synchronisation est déjà en cours");
  const requestId = makeRequestId();
  const json = JSON.stringify({ v: 1, id: requestId, op: operation, body });
  const endpoint = getState().httpEndpoint;
  pendingCommand = operation;
  mergeState({ busy: true, error: null });
  try {
    let text: string;
    if (endpoint) {
      try {
        text = await httpRequest(endpoint, json);
        mergeState({ transport: "http", connection: "connected" });
      } catch (error) {
        if (web) throw error;
        stopEventStream();
        void AsyncStorage.removeItem(endpointStorageKey);
        setState("httpEndpoint", null);
        text = await bleRequest(json);
      }
    } else {
      text = await bleRequest(json);
    }
    const response = handleResponse(operation, requestId, text);
    if (operation !== "state.get" && operation !== "session.get")
      eventRefreshPending = true;
    finishCommand();
    return response;
  } catch (error) {
    finishCommand();
    setState(
      "error",
      error instanceof Error ? error.message : "Connexion au réveil impossible",
    );
    throw error;
  }
}

export function refresh(): Promise<unknown> {
  return pendingCommand ? Promise.resolve(null) : command("state.get");
}

function drainEventRefresh(): void {
  if (!eventRefreshPending || pendingCommand) return;
  eventRefreshPending = false;
  void refresh().catch(() => undefined);
}

function requestEventRefresh(): void {
  eventRefreshPending = true;
  drainEventRefresh();
}

function clearEventRetry(): void {
  if (eventRetryTimer) clearTimeout(eventRetryTimer);
  eventRetryTimer = null;
}

export function stopEventStream(): void {
  eventGeneration += 1;
  clearEventRetry();
  eventController?.abort();
  eventController = null;
}

function eventStreamActive(): boolean {
  return (
    web || !["background", "inactive"].includes(NativeAppState.currentState)
  );
}

function handleEvent({ id, event, data }: ServerEvent): void {
  if (id && event !== "ready") eventLastId = id;
  if (event === "ready") {
    eventRetryDelay = 1_000;
    mergeState({ transport: "http", connection: "connected" });
  }
  if (
    ["state.changed", "session.changed", "breathing.changed"].includes(event)
  ) {
    try {
      const envelope = JSON.parse(data) as { v?: number };
      if (envelope.v === 1) requestEventRefresh();
    } catch {
      // Ignore malformed events; the stream remains usable.
    }
  }
}

async function readEventStream(
  response: Response,
  generation: number,
): Promise<void> {
  if (!response.ok)
    throw new Error("Le flux temps réel du réveil est indisponible");
  if (!response.body)
    throw new Error("Le flux temps réel n’est pas pris en charge");
  mergeState({ transport: "http", connection: "connected" });
  eventRetryDelay = 1_000;
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  while (generation === eventGeneration) {
    const result = await reader.read();
    if (result.done) throw new Error("Le flux temps réel a été interrompu");
    const consumed = consumeChunk(
      buffer,
      decoder.decode(result.value, { stream: true }),
    );
    buffer = consumed.buffer;
    consumed.events.forEach(handleEvent);
  }
}

function scheduleEventReconnect(
  commandEndpoint: string,
  generation: number,
): void {
  if (generation !== eventGeneration || !eventStreamActive()) return;
  const delay = eventRetryDelay;
  eventRetryDelay = Math.min(15_000, delay * 2);
  clearEventRetry();
  eventRetryTimer = setTimeout(() => {
    eventRetryTimer = null;
    if (generation === eventGeneration) startEventStream(commandEndpoint);
  }, delay);
}

export function startEventStream(commandEndpoint: string): void {
  if (!commandEndpoint.trim() || !eventStreamActive()) return;
  const nextEndpoint = eventsEndpoint(commandEndpoint);
  const sameEndpoint = nextEndpoint === eventEndpoint;
  stopEventStream();
  if (!sameEndpoint) eventLastId = null;
  eventEndpoint = nextEndpoint;
  const generation = eventGeneration;
  const controller = new AbortController();
  const headers: Record<string, string> = {
    Accept: "text/event-stream",
    "Cache-Control": "no-cache",
  };
  if (eventLastId) headers["Last-Event-ID"] = eventLastId;
  eventController = controller;
  void request(nextEndpoint, {
    method: "GET",
    headers,
    signal: controller.signal,
  })
    .then((response) => readEventStream(response, generation))
    .catch((error: unknown) => {
      if (
        generation === eventGeneration &&
        (!(error instanceof Error) || error.name !== "AbortError")
      ) {
        eventController = null;
        scheduleEventReconnect(commandEndpoint, generation);
      }
    });
}

function installAppStateListener(): void {
  if (web) return;
  appStateSubscription?.remove();
  appStateSubscription = NativeAppState.addEventListener("change", (state) => {
    if (state === "active") {
      const endpoint = getState().httpEndpoint;
      if (endpoint) {
        startEventStream(endpoint);
        void refresh().catch(() => undefined);
      }
    } else {
      stopEventStream();
    }
  });
}

function connectDevice(device: Device): void {
  manager?.stopDeviceScan();
  setState("connection", "connecting");
  void device
    .connect()
    .then((connected) => connected.discoverAllServicesAndCharacteristics())
    .then((ready) => {
      connectedDevice = ready;
      mergeState({ connection: "connected", transport: "bluetooth" });
      return refresh();
    })
    .catch((error: unknown) => {
      connectedDevice = null;
      mergeState({
        connection: "disconnected",
        error:
          error instanceof Error
            ? error.message
            : "Connexion Bluetooth impossible",
      });
    });
}

function stopStateListener(): void {
  bluetoothStateSubscription?.remove();
  bluetoothStateSubscription = null;
}

function beginScan(): void {
  if (!manager) return;
  stopStateListener();
  manager.stopDeviceScan();
  manager.startDeviceScan([serviceUuid], null, (error, device) => {
    if (error) mergeState({ connection: "disconnected", error: error.message });
    else if (device) connectDevice(device);
  });
}

export function scan(): void {
  if (!manager) return;
  mergeState({ connection: "scanning", error: null });
  manager.stopDeviceScan();
  stopStateListener();
  bluetoothStateSubscription = manager.onStateChange((state) => {
    if (state === "PoweredOn") beginScan();
    else if (state === "Unauthorized") {
      stopStateListener();
      mergeState({
        connection: "disconnected",
        error: "Autorisez le Bluetooth dans Réglages pour joindre le réveil.",
      });
    } else if (state === "Unsupported") {
      stopStateListener();
      mergeState({ connection: "disconnected", error: null });
    } else if (state === "PoweredOff")
      mergeState({ connection: "disconnected", error: null });
  }, true);
}

async function loadEndpoint(): Promise<string | undefined> {
  const endpoint = await AsyncStorage.getItem(endpointStorageKey);
  if (endpoint?.trim()) return endpoint;
  const legacyEndpoint = Settings?.get(endpointStorageKey);
  if (typeof legacyEndpoint === "string" && legacyEndpoint.trim()) {
    await AsyncStorage.setItem(endpointStorageKey, legacyEndpoint);
    return legacyEndpoint;
  }
  return undefined;
}

export function start(): void {
  installAppStateListener();
  if (web) {
    mergeState({
      httpEndpoint: webCommandEndpoint,
      transport: "http",
      connection: "connecting",
    });
    startEventStream(webCommandEndpoint);
    void refresh().catch(() => undefined);
    return;
  }
  void loadEndpoint().then((endpoint) => {
    if (endpoint) {
      setState("httpEndpoint", endpoint);
      startEventStream(endpoint);
      void refresh().catch(() => scan());
    } else scan();
  });
}

export function reconnect(): Promise<unknown> | void {
  if (web) {
    mergeState({
      httpEndpoint: webCommandEndpoint,
      transport: "http",
      connection: "connecting",
    });
    startEventStream(webCommandEndpoint);
    return refresh();
  }
  stopEventStream();
  connectedDevice = null;
  scan();
}
