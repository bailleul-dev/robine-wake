//// Paths of the web app, one per tab.

import gleam/string
import robine/types.{type Tab, Alarms, Evening, Morning, System}

pub fn normalize_path(path: String) -> String {
  case string.trim(path) {
    "" -> "/"
    normalized ->
      case string.length(normalized) > 1 && string.ends_with(normalized, "/") {
        True -> string.drop_end(normalized, 1)
        False -> normalized
      }
  }
}

pub fn tab_for_path(path: String) -> Result(Tab, Nil) {
  case normalize_path(path) {
    "/" | "/matin" -> Ok(Morning)
    "/soir" -> Ok(Evening)
    "/alarmes" -> Ok(Alarms)
    "/reveil" -> Ok(System)
    _ -> Error(Nil)
  }
}

pub fn path_for_tab(tab: Tab) -> String {
  case tab {
    Morning -> "/"
    Evening -> "/soir"
    Alarms -> "/alarmes"
    System -> "/reveil"
  }
}

pub fn title_for_tab(tab: Tab) -> String {
  case tab {
    Morning -> "Matin · Robine Wake"
    Evening -> "Soir · Robine Wake"
    Alarms -> "Alarmes · Robine Wake"
    System -> "Réveil · Robine Wake"
  }
}
