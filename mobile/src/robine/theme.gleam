//// The night theme: colours, Liquid Glass panels and shared components.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import redraw.{type Element}
import robine/native
import robine/style.{type Style} as s

pub const night950 = "#090812"

pub const night900 = "#151020"

pub const night850 = "#201627"

pub const night800 = "#2A1D30"

pub const text = "#FFF8F1"

pub const muted = "#BDB1BE"

pub const moon = "#F5CF87"

pub const moon_soft = "#FFE7B7"

pub const lavender = "#AAA7FF"

pub const mint = "#78D9BC"

pub const rose = "#FF8CA3"

pub const breathing_inhale_amber = "#F5B75B"

pub const breathing_exhale_rose = "#E0698F"

pub const twilight_rose = "#E0698F"

@external(javascript, "./theme_ffi.mjs", "is_liquid_glass")
pub fn liquid_glass() -> Bool

pub const desktop_breakpoint = 900

pub fn desktop_width(width: Int) -> Bool {
  width >= desktop_breakpoint
}

pub fn use_viewport_width() -> Int {
  native.use_window_width()
}

const stars = [
  #(8, 7, 2, 0.42),
  #(18, 17, 2, 0.7),
  #(31, 5, 1, 0.55),
  #(44, 13, 2, 0.8),
  #(62, 6, 2, 0.5),
  #(79, 12, 1, 0.8),
  #(91, 4, 2, 0.55),
  #(13, 32, 1, 0.65),
  #(72, 27, 2, 0.48),
  #(92, 39, 1, 0.75),
  #(25, 53, 2, 0.4),
  #(83, 59, 2, 0.42),
  #(6, 70, 1, 0.65),
  #(52, 74, 2, 0.4),
  #(94, 83, 1, 0.65),
]

fn percent(value: Int) -> String {
  int.to_string(value) <> "%"
}

pub fn night_background() -> Element {
  native.linear_gradient(
    [night950, night900, "#211629"],
    #(0.0, 0.0),
    #(1.0, 1.0),
    [native.style([s.position("absolute"), s.fill()])],
    [
      native.view(
        [
          native.style([
            s.position("absolute"),
            s.width(520),
            s.height(520),
            s.border_radius(999),
            s.right(-210),
            s.top(-260),
            s.opacity(0.2),
            s.background_color("#9D5C78"),
          ]),
        ],
        [],
      ),
      native.view(
        [
          native.style([
            s.position("absolute"),
            s.width(480),
            s.height(480),
            s.border_radius(999),
            s.left(-260),
            s.bottom(-300),
            s.opacity(0.13),
            s.background_color("#E39A62"),
          ]),
        ],
        [],
      ),
      ..list.map(stars, fn(star) {
        let #(x, y, size, opacity) = star
        native.view(
          [
            native.key(int.to_string(x) <> "-" <> int.to_string(y)),
            native.style([
              s.position("absolute"),
              s.left_pct(percent(x)),
              s.raw("top", percent(y)),
              s.width(size),
              s.height(size),
              s.border_radius(size),
              s.opacity(opacity),
              s.background_color(moon_soft),
            ]),
          ],
          [],
        )
      })
    ],
  )
}

pub fn icon(name: String, size: Int, color: String) -> Element {
  native.icon(name, size, color)
}

pub fn crescent(size: Int) -> Element {
  native.view(
    [
      native.style([
        s.shadow_color(moon),
        s.shadow_opacity(0.35),
        s.raw("shadowRadius", int.to_float(size) *. 0.3),
      ]),
    ],
    [icon("moon", size, moon)],
  )
}

pub fn eyebrow(label: String, color: String) -> Element {
  native.text(
    [
      native.style([
        s.font_size(11),
        s.font_weight("800"),
        s.letter_spacing(1.5),
        s.color(color),
        s.text_transform("uppercase"),
      ]),
    ],
    label,
  )
}

/// Settings of a glass panel; start from `glass()`.
pub type Glass {
  Glass(
    effect: String,
    interactive: Bool,
    tint: String,
    fallback_background: String,
    style: List(Style),
  )
}

pub fn glass() -> Glass {
  Glass(
    effect: "regular",
    interactive: False,
    tint: "rgba(34,24,43,0.58)",
    fallback_background: "rgba(31,23,39,0.9)",
    style: [],
  )
}

pub fn glass_panel(glass: Glass, children: List(Element)) -> Element {
  case liquid_glass() {
    True ->
      native.glass_view(
        [
          native.style(glass.style),
          native.prop("glassEffectStyle", glass.effect),
          native.prop("tintColor", glass.tint),
          native.prop("colorScheme", "dark"),
          native.prop("isInteractive", glass.interactive),
        ],
        children,
      )
    False ->
      native.view(
        [
          native.style(
            list.append(glass.style, [
              s.background_color(glass.fallback_background),
            ]),
          ),
        ],
        children,
      )
  }
}

/// A card; `extra` is appended to its style, padding 18 by default.
pub fn card(
  highlighted: Bool,
  extra: List(Style),
  children: List(Element),
) -> Element {
  glass_panel(
    Glass(
      effect: case highlighted {
        True -> "regular"
        False -> "clear"
      },
      interactive: False,
      tint: case highlighted {
        True -> "rgba(84,54,69,0.58)"
        False -> "rgba(35,27,45,0.48)"
      },
      fallback_background: case highlighted {
        True -> "rgba(49,33,49,0.95)"
        False -> "rgba(31,23,39,0.9)"
      },
      style: [
        s.padding(18),
        s.border_radius(24),
        s.border_width(1),
        s.border_color(case highlighted {
          True -> "rgba(245,207,135,0.32)"
          False -> "rgba(255,231,183,0.12)"
        }),
        s.shadow_color("#2A1020"),
        s.shadow_opacity(0.3),
        s.shadow_radius(18),
        s.shadow_offset(0, 10),
        ..extra
      ],
    ),
    children,
  )
}

pub fn divider() -> Element {
  native.view(
    [native.style([s.height(1), s.background_color("rgba(255,255,255,0.08)")])],
    [],
  )
}

// Buttons ---------------------------------------------------------------------

fn sf_symbol(icon: String) -> Option(String) {
  case icon {
    "add" -> Some("plus")
    "refresh" -> Some("arrow.clockwise")
    "sunny" -> Some("sun.max.fill")
    "play" -> Some("play.fill")
    "flash" -> Some("bolt.fill")
    "stop" -> Some("stop.fill")
    _ -> None
  }
}

pub type Variant {
  Plain
  Primary
  Danger
}

/// A button; start from `button(title, on_press)`.
pub type Button {
  Button(
    title: String,
    on_press: fn() -> Nil,
    variant: Variant,
    disabled: Bool,
    icon: Option(String),
    compact: Bool,
    grow: Bool,
  )
}

pub fn button(title: String, on_press: fn() -> Nil) -> Button {
  Button(
    title:,
    on_press:,
    variant: Plain,
    disabled: False,
    icon: None,
    compact: False,
    grow: False,
  )
}

pub fn primary(button: Button) -> Button {
  Button(..button, variant: Primary)
}

pub fn danger(button: Button) -> Button {
  Button(..button, variant: Danger)
}

pub fn disabled(button: Button, disabled: Bool) -> Button {
  Button(..button, disabled:)
}

pub fn with_icon(button: Button, icon: String) -> Button {
  Button(..button, icon: Some(icon))
}

pub fn compact(button: Button) -> Button {
  Button(..button, compact: True)
}

pub fn grow(button: Button) -> Button {
  Button(..button, grow: True)
}

type Modifier

@external(javascript, "./theme_ffi.mjs", "modifier")
fn modifier(name: String, argument: a) -> Modifier

@external(javascript, "./theme_ffi.mjs", "frame_max_width")
fn frame_max_width(width: Int) -> Modifier

type MatchContents

@external(javascript, "./theme_ffi.mjs", "match_vertical")
fn match_vertical() -> MatchContents

fn native_glass_button(button: Button) -> Element {
  let primary = button.variant == Primary
  let danger = button.variant == Danger
  let tint = case button.variant {
    Danger -> rose
    Primary -> moon
    Plain -> moon_soft
  }
  let modifiers = [
    modifier("buttonStyle", case primary {
      True -> "glassProminent"
      False -> "glass"
    }),
    modifier("controlSize", case button.compact {
      True -> "regular"
      False -> "large"
    }),
    modifier("tint", tint),
    modifier("disabled", button.disabled),
    ..case button.grow {
      True -> [frame_max_width(10_000)]
      False -> []
    }
  ]
  native.swift_host(
    [
      case button.grow {
        True -> native.prop("matchContents", match_vertical())
        False -> native.prop("matchContents", True)
      },
      native.prop("colorScheme", "dark"),
      native.prop("ignoreSafeArea", "all"),
      native.prop("seedColor", tint),
      native.style([
        s.min_height(case button.compact {
          True -> 38
          False -> 48
        }),
        ..case button.grow {
          // A SwiftUI Host is a React Native child. Its SwiftUI frame only
          // fills the width proposed by React Native, so it must participate
          // in the row's flex layout before `frame(maxWidth:)` can expand it.
          True -> [s.flex(1), s.align_self("stretch")]
          False -> [s.align_self("center")]
        },
      ]),
    ],
    [
      native.swift_button(
        list.flatten([
          [
            native.prop("label", button.title),
            native.prop("role", case danger {
              True -> "destructive"
              False -> "default"
            }),
            native.on_press(button.on_press),
            native.list_prop("modifiers", modifiers),
          ],
          case option.then(button.icon, sf_symbol) {
            Some(symbol) -> [native.prop("systemImage", symbol)]
            None -> []
          },
        ]),
      ),
    ],
  )
}

fn fallback_button(button: Button) -> Element {
  let primary = button.variant == Primary
  let background = case button.variant {
    Primary -> moon
    Danger -> "rgba(255,140,163,0.72)"
    Plain -> "rgba(255,231,183,0.08)"
  }
  let foreground = case primary {
    True -> night950
    False -> text
  }
  native.pressable(
    [
      native.role("button"),
      native.on_press(button.on_press),
      native.disabled(button.disabled),
      native.pressable_style(fn(pressed) {
        [
          s.flex_direction("row"),
          s.align_items("center"),
          s.justify_content("center"),
          s.gap(7),
          s.padding_horizontal(pick(button.compact, 12, 17)),
          s.min_height(pick(button.compact, 36, 44)),
          s.padding_vertical(pick(button.compact, 8, 11)),
          s.border_radius(999),
          s.cursor(case button.disabled {
            True -> "default"
            False -> "pointer"
          }),
          ..list.flatten([
            case button.grow {
              True -> [s.flex(1), s.align_self("stretch")]
              False -> []
            },
            [
              s.background_color(background),
              s.border_width(pick(primary, 0, 1)),
              s.border_color("rgba(255,231,183,0.12)"),
              s.opacity(case button.disabled, pressed {
                True, _ -> 0.45
                False, True -> 0.72
                False, False -> 1.0
              }),
              s.scale(case pressed {
                True -> 0.97
                False -> 1.0
              }),
            ],
          ])
        ]
      }),
    ],
    [
      case button.icon {
        Some(name) -> icon(name, pick(button.compact, 14, 17), foreground)
        None -> native.none()
      },
      native.text(
        [
          native.style([
            s.font_size(pick(button.compact, 12, 15)),
            s.font_weight("800"),
            s.color(foreground),
          ]),
        ],
        button.title,
      ),
    ],
  )
}

fn pick(condition: Bool, when_true: a, when_false: a) -> a {
  case condition {
    True -> when_true
    False -> when_false
  }
}

pub fn render(button: Button) -> Element {
  case liquid_glass() {
    True -> native_glass_button(button)
    False -> fallback_button(button)
  }
}

pub fn icon_button(
  icon_name: String,
  label: String,
  on_press: fn() -> Nil,
  disabled: Bool,
  color: String,
) -> Element {
  native.pressable(
    [
      native.role("button"),
      native.label(label),
      native.on_press(on_press),
      native.disabled(disabled),
      native.pressable_style(fn(pressed) {
        [
          s.width(40),
          s.height(40),
          s.border_radius(13),
          s.align_items("center"),
          s.justify_content("center"),
          s.cursor(pick(disabled, "default", "pointer")),
          s.background_color(pick(
            pressed,
            "rgba(245,207,135,0.18)",
            "rgba(255,231,183,0.07)",
          )),
          s.border_width(1),
          s.border_color("rgba(255,231,183,0.11)"),
          s.opacity(pick(disabled, 0.45, 1.0)),
        ]
      }),
    ],
    [icon(icon_name, 20, color)],
  )
}

// Toggle ----------------------------------------------------------------------

pub type ToggleProps {
  ToggleProps(
    value: Bool,
    on_value_change: fn(Bool) -> Nil,
    disabled: Bool,
    label: String,
  )
}

pub fn toggle(
  value: Bool,
  label: String,
  disabled: Bool,
  on_value_change: fn(Bool) -> Nil,
) -> Element {
  native.component("Toggle", render_toggle)(ToggleProps(
    value:,
    on_value_change:,
    disabled:,
    label:,
  ))
}

fn render_toggle(props: ToggleProps) -> Element {
  let progress = native.use_animated(pick(props.value, 1.0, 0.0), 180)
  let thumb_offset = native.interpolate(progress, 0, 22)
  let track_color = native.interpolate(progress, "#332B38", "#245448")
  let border_color =
    native.interpolate(
      progress,
      "rgba(189,177,190,0.28)",
      "rgba(120,217,188,0.56)",
    )
  let thumb_color = native.interpolate(progress, "#CFC3CC", "#A9E8D5")
  native.pressable(
    [
      native.role("switch"),
      native.label(props.label),
      native.prop(
        "accessibilityState",
        ToggleAccessibility(checked: props.value, disabled: props.disabled),
      ),
      native.disabled(props.disabled),
      native.prop("hitSlop", 8),
      native.on_press(fn() { props.on_value_change(!props.value) }),
      native.pressable_style(fn(pressed) {
        [
          s.border_radius(999),
          s.cursor(pick(props.disabled, "default", "pointer")),
          s.outline_style("none"),
          s.opacity(pick(props.disabled, 0.42, 1.0)),
          s.scale(pick(pressed, 0.96, 1.0)),
        ]
      }),
    ],
    [
      native.animated_view(
        [
          native.style([
            s.width(52),
            s.height(30),
            s.padding(3),
            s.border_radius(999),
            s.justify_content("center"),
            s.raw("backgroundColor", track_color),
            s.border_width(1),
            s.raw("borderColor", border_color),
          ]),
        ],
        [
          native.animated_view(
            [
              native.style([
                s.width(22),
                s.height(22),
                s.border_radius(999),
                s.raw("backgroundColor", thumb_color),
                s.shadow_color("#090812"),
                s.shadow_opacity(0.42),
                s.shadow_radius(4),
                s.shadow_offset(0, 2),
                s.translate_x(thumb_offset),
              ]),
            ],
            [],
          ),
        ],
      ),
    ],
  )
}

/// Read by React Native as `{checked, disabled}`.
type ToggleAccessibility {
  ToggleAccessibility(checked: Bool, disabled: Bool)
}

// Inputs ----------------------------------------------------------------------

pub fn input_style(overrides: List(Style)) -> List(Style) {
  [
    s.min_height(46),
    s.padding_horizontal(14),
    s.padding_vertical(11),
    s.border_radius(13),
    s.border_width(1),
    s.border_color("rgba(255,231,183,0.15)"),
    s.font_size(14),
    s.color(text),
    s.background_color("rgba(13,9,18,0.58)"),
    s.outline_style("none"),
    ..overrides
  ]
}

pub fn picker_style(overrides: List(Style)) -> List(Style) {
  [
    s.min_height(46),
    s.padding_horizontal(12),
    s.border_radius(13),
    s.border_width(1),
    s.border_color("rgba(255,231,183,0.15)"),
    s.color(text),
    s.background_color(night800),
    s.cursor("pointer"),
    ..overrides
  ]
}

// Larger pieces ---------------------------------------------------------------

pub fn morning_sky(desktop: Bool, children: List(Element)) -> Element {
  native.view(
    [
      native.style([
        s.min_height(pick(desktop, 336, 268)),
        s.overflow("hidden"),
        s.border_radius(pick(desktop, 32, 26)),
        s.border_width(1),
        s.border_color("rgba(255,231,183,0.16)"),
        s.shadow_color("#1D0D18"),
        s.shadow_opacity(0.45),
        s.shadow_radius(30),
      ]),
    ],
    [
      native.linear_gradient(
        ["#3A263D", "#211B35", "#111425"],
        #(0.0, 0.0),
        #(1.0, 1.0),
        [native.style([s.position("absolute"), s.fill()])],
        [],
      ),
      native.linear_gradient(
        [moon_soft, moon, "#C67A58"],
        #(0.2, 0.1),
        #(0.9, 1.0),
        [
          native.style([
            s.position("absolute"),
            s.width(pick(desktop, 190, 142)),
            s.height(pick(desktop, 190, 142)),
            s.border_radius(999),
            s.right(pick(desktop, -26, -38)),
            s.top(pick(desktop, -44, -24)),
            s.opacity(0.94),
            s.shadow_color(moon),
            s.shadow_opacity(0.5),
            s.shadow_radius(48),
          ]),
        ],
        [],
      ),
      native.view(
        [
          native.style([
            s.position("absolute"),
            s.left(-50),
            s.right(-50),
            s.bottom(pick(desktop, -105, -90)),
            s.height(pick(desktop, 205, 170)),
            s.border_radius(999),
            s.background_color("rgba(41,42,69,0.96)"),
            s.border_top_width(1),
            s.border_top_color("rgba(255,255,255,0.09)"),
          ]),
        ],
        [],
      ),
      native.view(
        [
          native.style([
            s.position("absolute"),
            s.left_pct("18%"),
            s.right(-90),
            s.bottom(pick(desktop, -135, -112)),
            s.height(pick(desktop, 210, 175)),
            s.border_radius(999),
            s.background_color("rgba(21,24,48,0.98)"),
          ]),
        ],
        [],
      ),
      native.view(
        [
          native.style([
            s.flex(1),
            s.z_index(2),
            s.justify_content("center"),
            s.padding(pick(desktop, 28, 18)),
          ]),
        ],
        children,
      ),
    ],
  )
}

pub fn status_pill(title: String, connected: Bool, busy: Bool) -> Element {
  glass_panel(
    Glass(
      effect: "clear",
      interactive: False,
      tint: "rgba(52,39,60,0.42)",
      fallback_background: "rgba(255,255,255,0.07)",
      style: [
        s.flex_direction("row"),
        s.align_items("center"),
        s.gap(7),
        s.padding_horizontal(12),
        s.padding_vertical(8),
        s.border_radius(999),
        s.border_width(1),
        s.border_color("rgba(255,255,255,0.12)"),
      ],
    ),
    [
      case busy {
        True ->
          native.activity_indicator([
            native.prop("size", "small"),
            native.prop("color", moon),
          ])
        False ->
          native.view(
            [
              native.style([
                s.width(7),
                s.height(7),
                s.border_radius(4),
                s.background_color(pick(connected, mint, rose)),
              ]),
            ],
            [],
          )
      },
      native.text(
        [native.style([s.font_size(12), s.font_weight("700"), s.color(text)])],
        pick(busy, "Synchronisation", title),
      ),
    ],
  )
}

pub fn metric_row(
  icon_name: String,
  title: String,
  detail: String,
  color: String,
) -> Element {
  native.view(
    [
      native.style([s.flex_direction("row"), s.align_items("center"), s.gap(13)]),
    ],
    [
      native.view(
        [
          native.style([
            s.width(34),
            s.height(34),
            s.border_radius(10),
            s.align_items("center"),
            s.justify_content("center"),
            s.background_color("rgba(170,167,255,0.13)"),
          ]),
        ],
        [icon(icon_name, 18, color)],
      ),
      native.text(
        [
          native.style([
            s.flex(1),
            s.font_size(14),
            s.font_weight("600"),
            s.color(text),
          ]),
        ],
        title,
      ),
      native.text([native.style([s.font_size(14), s.color(muted)])], detail),
    ],
  )
}

pub fn screen_title(title: String, action: Button, desktop: Bool) -> Element {
  native.view(
    [
      native.style(
        list.flatten([
          [s.width_pct("100%")],
          case desktop {
            True -> [s.max_width(1180)]
            False -> []
          },
          [
            s.align_self("center"),
            s.flex_direction("row"),
            s.align_items("center"),
            s.padding_horizontal(pick(desktop, 32, 18)),
            s.padding_top(pick(desktop, 28, 8)),
            s.padding_bottom(pick(desktop, 20, 14)),
          ],
        ]),
      ),
    ],
    [
      native.text(
        [
          native.style([
            s.flex(1),
            s.font_size(pick(desktop, 34, 30)),
            s.font_weight("800"),
            s.color(text),
          ]),
        ],
        title,
      ),
      render(compact(action)),
    ],
  )
}
