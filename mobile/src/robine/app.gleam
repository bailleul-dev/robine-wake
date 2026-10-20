//// The root of the app: navigation around the current screen and the layers
//// above it.

import gleam/list
import gleam/option.{None, Some}
import redraw.{type Element}
import robine/actions
import robine/command
import robine/editor
import robine/native
import robine/routes.{type Tab, Alarms, Evening, Morning, System}
import robine/screens
import robine/session.{type Active}
import robine/store.{type AppState, AppState}
import robine/style.{type Style} as s
import robine/theme
import robine/transport
import robine/wake_challenge

const tabs = [
  #(Morning, "Matin", "sunny"),
  #(Evening, "Soir", "moon"),
  #(Alarms, "Alarmes", "alarm"),
  #(System, "Réveil", "sparkles"),
]

fn pick(condition: Bool, when_true: a, when_false: a) -> a {
  case condition {
    True -> when_true
    False -> when_false
  }
}

fn label(styles: List(Style), content: String) -> Element {
  native.text([native.style(styles)], content)
}

@external(javascript, "./app_ffi.mjs", "set_title")
fn set_title(title: String) -> Nil

@external(javascript, "./app_ffi.mjs", "location_path")
fn location_path() -> String

@external(javascript, "./app_ffi.mjs", "push_path")
fn push_path(path: String) -> Nil

@external(javascript, "./app_ffi.mjs", "on_popstate")
fn on_popstate(callback: fn(String) -> Nil) -> fn() -> Nil

type PressEvent

@external(javascript, "./app_ffi.mjs", "claim_press")
fn claim_press(event: PressEvent) -> Bool

fn apply_tab(tab: Tab) -> Nil {
  store.update(fn(state) { AppState(..state, tab:) })
  set_title(routes.title_for_tab(tab))
}

fn navigate(tab: Tab) -> Nil {
  push_path(routes.path_for_tab(tab))
  apply_tab(tab)
}

/// Props of a tab link: a real link on the web, so it can open a new tab.
fn link_props(tab: Tab) -> List(native.Prop) {
  case native.web() {
    True -> [
      native.role("link"),
      native.prop("href", routes.path_for_tab(tab)),
      native.prop("onPress", fn(event: PressEvent) {
        case claim_press(event) {
          True -> navigate(tab)
          False -> Nil
        }
      }),
    ]
    False -> [native.role("button"), native.on_press(fn() { navigate(tab) })]
  }
}

fn tab_bar(state: AppState) -> Element {
  theme.glass_panel(
    theme.Glass(
      effect: "regular",
      interactive: True,
      tint: "rgba(30,20,37,0.7)",
      fallback_background: "rgba(24,16,28,0.98)",
      style: [
        s.position("absolute"),
        s.left(10),
        s.right(10),
        s.bottom(8),
        s.height(82),
        s.padding(6),
        s.flex_direction("row"),
        s.border_radius(41),
        s.border_width(1),
        s.border_color("rgba(255,231,183,0.16)"),
        s.shadow_color("#000"),
        s.shadow_opacity(0.38),
        s.shadow_radius(24),
        s.shadow_offset(0, 10),
      ],
    ),
    list.map(tabs, fn(entry) {
      let #(id, title, icon) = entry
      let active = id == state.tab
      native.pressable(
        [
          native.key(title),
          native.style([
            s.flex(1),
            s.align_items("center"),
            s.justify_content("center"),
            s.gap(3),
            s.border_radius(999),
            ..pick(active, [s.background_color("rgba(245,207,135,0.13)")], [])
          ]),
          ..link_props(id)
        ],
        [
          theme.icon(icon, 22, pick(active, theme.moon, theme.muted)),
          label(
            [
              s.font_size(10),
              s.font_weight("750"),
              s.color(pick(active, theme.moon, theme.muted)),
            ],
            title,
          ),
        ],
      )
    }),
  )
}

fn desktop_sidebar(state: AppState) -> Element {
  let ready = option.is_some(state.endpoint)
  native.view(
    [
      native.style([
        s.width(256),
        s.padding_horizontal(20),
        s.padding_vertical(28),
        s.background_color("rgba(20,14,25,0.76)"),
        s.border_right_width(1),
        s.border_right_color("rgba(255,231,183,0.09)"),
      ]),
    ],
    [
      native.view(
        [
          native.style([
            s.flex_direction("row"),
            s.align_items("center"),
            s.gap(12),
            s.padding_horizontal(8),
            s.margin_bottom(34),
          ]),
        ],
        [
          theme.crescent(34),
          native.view([], [
            label(
              [
                s.font_size(13),
                s.font_weight("900"),
                s.letter_spacing(1.7),
                s.color(theme.text),
              ],
              "ROBINE WAKE",
            ),
            label(
              [s.font_size(11), s.margin_top(2), s.color(theme.muted)],
              "Des matins plus doux",
            ),
          ]),
        ],
      ),
      theme.eyebrow("Vos rituels", theme.moon),
      native.view(
        [native.style([s.gap(8), s.margin_top(12)])],
        list.map(tabs, fn(entry) {
          let #(id, title, icon) = entry
          let active = id == state.tab
          native.pressable(
            [
              native.key(title),
              native.pressable_style(fn(pressed) {
                [
                  s.height(48),
                  s.padding_horizontal(14),
                  s.border_radius(15),
                  s.flex_direction("row"),
                  s.align_items("center"),
                  s.gap(12),
                  s.cursor("pointer"),
                  s.background_color(case pressed, active {
                    True, _ -> "rgba(245,207,135,0.18)"
                    False, True -> "rgba(245,207,135,0.13)"
                    False, False -> "transparent"
                  }),
                  s.border_width(1),
                  s.border_color(pick(
                    active,
                    "rgba(245,207,135,0.24)",
                    "transparent",
                  )),
                ]
              }),
              ..link_props(id)
            ],
            [
              theme.icon(icon, 21, pick(active, theme.moon, theme.muted)),
              label(
                [
                  s.font_size(14),
                  s.font_weight(pick(active, "800", "650")),
                  s.color(pick(active, theme.text, theme.muted)),
                ],
                title,
              ),
              native.when(active, fn() {
                native.view(
                  [
                    native.style([
                      s.margin_left_auto(),
                      s.width(6),
                      s.height(6),
                      s.border_radius(3),
                      s.background_color(theme.moon),
                    ]),
                  ],
                  [],
                )
              }),
            ],
          )
        }),
      ),
      native.view([native.style([s.flex(1)])], []),
      native.view(
        [
          native.style([
            s.padding(15),
            s.border_radius(18),
            s.background_color("rgba(245,207,135,0.055)"),
            s.border_width(1),
            s.border_color("rgba(245,207,135,0.12)"),
          ]),
        ],
        [
          label(
            [s.font_size(11), s.font_weight("800"), s.color(theme.muted)],
            "LE RÉVEIL VEILLE",
          ),
          native.view(
            [
              native.style([
                s.flex_direction("row"),
                s.align_items("center"),
                s.gap(8),
                s.margin_top(9),
              ]),
            ],
            [
              native.view(
                [
                  native.style([
                    s.width(8),
                    s.height(8),
                    s.border_radius(4),
                    s.background_color(pick(ready, theme.mint, theme.rose)),
                  ]),
                ],
                [],
              ),
              label(
                [s.font_size(13), s.font_weight("700"), s.color(theme.text)],
                pick(
                  ready,
                  "Tout est prêt pour demain",
                  "Connexion à retrouver",
                ),
              ),
            ],
          ),
          label(
            [
              s.font_size(11),
              s.line_height(16),
              s.margin_top(8),
              s.color(theme.muted),
            ],
            "Vous pouvez décrocher, Robine Wake garde le rythme.",
          ),
        ],
      ),
    ],
  )
}

fn global_alarm_controls(session: Active, desktop: Bool) -> Element {
  theme.glass_panel(
    theme.Glass(
      effect: "regular",
      interactive: False,
      tint: "rgba(83,43,58,0.68)",
      fallback_background: "rgba(49,33,49,0.97)",
      style: [
        s.position("absolute"),
        s.left(pick(desktop, 280, 14)),
        s.right(pick(desktop, 24, 14)),
        s.bottom(pick(desktop, 24, 102)),
        s.padding(12),
        s.border_radius(22),
        s.flex_direction("row"),
        s.flex_wrap("wrap"),
        s.align_items("center"),
        s.gap(12),
        s.border_width(1),
        s.border_color("rgba(255,140,163,0.35)"),
        s.shadow_color("#000"),
        s.shadow_opacity(0.35),
        s.shadow_radius(18),
      ],
    ),
    [
      native.view(
        [
          native.style([
            s.width(42),
            s.height(42),
            s.border_radius(21),
            s.align_items("center"),
            s.justify_content("center"),
            s.background_color("rgba(255,140,163,0.14)"),
          ]),
        ],
        [theme.icon("pulse", 22, theme.rose)],
      ),
      native.view([native.style([s.flex(1)])], [
        label(
          [s.font_size(14), s.font_weight("800"), s.color(theme.text)],
          "Alarme en cours",
        ),
        label([s.font_size(12), s.color(theme.muted)], case session.phase {
          session.StrongPhase -> "Son de renfort"
          session.GentlePhase -> "Réveil progressif"
        }),
      ]),
      native.when(session.test_mode, fn() {
        theme.button("Arrêt direct", fn() {
          actions.send(command.Dismiss)
          Nil
        })
        |> theme.compact
        |> theme.render
      }),
      case session.phone_may_dismiss {
        True ->
          theme.button(
            pick(session.test_mode, "Tester l’arrêt", "Je suis levé"),
            fn() { actions.open_challenge(session.id) },
          )
          |> theme.with_icon("sunny")
          |> theme.primary
          |> theme.compact
          |> theme.render
        False ->
          label(
            [s.font_size(11), s.font_weight("700"), s.color(theme.muted)],
            "Arrêt sur le réveil",
          )
      },
    ],
  )
}

fn error_dialog(message: String) -> Element {
  native.modal(
    [
      native.prop("visible", True),
      native.prop("transparent", True),
      native.prop("animationType", "fade"),
    ],
    [
      native.view(
        [
          native.style([
            s.flex(1),
            s.justify_content("center"),
            s.padding(24),
            s.background_color("rgba(0,0,0,0.62)"),
          ]),
        ],
        [
          theme.card(True, [], [
            native.view([native.style([s.gap(16)])], [
              label(
                [s.font_size(20), s.font_weight("800"), s.color(theme.text)],
                "Connexion au réveil",
              ),
              label(
                [s.font_size(14), s.line_height(20), s.color(theme.muted)],
                message,
              ),
              native.view(
                [
                  native.style([
                    s.flex_direction("row"),
                    s.justify_content("flex-end"),
                    s.gap(10),
                  ]),
                ],
                [
                  theme.button("Fermer", store.clear_failure) |> theme.render,
                  theme.button("Réessayer", fn() {
                    store.clear_failure()
                    transport.reconnect()
                  })
                    |> theme.primary
                    |> theme.render,
                ],
              ),
            ]),
          ]),
        ],
      ),
    ],
  )
}

fn current_screen(tab: Tab, desktop: Bool) -> Element {
  case tab {
    Evening -> screens.evening_screen(desktop)
    Alarms -> screens.alarms_screen(desktop)
    System -> screens.system_screen(desktop)
    Morning -> screens.morning_screen(desktop)
  }
}

fn apply_browser_route(path: String) -> Nil {
  case routes.tab_for_path(path) {
    Ok(tab) -> apply_tab(tab)
    Error(Nil) -> Nil
  }
}

/// The root component, registered with Expo by `index.js`.
pub fn app(_props: Nil) -> Element {
  let state = store.use_app_state()
  let desktop = theme.desktop_width(theme.use_viewport_width())
  redraw.use_effect_(
    fn() {
      let remove = on_popstate(apply_browser_route)
      case native.web() {
        True -> apply_browser_route(location_path())
        False -> Nil
      }
      transport.start()
      remove
    },
    #(),
  )
  native.safe_area_provider([
    native.view(
      [native.style([s.flex(1), s.background_color(theme.night950)])],
      [
        theme.night_background(),
        native.status_bar_light(),
        native.view(
          [
            native.style([
              s.flex(1),
              s.flex_direction(pick(desktop, "row", "column")),
            ]),
          ],
          [
            native.when(desktop, fn() { desktop_sidebar(state) }),
            native.safe_area_view(
              [native.edges(["top"]), native.style([s.flex(1)])],
              [current_screen(state.tab, desktop)],
            ),
          ],
        ),
        native.when(!desktop, fn() { tab_bar(state) }),
        case state.clock.active_session {
          Some(session) -> global_alarm_controls(session, desktop)
          None -> native.none()
        },
        case state.editor {
          Some(draft) -> editor.alarm_editor(draft)
          None -> native.none()
        },
        native.when(
          option.is_some(store.challenged(state)),
          wake_challenge.wake_challenge,
        ),
        case state.failure {
          Some(failure) -> error_dialog(command.describe(failure))
          None -> native.none()
        },
      ],
    ),
  ])
}
