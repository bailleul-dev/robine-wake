// Browser routing of the web build; nothing happens on phones.

import { Platform } from "react-native";

const web = Platform.OS === "web";

export function set_title(title) {
  if (web) document.title = title;
}

export function location_path() {
  return web ? location.pathname : "/";
}

export function push_path(path) {
  if (!web) return;
  if (path !== location.pathname) history.pushState({}, "", path);
  window.scrollTo({ top: 0, behavior: "smooth" });
}

export function on_popstate(callback) {
  if (!web) return () => undefined;
  const listener = () => callback(location.pathname);
  window.addEventListener("popstate", listener);
  return () => window.removeEventListener("popstate", listener);
}

/// Whether a press asks the browser to open the link itself (new tab…);
/// otherwise its default navigation is prevented.
export function claim_press(event) {
  const native = event?.nativeEvent ?? {};
  const modified =
    native.altKey || native.ctrlKey || native.metaKey || native.shiftKey ||
    (native.button ?? 0) !== 0;
  if (!modified) event?.preventDefault?.();
  return !modified;
}
