import { useSyncExternalStore } from "react";
import type { AppState } from "./types";

export const initialState: AppState = {
  tab: "morning",
  connection: "scanning",
  transport: null,
  httpEndpoint: null,
  busy: false,
  error: null,
  alarms: [],
  sounds: [],
  device: null,
  recentSessions: [],
  activeSession: null,
  smartphoneDismiss: { enabled: true, locked: false },
  hue: null,
  hueTargets: [],
  remoteButton: null,
  breathingSynchronizedAt: null,
  editor: null,
  challenge: null,
  lastUpdated: null,
};

let appState = initialState;
const listeners = new Set<() => void>();

export function getState(): AppState {
  return appState;
}

export function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function emit(): void {
  for (const listener of listeners) listener();
}

export function setState<K extends keyof AppState>(
  key: K,
  value: AppState[K],
): void {
  appState = { ...appState, [key]: value };
  emit();
}

export function mergeState(values: Partial<AppState>): void {
  appState = { ...appState, ...values };
  emit();
}

export function useAppState(): AppState {
  return useSyncExternalStore(subscribe, getState, getState);
}

export function clearError(): void {
  setState("error", null);
}
