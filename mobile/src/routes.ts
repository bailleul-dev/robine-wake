import type { Tab } from "./types";

const tabRoutes: Record<Tab, { path: string; title: string }> = {
  morning: { path: "/", title: "Matin · Robine Wake" },
  evening: { path: "/soir", title: "Soir · Robine Wake" },
  alarms: { path: "/alarmes", title: "Alarmes · Robine Wake" },
  system: { path: "/reveil", title: "Réveil · Robine Wake" },
};

const routeTabs: Record<string, Tab> = {
  "/": "morning",
  "/matin": "morning",
  "/soir": "evening",
  "/alarmes": "alarms",
  "/reveil": "system",
};

export function normalizePath(path: string): string {
  const normalized = path.trim() || "/";
  return normalized.length > 1 && normalized.endsWith("/")
    ? normalized.slice(0, -1)
    : normalized;
}

export function tabForPath(path: string): Tab | undefined {
  return routeTabs[normalizePath(path)];
}

export function pathForTab(tab: Tab): string {
  return tabRoutes[tab]?.path ?? "/";
}

export function titleForTab(tab: Tab): string {
  return tabRoutes[tab]?.title ?? "Robine Wake";
}
