import robine/routes.{Alarms, Evening, Morning, System}

pub fn maps_public_paths_to_tabs_test() {
  assert routes.tab_for_path("/") == Ok(Morning)
  assert routes.tab_for_path("/matin") == Ok(Morning)
  assert routes.tab_for_path("/soir/") == Ok(Evening)
  assert routes.tab_for_path("/alarmes") == Ok(Alarms)
  assert routes.tab_for_path("/reveil") == Ok(System)
  assert routes.tab_for_path("/inconnue") == Error(Nil)
}

pub fn maps_tabs_to_canonical_paths_and_titles_test() {
  assert routes.path_for_tab(Morning) == "/"
  assert routes.path_for_tab(Evening) == "/soir"
  assert routes.path_for_tab(Alarms) == "/alarmes"
  assert routes.path_for_tab(System) == "/reveil"
  assert routes.title_for_tab(System) == "Réveil · Robine Wake"
}
