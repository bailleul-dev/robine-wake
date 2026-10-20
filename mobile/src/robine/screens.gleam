//// The four tabs: morning, alarms, evening and the clock itself.

import gleam/float
import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import redraw.{type Element}
import robine/actions
import robine/alarm.{type Alarm}
import robine/breathing.{type Breathing, Guided}
import robine/calendar
import robine/command
import robine/id
import robine/level
import robine/light
import robine/link
import robine/nap.{type Nap}
import robine/native
import robine/platform
import robine/session
import robine/snapshot
import robine/sound
import robine/store.{type AppState}
import robine/style.{type Style} as s
import robine/theme

const evening_volume_storage_key = "robineWake.eveningVolumePercent.v4"

fn pick(condition: Bool, when_true: a, when_false: a) -> a {
  case condition {
    True -> when_true
    False -> when_false
  }
}

fn ignore(_sent: a) -> Nil {
  Nil
}

/// The current time, refreshed every `every` milliseconds.
fn use_now(every: Int) -> Timestamp {
  let #(now, set_now) = redraw.use_lazy_state(platform.now)
  redraw.use_effect_(
    fn() {
      let timer = platform.set_interval(every, fn() { set_now(platform.now()) })
      fn() { platform.clear_interval(timer) }
    },
    #(),
  )
  now
}

fn valid_volume(value: String) -> Option(Int) {
  let number = case int.parse(value) {
    Ok(number) -> Ok(int.to_float(number))
    Error(Nil) -> float.parse(value)
  }
  case number {
    Ok(number) if number >=. 0.0 && number <=. 100.0 -> Some(float.round(number))
    _ -> None
  }
}

fn use_evening_volume() -> #(Int, fn(Int) -> Nil) {
  let #(volume, set_volume) = redraw.use_state(60)
  redraw.use_effect(
    fn() {
      {
        use stored <- promise.map(platform.storage_get(
          evening_volume_storage_key,
        ))
        let loaded =
          option.lazy_or(
            option.then(option.from_result(stored), valid_volume),
            fn() {
              platform.legacy_setting(evening_volume_storage_key)
              |> option.from_result
              |> option.then(valid_volume)
            },
          )
        case loaded {
          Some(loaded) -> {
            set_volume(loaded)
            platform.storage_set(
              evening_volume_storage_key,
              int.to_string(loaded),
            )
          }
          None -> Nil
        }
      }
      Nil
    },
    #(),
  )
  let update = fn(value: Int) {
    case value >= 0 && value <= 100 {
      True -> {
        set_volume(value)
        platform.storage_set(evening_volume_storage_key, int.to_string(value))
      }
      False -> Nil
    }
  }
  #(volume, update)
}

fn page_content_style(desktop: Bool, overrides: List(Style)) -> native.Prop {
  native.prop(
    "contentContainerStyle",
    style_object(
      list.flatten([
        [s.width_pct("100%")],
        pick(desktop, [s.max_width(1180)], []),
        [
          s.align_self("center"),
          s.padding_horizontal(pick(desktop, 32, 18)),
          s.padding_top(pick(desktop, 8, 0)),
          s.padding_bottom(pick(desktop, 40, 120)),
          s.gap(pick(desktop, 22, 18)),
        ],
        overrides,
      ]),
    ),
  )
}

type StyleObject

@external(javascript, "./screens_ffi.mjs", "style_object")
fn style_object(entries: List(Style)) -> StyleObject

fn scroll_page(
  desktop: Bool,
  overrides: List(Style),
  children: List(Element),
) -> Element {
  native.scroll_view(
    [
      page_content_style(desktop, overrides),
      native.prop("showsVerticalScrollIndicator", False),
    ],
    children,
  )
}

fn dashboard_card_style(desktop: Bool) -> List(Style) {
  pick(desktop, [s.flex_basis_pct("47%"), s.flex_grow(1), s.min_width(320)], [])
}

fn wrap_overrides(desktop: Bool) -> List(Style) {
  pick(
    desktop,
    [s.flex_direction("row"), s.flex_wrap("wrap"), s.align_items("flex-start")],
    [],
  )
}

pub fn connection_label(state: AppState) -> String {
  case state.connection {
    link.Searching -> "Recherche…"
    link.Joining -> "Connexion…"
    link.Online(link.Wifi) -> "Wi-Fi"
    link.Online(link.Nearby) -> "À proximité"
    link.Offline -> "Déconnecté"
  }
}

fn time_of(entry: Alarm) -> String {
  calendar.time_to_string(entry.settings.time)
}

fn schedule_of(entry: Alarm) -> String {
  alarm.days_label(entry)
}

fn ramp_of(entry: Alarm) -> Int {
  alarm.ramp_minutes(entry.settings.ramp)
}

fn row(styles: List(Style), children: List(Element)) -> Element {
  native.view([native.style([s.flex_direction("row"), ..styles])], children)
}

fn column(styles: List(Style), children: List(Element)) -> Element {
  native.view([native.style(styles)], children)
}

fn spacer() -> Element {
  native.view([native.style([s.flex(1)])], [])
}

fn label(styles: List(Style), content: String) -> Element {
  native.text([native.style(styles)], content)
}

fn header(eyebrow: Element, icon: Element) -> Element {
  row([s.align_items("center")], [eyebrow, spacer(), icon])
}

fn connection_pill(state: AppState) -> Element {
  theme.status_pill(
    connection_label(state),
    option.is_some(state.endpoint)
      || case state.connection {
      link.Online(_) -> True
      _ -> False
    },
    state.busy,
  )
}

// Morning ---------------------------------------------------------------------

fn brand_header(state: AppState) -> Element {
  row([s.align_items("center"), s.gap(12)], [
    theme.crescent(28),
    column([s.flex(1)], [
      label(
        [
          s.font_size(12),
          s.font_weight("800"),
          s.letter_spacing(1.8),
          s.color(theme.text),
        ],
        "ROBINE WAKE",
      ),
      label(
        [s.font_size(12), s.margin_top(2), s.color(theme.muted)],
        "Un réveil qui commence doucement",
      ),
    ]),
    connection_pill(state),
  ])
}

fn dashboard_greeting(state: AppState) -> Element {
  row([s.align_items("flex-end"), s.gap(18), s.padding_vertical(8)], [
    column([s.flex(1), s.gap(5)], [
      theme.eyebrow("Votre cocon", theme.moon),
      label(
        [
          s.font_size(32),
          s.font_weight("750"),
          s.letter_spacing(-0.8),
          s.color(theme.text),
        ],
        "Bonsoir",
      ),
      label(
        [s.font_size(14), s.color(theme.muted)],
        "Le réveil veille sur votre prochain matin.",
      ),
    ]),
    connection_pill(state),
  ])
}

fn clock_hero() -> Element {
  native.component("ClockHero", render_clock_hero)(Nil)
}

fn render_clock_hero(_props: Nil) -> Element {
  let now = use_now(30_000)
  column([s.align_items("center"), s.padding_vertical(20), s.gap(8)], [
    theme.eyebrow("Votre matin", theme.moon),
    label(
      [
        s.font_size(68),
        s.line_height(76),
        s.font_weight("500"),
        s.tabular_nums(),
        s.color(theme.text),
      ],
      platform.format_time(now),
    ),
    label([s.font_size(15), s.color(theme.muted)], platform.format_day(now)),
    label(
      [s.font_size(12), s.margin_top(8), s.color(theme.moon_soft)],
      "Tout est calme. Robine Wake garde le rythme.",
    ),
  ])
}

fn compact_alarm_row(alarm: Alarm) -> Element {
  row(
    [
      s.align_items("center"),
      s.gap(12),
      s.opacity(pick(alarm.settings.enabled, 1.0, 0.5)),
    ],
    [
      label(
        [
          s.font_size(23),
          s.font_weight("700"),
          s.tabular_nums(),
          s.color(theme.text),
        ],
        time_of(alarm),
      ),
      column([s.flex(1)], [
        label(
          [s.font_size(14), s.font_weight("700"), s.color(theme.text)],
          alarm.settings.label,
        ),
        label(
          [s.font_size(12), s.margin_top(2), s.color(theme.muted)],
          schedule_of(alarm),
        ),
      ]),
      theme.icon("chevron-forward", 16, theme.muted),
    ],
  )
}

pub fn active_session_card(session: session.Active) -> Element {
  theme.card(True, [], [
    column([s.gap(15)], [
      header(
        theme.eyebrow("Réveil en cours", theme.rose),
        theme.icon("pulse", 22, theme.rose),
      ),
      label(
        [s.font_size(20), s.font_weight("700"), s.color(theme.text)],
        case session.phase {
          session.StrongPhase -> "Le son de renfort joue"
          session.GentlePhase -> "La lumière sonore monte doucement"
        },
      ),
      row([s.flex_wrap("wrap"), s.gap(12)], [
        native.when(session.test_mode, fn() {
          theme.button("Arrêt direct", fn() {
            ignore(actions.send(command.Dismiss))
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
            |> theme.primary
            |> theme.render
          False ->
            row([s.align_items("center"), s.gap(7)], [
              theme.icon("phone-portrait-outline", 17, theme.muted),
              label(
                [s.font_size(11), s.font_weight("700"), s.color(theme.muted)],
                "Arrêt sur le réveil",
              ),
            ])
        },
      ]),
    ]),
  ])
}

fn clock_warning() -> Element {
  theme.card(False, [], [
    row([s.align_items("center"), s.gap(14)], [
      theme.icon("time", 28, theme.moon),
      column([s.flex(1)], [
        label(
          [s.font_size(17), s.font_weight("700"), s.color(theme.text)],
          "Heure à confirmer",
        ),
        label(
          [s.font_size(12), s.margin_top(3), s.color(theme.muted)],
          "Vérifiez l’heure avant d’activer un réveil.",
        ),
      ]),
      theme.button("Confirmer", fn() {
        ignore(actions.send(command.ConfirmClock))
      })
        |> theme.compact
        |> theme.render,
    ]),
  ])
}

fn next_wake_card(alarm: Option(Alarm)) -> Element {
  case alarm {
    None ->
      native.pressable([native.on_press(actions.create_alarm)], [
        theme.card(True, [], [
          column([s.align_items("center"), s.gap(14)], [
            theme.icon("alarm", 34, theme.moon),
            label(
              [s.font_size(17), s.font_weight("700"), s.color(theme.text)],
              "Préparer votre premier matin",
            ),
            label(
              [s.font_size(14), s.text_align("center"), s.color(theme.muted)],
              "Choisissez l’heure, le voyage sonore et la montée progressive.",
            ),
            theme.button("Créer une alarme", actions.create_alarm)
              |> theme.primary
              |> theme.render,
          ]),
        ]),
      ])
    Some(alarm) -> {
      native.pressable([native.on_press(fn() { actions.edit_alarm(alarm) })], [
        theme.card(True, [], [
          column([s.gap(15)], [
            row([], [
              theme.eyebrow("Prochain réveil", theme.moon),
              spacer(),
              theme.icon("chevron-forward", 17, theme.muted),
            ]),
            row([s.align_items("baseline")], [
              label(
                [
                  s.flex(1),
                  s.font_size(46),
                  s.font_weight("700"),
                  s.tabular_nums(),
                  s.color(theme.text),
                ],
                time_of(alarm),
              ),
              label(
                [
                  s.font_size(17),
                  s.font_weight("700"),
                  s.color(theme.moon_soft),
                ],
                alarm.settings.label,
              ),
            ]),
            row([s.gap(17)], [
              label(
                [s.font_size(12), s.color(theme.muted)],
                "◫ " <> schedule_of(alarm),
              ),
              label(
                [s.font_size(12), s.color(theme.muted)],
                "〽 " <> int.to_string(ramp_of(alarm)) <> " min avant",
              ),
            ]),
          ]),
        ]),
      ])
    }
  }
}

fn nap_card(nap: Option(Nap)) -> Element {
  native.component("NapCard", render_nap_card)(nap)
}

fn render_nap_card(planned: Option(Nap)) -> Element {
  let busy = store.use_app_state().busy
  let #(length, set_length) = redraw.use_state(nap.length(20))
  let minutes = nap.minutes(length)
  let now = use_now(15_000)
  let wake_time = nap.pending(planned, now)
  theme.card(False, [], [
    column([s.gap(14)], [
      header(
        theme.eyebrow("Sieste", theme.lavender),
        theme.icon("moon", 20, theme.lavender),
      ),
      ..case wake_time {
        Some(wake) -> {
          let left = duration.to_milliseconds(timestamp.difference(now, wake))
          let remaining = int.max(1, { left + 59_999 } / 60_000)
          [
            row([s.align_items("baseline"), s.gap(12)], [
              label(
                [
                  s.font_size(34),
                  s.font_weight("700"),
                  s.tabular_nums(),
                  s.color(theme.text),
                ],
                platform.format_time(wake),
              ),
              label(
                [s.flex(1), s.font_size(14), s.color(theme.muted)],
                "Réveil dans " <> int.to_string(remaining) <> " min",
              ),
            ]),
            theme.button("Annuler la sieste", fn() {
              ignore(actions.send(command.CancelNap))
            })
              |> theme.with_icon("stop")
              |> theme.grow
              |> theme.disabled(busy)
              |> theme.render,
          ]
        }
        None -> [
          row([], [
            label(
              [
                s.flex(1),
                s.font_size(14),
                s.font_weight("700"),
                s.color(theme.text),
              ],
              "Durée",
            ),
            label(
              [s.font_size(14), s.font_weight("700"), s.color(theme.lavender)],
              int.to_string(minutes) <> " min",
            ),
          ]),
          slider(
            minutes,
            5,
            120,
            5,
            theme.lavender,
            fn(minutes) { set_length(nap.length(minutes)) },
            None,
          ),
          label(
            [s.font_size(12), s.color(theme.muted)],
            "Le son monte pendant les "
              <> int.to_string(nap.ramp_minutes(length))
              <> " dernières minutes.",
          ),
          theme.button("Lancer la sieste", fn() {
            ignore(actions.send(command.StartNap(length)))
          })
            |> theme.with_icon("play")
            |> theme.primary
            |> theme.grow
            |> theme.disabled(busy)
            |> theme.render,
        ]
      }
    ]),
  ])
}

/// The community slider, rounding what it reports.
pub fn slider(
  value: Int,
  minimum: Int,
  maximum: Int,
  step: Int,
  color: String,
  on_change: fn(Int) -> Nil,
  on_complete: Option(fn(Int) -> Nil),
) -> Element {
  native.slider([
    native.prop("minimumValue", minimum),
    native.prop("maximumValue", maximum),
    native.prop("step", step),
    native.prop("value", value),
    native.prop("minimumTrackTintColor", color),
    native.prop("maximumTrackTintColor", "rgba(255,255,255,0.15)"),
    native.prop("thumbTintColor", color),
    native.prop("onValueChange", fn(next: Float) {
      on_change(float.round(next))
    }),
    native.prop("onSlidingComplete", fn(next: Float) {
      case on_complete {
        Some(complete) -> complete(float.round(next))
        None -> Nil
      }
    }),
  ])
}

fn alarm_list_card(alarms: List(Alarm)) -> Element {
  theme.card(False, [], [
    column([s.gap(14)], [
      header(
        theme.eyebrow("Vos alarmes", theme.lavender),
        theme.icon_button(
          "add",
          "Ajouter une alarme",
          actions.create_alarm,
          False,
          theme.lavender,
        ),
      ),
      ..case alarms {
        [] -> [
          label(
            [s.font_size(14), s.color(theme.muted)],
            "Aucune alarme enregistrée.",
          ),
        ]
        _ ->
          alarms
          |> list.take(3)
          |> list.index_map(fn(alarm, index) {
            [
              native.when(index > 0, theme.divider),
              native.pressable(
                [native.on_press(fn() { actions.edit_alarm(alarm) })],
                [compact_alarm_row(alarm)],
              ),
            ]
          })
          |> list.flatten
      }
    ]),
  ])
}

pub fn morning_screen(desktop: Bool) -> Element {
  native.component("MorningScreen", render_morning_screen)(desktop)
}

fn render_morning_screen(desktop: Bool) -> Element {
  let state = store.use_app_state()
  let alarms = state.clock.alarms
  let next = alarm.next(alarms)
  let session = case state.clock.active_session {
    Some(session) -> active_session_card(session)
    None -> native.none()
  }
  let warning = case state.clock.device {
    Some(snapshot.Device(clock_trusted: False, ..)) -> clock_warning()
    _ -> native.none()
  }
  scroll_page(desktop, [], case desktop {
    True -> [
      dashboard_greeting(state),
      row([s.align_items("flex-start"), s.gap(22)], [
        column([s.raw("flex", 0.82), s.gap(22)], [
          theme.morning_sky(True, [clock_hero()]),
          session,
          warning,
        ]),
        column([s.raw("flex", 1.18), s.gap(22)], [
          next_wake_card(next),
          nap_card(state.clock.nap),
          alarm_list_card(alarms),
        ]),
      ]),
    ]
    False -> [
      brand_header(state),
      theme.morning_sky(False, [clock_hero()]),
      session,
      warning,
      next_wake_card(next),
      nap_card(state.clock.nap),
      alarm_list_card(alarms),
    ]
  })
}

// Alarms ----------------------------------------------------------------------

fn confirm_full_alarm(alarm: Alarm) -> Nil {
  native.alert(
    "Lancer « " <> alarm.settings.label <> " » comme demain matin ?",
    "La séquence réelle démarre maintenant : montée pendant "
      <> int.to_string(ramp_of(alarm))
      <> " minutes, plafond pendant 5 minutes, puis son de renfort.",
    [
      #("Annuler", "cancel", fn() { Nil }),
      #("Lancer le réveil complet", "default", fn() {
        ignore(actions.send(command.TriggerAlarm(alarm.id)))
      }),
    ],
  )
}

fn confirm_strong(alarm: Alarm) -> Nil {
  native.alert(
    "Tester directement la phase forte de « " <> alarm.settings.label <> " » ?",
    "Le son de renfort démarrera au volume maximal configuré et les couleurs alterneront toutes les 3 secondes.",
    [
      #("Annuler", "cancel", fn() { Nil }),
      #("Lancer la phase forte", "default", fn() {
        ignore(actions.send(command.TriggerStrong(alarm.id)))
      }),
    ],
  )
}

fn alarm_card(state: AppState, alarm: Alarm) -> Element {
  theme.card(False, [], [
    column([s.gap(14), s.opacity(pick(alarm.settings.enabled, 1.0, 0.55))], [
      row([s.align_items("flex-start")], [
        native.pressable(
          [
            native.style([s.flex(1)]),
            native.on_press(fn() { actions.edit_alarm(alarm) }),
          ],
          [
            label(
              [
                s.font_size(38),
                s.font_weight("700"),
                s.tabular_nums(),
                s.color(theme.text),
              ],
              time_of(alarm),
            ),
            label(
              [
                s.font_size(17),
                s.font_weight("700"),
                s.margin_top(4),
                s.color(theme.text),
              ],
              alarm.settings.label,
            ),
            label(
              [s.font_size(14), s.margin_top(5), s.color(theme.muted)],
              schedule_of(alarm),
            ),
          ],
        ),
        theme.toggle(
          alarm.settings.enabled,
          "Activer l’alarme " <> alarm.settings.label,
          state.busy,
          fn(enabled) { actions.set_alarm_enabled(alarm, enabled) },
        ),
      ]),
      theme.divider(),
      row([s.align_items("center"), s.gap(9)], [
        label(
          [
            s.flex(1),
            s.font_size(12),
            s.font_weight("700"),
            s.color(theme.lavender),
          ],
          "🔈 Doux → 🔊 Renfort",
        ),
        theme.button("Réveil complet", fn() { confirm_full_alarm(alarm) })
          |> theme.with_icon("play")
          |> theme.primary
          |> theme.compact
          |> theme.disabled(state.busy)
          |> theme.render,
        theme.button("Fort", fn() { confirm_strong(alarm) })
          |> theme.with_icon("flash")
          |> theme.danger
          |> theme.compact
          |> theme.disabled(state.busy)
          |> theme.render,
      ]),
    ]),
  ])
}

pub fn alarms_screen(desktop: Bool) -> Element {
  native.component("AlarmsScreen", render_alarms_screen)(desktop)
}

fn render_alarms_screen(desktop: Bool) -> Element {
  let state = store.use_app_state()
  let alarms = state.clock.alarms
  column([s.flex(1)], [
    theme.screen_title(
      "Alarmes",
      theme.button("Ajouter", actions.create_alarm)
        |> theme.with_icon("add")
        |> theme.disabled(state.busy),
      desktop,
    ),
    scroll_page(desktop, [], [
      case alarms {
        [_, ..] ->
          native.view(
            [
              native.style([
                s.flex_direction(pick(desktop, "row", "column")),
                s.flex_wrap(pick(desktop, "wrap", "nowrap")),
                s.gap(16),
              ]),
            ],
            list.map(alarms, fn(alarm) {
              native.view(
                [
                  native.key(id.to_string(alarm.id)),
                  native.style(
                    pick(desktop, [s.flex_basis_pct("47%"), s.flex_grow(1)], []),
                  ),
                ],
                [alarm_card(state, alarm)],
              )
            }),
          )
        [] ->
          theme.card(True, [], [
            column(
              [s.align_items("center"), s.gap(16), s.padding_vertical(20)],
              [
                theme.crescent(50),
                label(
                  [s.font_size(22), s.font_weight("700"), s.color(theme.text)],
                  "Vos matins commencent ici",
                ),
                label(
                  [
                    s.font_size(14),
                    s.text_align("center"),
                    s.color(theme.muted),
                  ],
                  "Créez un réveil à deux étapes, doux puis plus présent si nécessaire.",
                ),
                theme.button("Créer une alarme", actions.create_alarm)
                  |> theme.primary
                  |> theme.render,
              ],
            ),
          ])
      },
    ]),
  ])
}

// Evening ---------------------------------------------------------------------

fn breathing_guide(breathing: Breathing) -> Element {
  native.component("BreathingGuide", render_breathing_guide)(breathing)
}

fn render_breathing_guide(breathing: Breathing) -> Element {
  let now = use_now(100)
  case breathing {
    breathing.Resting -> native.none()
    Guided(..) as guided -> breathing_circle(guided, now)
  }
}

/// The breath the strip shows, mirrored on screen: the circle swells with
/// the lungs.
fn breathing_circle(guided: Breathing, now: Timestamp) -> Element {
  let assert Guided(breath:, started:, ends:, ..) = guided
  let #(phase, progress, fullness) =
    breathing.phase_at(breath, breathing.elapsed_ms(started, now))
  let #(word, color) = case phase {
    breathing.Inhale -> #("Inspirez", theme.breathing_inhale_amber)
    breathing.HoldFull -> #("Retenez", theme.breathing_inhale_amber)
    breathing.Exhale -> #("Expirez", theme.breathing_exhale_rose)
    breathing.HoldEmpty -> #("Pause", theme.breathing_exhale_rose)
  }
  let phase_left =
    float.ceiling(
      int.to_float(breathing.phase_ms(breath, phase))
      *. { 1.0 -. progress }
      /. 1000.0,
    )
  let minutes_left = case ends {
    Some(ends) ->
      " · "
      <> int.to_string(int.max(
        0,
        float.round(float.ceiling(
          duration.to_seconds(timestamp.difference(now, ends)) /. 60.0,
        )),
      ))
      <> " min restantes"
    None -> ""
  }
  let size = 118.0 +. 54.0 *. fullness
  column([s.align_items("center"), s.gap(14), s.padding_vertical(8)], [
    native.view(
      [
        native.style([
          s.width(190),
          s.height(190),
          s.align_items("center"),
          s.justify_content("center"),
        ]),
      ],
      [
        native.view(
          [
            native.style([
              s.raw("width", size),
              s.raw("height", size),
              s.border_radius(999),
              s.background_color(color),
              s.opacity(0.82),
              s.shadow_color(color),
              s.shadow_opacity(0.5),
              s.shadow_radius(28),
            ]),
          ],
          [],
        ),
        label(
          [
            s.position("absolute"),
            s.font_size(20),
            s.font_weight("800"),
            s.color(theme.text),
          ],
          word,
        ),
      ],
    ),
    label(
      [s.font_size(13), s.color(theme.muted)],
      int.to_string(float.round(phase_left)) <> " s" <> minutes_left,
    ),
  ])
}

fn volume_control(
  volume: Int,
  active: Bool,
  set_volume: fn(Int) -> Nil,
) -> Element {
  column(
    [
      s.gap(8),
      s.padding(12),
      s.border_radius(13),
      s.background_color("rgba(255,255,255,0.05)"),
    ],
    [
      row([], [
        label(
          [
            s.flex(1),
            s.font_size(14),
            s.font_weight("700"),
            s.color(theme.text),
          ],
          pick(volume == 0, "🔇", "🔊") <> " Volume du jardin sonore",
        ),
        label(
          [s.font_size(14), s.font_weight("700"), s.color(theme.moon)],
          int.to_string(volume) <> " %",
        ),
      ]),
      slider(
        volume,
        0,
        100,
        5,
        theme.moon,
        set_volume,
        Some(fn(value) {
          case active {
            True ->
              ignore(
                actions.send(command.SetBreathingVolume(level.percent(value))),
              )
            False -> Nil
          }
        }),
      ),
    ],
  )
}

/// A labelled value above its slider.
fn minutes_slider(
  title: String,
  minutes: Int,
  most: Int,
  set_minutes: fn(Int) -> Nil,
) -> Element {
  column([s.gap(8)], [
    row([], [
      label(
        [
          s.flex(1),
          s.font_size(14),
          s.font_weight("700"),
          s.color(theme.text),
        ],
        title,
      ),
      label(
        [s.font_size(14), s.font_weight("700"), s.color(theme.moon)],
        int.to_string(minutes) <> " min",
      ),
    ]),
    slider(minutes, 1, most, 1, theme.moon, set_minutes, None),
  ])
}

pub fn evening_screen(desktop: Bool) -> Element {
  native.component("EveningScreen", render_evening_screen)(desktop)
}

fn render_evening_screen(desktop: Bool) -> Element {
  let state = store.use_app_state()
  column([s.flex(1)], [
    theme.screen_title(
      "Le soir",
      theme.button("Actualiser", fn() { ignore(actions.refresh()) })
        |> theme.with_icon("refresh")
        |> theme.disabled(state.busy),
      desktop,
    ),
    scroll_page(desktop, wrap_overrides(desktop), [
      theme.card(True, dashboard_card_style(desktop), [
        column([s.align_items("center"), s.gap(14)], [
          theme.crescent(44),
          theme.eyebrow("Rituel du soir", theme.twilight_rose),
          label(
            [s.font_size(23), s.font_weight("700"), s.color(theme.text)],
            "Ralentir avant la nuit",
          ),
          label(
            [s.font_size(14), s.text_align("center"), s.color(theme.muted)],
            "Une respiration guidée par le ruban lumineux, sur un jardin sonore, puis un coucher de soleil pour s’endormir.",
          ),
        ]),
      ]),
      breathing_card(desktop),
      light_card(desktop),
    ]),
  ])
}

fn breathing_card(desktop: Bool) -> Element {
  native.component("BreathingCard", render_breathing_card)(desktop)
}

fn render_breathing_card(desktop: Bool) -> Element {
  let state = store.use_app_state()
  let #(cadence_text, set_cadence_text) = redraw.use_state(light.coherence)
  let #(minutes, set_minutes) = redraw.use_state(10)
  let #(volume, set_volume) = use_evening_volume()
  let session = state.clock.breathing
  let #(active, active_volume, ambience, strip) = case session {
    Guided(volume:, ambience:, strip:, ..) -> #(
      True,
      Some(level.percent_to_int(volume)),
      ambience,
      strip,
    )
    breathing.Resting -> #(False, None, False, False)
  }
  let cadence = light.cadence(cadence_text)
  redraw.use_effect(
    fn() {
      case active_volume {
        Some(active_volume) if active_volume != volume ->
          set_volume(active_volume)
        _ -> Nil
      }
    },
    #(active_volume, volume),
  )
  theme.card(active, dashboard_card_style(desktop), [
    column([s.gap(15)], [
      header(
        theme.eyebrow(
          case session {
            Guided(cadence:, ..) -> "Respiration " <> cadence
            breathing.Resting -> "Respiration"
          },
          theme.twilight_rose,
        ),
        theme.icon("bulb", 21, theme.breathing_inhale_amber),
      ),
      ..case active {
        True -> [
          breathing_guide(session),
          label(
            [
              s.font_size(12),
              s.font_weight("700"),
              s.color(pick(ambience, theme.mint, theme.rose)),
            ],
            pick(
              ambience,
              "🔊  Jardin sonore pendant la séance",
              "🔇  La séance continue sans jardin sonore",
            ),
          ),
          case strip {
            True -> native.none()
            False ->
              label(
                [s.font_size(12), s.font_weight("700"), s.color(theme.rose)],
                "💡  Le réveil ne joint pas le ruban lumineux",
              )
          },
          volume_control(volume, True, set_volume),
          theme.button("Terminer la séance", fn() {
            ignore(actions.send(command.StopBreathing))
          })
            |> theme.with_icon("stop")
            |> theme.primary
            |> theme.disabled(state.busy)
            |> theme.render,
        ]
        False -> [
          label(
            [s.font_size(14), s.line_height(20), s.color(theme.muted)],
            "Poumons vides, seule la LED du centre luit en rouge très faible ; à l’inspiration, une fenêtre glisse vers les bouts du ruban et revient à l’expiration. La séance finit sur un souffle complet.",
          ),
          label(
            [s.font_size(14), s.font_weight("700"), s.color(theme.text)],
            "Cadence",
          ),
          native.text_input([
            native.prop("value", cadence_text),
            native.prop("onChangeText", set_cadence_text),
            native.prop("placeholder", light.coherence),
            native.prop("placeholderTextColor", theme.muted),
            native.prop("autoCapitalize", "none"),
            native.prop("autoCorrect", False),
            native.style(theme.input_style([])),
          ]),
          label(
            [
              s.font_size(12),
              s.color(pick(result.is_ok(cadence), theme.muted, theme.rose)),
            ],
            "Pause poumons vides - inspiration - pause poumons pleins - expiration, en secondes. 0-4-0-6 : cohérence cardiaque.",
          ),
          minutes_slider("Durée", minutes, 30, set_minutes),
          volume_control(volume, False, set_volume),
          theme.button("Commencer la séance", fn() {
            case cadence {
              Ok(cadence) ->
                ignore(
                  actions.send(command.StartBreathing(
                    cadence:,
                    length: light.length(minutes),
                    volume: level.percent(volume),
                  )),
                )
              Error(Nil) -> Nil
            }
          })
            |> theme.with_icon("play")
            |> theme.primary
            |> theme.disabled(state.busy || result.is_error(cadence))
            |> theme.render,
        ]
      }
    ]),
  ])
}

/// The clock's LED strip on its own: a sunrise to read by, a sunset to
/// fall asleep with.
fn light_card(desktop: Bool) -> Element {
  native.component("LightCard", render_light_card)(desktop)
}

fn render_light_card(desktop: Bool) -> Element {
  let busy = store.use_app_state().busy
  let #(minutes, set_minutes) = redraw.use_state(30)
  // The last reading, and when it arrived.
  let #(reading, set_reading) = redraw.use_state(None)
  let #(problem, set_problem) = redraw.use_state(None)
  let now = use_now(1000)
  let length = light.length(minutes)
  let settle = fn(sent: actions.Sent) {
    ignore(
      promise.map(sent, fn(result) {
        case result {
          Ok(command.LightReply(read)) -> {
            set_reading(Some(#(read, platform.now())))
            set_problem(None)
          }
          // Another command was on its way: the next reading will do.
          Error(command.Busy) -> Nil
          Error(failure) -> set_problem(Some(command.describe(failure)))
          Ok(_) -> Nil
        }
      }),
    )
  }
  let read = fn() { settle(actions.read(command.GetLight)) }
  redraw.use_effect_(
    fn() {
      read()
      let timer = platform.set_interval(10_000, read)
      fn() { platform.clear_interval(timer) }
    },
    #(),
  )
  let start = fn(program) {
    settle(actions.send(command.StartLightProgram(program)))
  }
  theme.card(False, dashboard_card_style(desktop), [
    column([s.gap(14)], [
      header(
        theme.eyebrow("Ruban lumineux", theme.moon),
        theme.icon("sunny", 20, theme.moon),
      ),
      strip_reading(reading, problem, now, read),
      minutes_slider("Durée", minutes, 60, set_minutes),
      row([s.gap(10)], [
        theme.button("Lever de soleil", fn() { start(light.Dawn(length)) })
          |> theme.with_icon("sunny")
          |> theme.grow
          |> theme.disabled(busy)
          |> theme.render,
        theme.button("Coucher de soleil", fn() { start(light.Sunset(length)) })
          |> theme.with_icon("moon")
          |> theme.grow
          |> theme.disabled(busy)
          |> theme.render,
      ]),
      theme.button("Éteindre", fn() { start(light.Off) })
        |> theme.with_icon("stop")
        |> theme.disabled(busy)
        |> theme.render,
    ]),
  ])
}

/// The strip as the ESP32 last rendered it, one swatch a pixel, with the
/// program and how far it went since.
fn strip_reading(
  reading: Option(#(light.Reading, Timestamp)),
  problem: Option(String),
  now: Timestamp,
  read: fn() -> Nil,
) -> Element {
  let #(pixels, title, detail, done) = case reading {
    None -> #(
      [],
      pick(option.is_some(problem), "Ruban non relevé", "Lecture du ruban…"),
      "",
      None,
    )
    Some(#(light.Reading(showing:, pixels:), read_at)) -> {
      let age = int.max(0, breathing.elapsed_ms(read_at, now))
      let #(detail, done) = case showing {
        light.Running(program:, elapsed_ms:, duration_ms:, ..) -> {
          let elapsed = int.min(elapsed_ms + age, duration_ms)
          let detail = case elapsed >= duration_ms, program {
            True, "dawn" -> "Plein jour, jusqu’à la prochaine commande"
            True, _ -> "Terminé"
            False, _ ->
              clock_label(elapsed) <> " / " <> clock_label(duration_ms)
          }
          #(
            detail,
            Some(int.to_float(elapsed) /. int.to_float(int.max(duration_ms, 1))),
          )
        }
        _ -> #("", None)
      }
      let read_label = "Relevé il y a " <> int.to_string(age / 1000) <> " s"
      #(
        pixels,
        light.describe(showing),
        case detail {
          "" -> read_label
          detail -> detail <> " · " <> read_label
        },
        done,
      )
    }
  }
  column([s.gap(8)], [
    row([s.align_items("center"), s.gap(10)], [
      column([s.flex(1), s.gap(2)], [
        label(
          [s.font_size(15), s.font_weight("700"), s.color(theme.text)],
          title,
        ),
        label([s.font_size(12), s.color(theme.muted), s.tabular_nums()], detail),
      ]),
      theme.button("Relever", read)
        |> theme.with_icon("refresh")
        |> theme.render,
    ]),
    row(
      [
        s.height(18),
        s.border_radius(6),
        s.overflow("hidden"),
        s.border_width(1),
        s.border_color(theme.night800),
        s.background_color(theme.night950),
      ],
      list.map(pixels, fn(colour) {
        native.view([native.style([s.flex(1), s.background_color(colour)])], [])
      }),
    ),
    case done {
      Some(done) ->
        row(
          [s.height(4), s.border_radius(2), s.background_color(theme.night800)],
          [
            native.view(
              [
                native.style([
                  s.width_pct(float.to_string(done *. 100.0) <> "%"),
                  s.border_radius(2),
                  s.background_color(theme.moon),
                ]),
              ],
              [],
            ),
          ],
        )
      None -> native.none()
    },
    case problem {
      Some(problem) ->
        label(
          [s.font_size(12), s.font_weight("700"), s.color(theme.rose)],
          "💡  " <> problem,
        )
      None -> native.none()
    },
  ])
}

/// `m:ss`.
fn clock_label(ms: Int) -> String {
  let seconds = ms / 1000
  int.to_string(seconds / 60)
  <> ":"
  <> string.pad_start(int.to_string(seconds % 60), 2, "0")
}

// System ----------------------------------------------------------------------

fn date_label(value: Option(Timestamp)) -> String {
  case value {
    Some(at) -> platform.format_date_time(at)
    None -> "—"
  }
}

fn remote_button_card(state: AppState, desktop: Bool) -> Element {
  let snapshot.RemoteButtons(pairing:, buttons:) = state.clock.remote
  theme.card(pairing, dashboard_card_style(desktop), [
    column([s.gap(15)], [
      row([], [
        theme.eyebrow("Bouton déporté", theme.mint),
        spacer(),
        theme.icon("radio-button-on", 21, theme.mint),
      ]),
      label(
        [s.font_size(14), s.line_height(20), s.color(theme.muted)],
        "Arrêt sécurisé en LoRa 868 MHz. Le Raspberry écoute directement le bouton, sans Internet ni routeur. Chaque appui est signé et protégé contre le rejeu.",
      ),
      ..list.append(
        list.map(buttons, fn(button) {
          row([s.align_items("center"), s.gap(12)], [
            theme.icon("shield-checkmark", 21, theme.mint),
            column([s.flex(1)], [
              label(
                [s.font_size(14), s.font_weight("700"), s.color(theme.text)],
                button.name,
              ),
              label(
                [s.font_size(12), s.color(theme.muted)],
                case button.last_seen_at {
                  Some(_) -> date_label(button.last_seen_at)
                  None -> "Jamais utilisé"
                },
              ),
            ]),
            theme.button("Oublier", fn() {
              ignore(actions.send(command.RemoveButton(button.id)))
            })
              |> theme.danger
              |> theme.compact
              |> theme.disabled(state.busy)
              |> theme.render,
          ])
        }),
        [
          case pairing {
            True ->
              label(
                [s.font_size(12), s.font_weight("700"), s.color(theme.moon)],
                "⌁ Association ouverte pendant 2 minutes. Maintenez maintenant le bouton physique enfoncé.",
              )
            False ->
              theme.button("Associer un bouton", fn() {
                ignore(actions.send(command.BeginButtonPairing))
              })
              |> theme.primary
              |> theme.disabled(state.busy)
              |> theme.render
          },
        ],
      )
    ]),
  ])
}

fn smartphone_dismiss_card(state: AppState, desktop: Bool) -> Element {
  let snapshot.SmartphoneDismiss(enabled:, locked:) =
    state.clock.smartphone_dismiss
  let locked = locked || option.is_some(state.clock.active_session)
  theme.card(!enabled, dashboard_card_style(desktop), [
    column([s.gap(13)], [
      header(
        theme.eyebrow("Arrêt de l’alarme", theme.rose),
        theme.toggle(
          enabled,
          "Autoriser l’arrêt de l’alarme depuis le smartphone",
          locked || state.busy,
          fn(value) {
            ignore(actions.send(command.SetSmartphoneDismiss(value)))
          },
        ),
      ),
      label(
        [s.font_size(14), s.line_height(20), s.color(theme.muted)],
        pick(
          enabled,
          "Le smartphone peut arrêter une alarme après le défi de réveil.",
          "L’alarme doit être arrêtée depuis le réveil ou le bouton déporté.",
        ),
      ),
      native.when(locked, fn() {
        row([s.align_items("center"), s.gap(8)], [
          theme.icon("lock-closed", 16, theme.moon),
          label(
            [s.font_size(11), s.font_weight("700"), s.color(theme.moon)],
            "Réglage verrouillé sur le réveil.",
          ),
        ])
      }),
    ]),
  ])
}

fn api_host(endpoint: Option(String)) -> String {
  case endpoint {
    None -> "À découvrir"
    Some(endpoint) -> {
      let without_scheme = case endpoint {
        "http://" <> rest | "https://" <> rest -> rest
        _ -> endpoint
      }
      case string.split(without_scheme, ":") {
        [host, ..] -> host
        [] -> without_scheme
      }
    }
  }
}

fn sounds_card(state: AppState, desktop: Bool) -> Element {
  theme.card(False, dashboard_card_style(desktop), [
    column([s.gap(15)], [
      theme.eyebrow("Bibliothèque sonore", theme.moon),
      ..list.map(list.take(state.clock.sounds, 8), fn(sound) {
        let strong = sound.is_strong(sound)
        row([s.align_items("center"), s.gap(12)], [
          theme.icon(
            pick(strong, "pulse", "musical-notes"),
            20,
            pick(strong, theme.rose, theme.moon),
          ),
          column([s.flex(1)], [
            label(
              [s.font_size(14), s.font_weight("600"), s.color(theme.text)],
              sound.title,
            ),
            case sound.artist {
              Some(artist) ->
                label([s.font_size(12), s.color(theme.muted)], artist)
              None -> native.none()
            },
          ]),
          label(
            [s.font_size(10), s.font_weight("800"), s.color(theme.muted)],
            string.uppercase(sound.intensity_label(sound.intensity)),
          ),
        ])
      })
    ]),
  ])
}

fn confirm_erase_history() -> Nil {
  native.alert("Effacer tout l’historique ?", "", [
    #("Annuler", "cancel", fn() { Nil }),
    #("Effacer", "destructive", fn() {
      ignore(actions.send(command.EraseHistory))
    }),
  ])
}

fn history_card(state: AppState, desktop: Bool) -> Element {
  case state.clock.recent_sessions {
    [] -> native.none()
    sessions ->
      theme.card(False, dashboard_card_style(desktop), [
        column([s.gap(14)], [
          header(
            theme.eyebrow("Matins récents", theme.lavender),
            theme.button("Effacer", confirm_erase_history)
              |> theme.danger
              |> theme.compact
              |> theme.render,
          ),
          ..list.map(list.take(sessions, 5), fn(session) {
            let dismissed = session.outcome == session.Dismissed
            theme.metric_row(
              pick(dismissed, "checkmark-circle", "time"),
              session.outcome_label(session.outcome),
              date_label(session.ended_at),
              pick(dismissed, theme.mint, theme.lavender),
            )
          })
        ]),
      ])
  }
}

pub fn system_screen(desktop: Bool) -> Element {
  native.component("SystemScreen", render_system_screen)(desktop)
}

fn render_system_screen(desktop: Bool) -> Element {
  let state = store.use_app_state()
  let device = state.clock.device
  let health = fn(part: fn(snapshot.Device) -> snapshot.Health) {
    case device {
      Some(device) -> snapshot.health_label(part(device))
      None -> "—"
    }
  }
  column([s.flex(1)], [
    theme.screen_title(
      "Le réveil",
      theme.button("Actualiser", fn() { ignore(actions.refresh()) })
        |> theme.with_icon("refresh")
        |> theme.disabled(state.busy),
      desktop,
    ),
    scroll_page(desktop, wrap_overrides(desktop), [
      theme.card(False, dashboard_card_style(desktop), [
        column([s.gap(14)], [
          theme.eyebrow("État du réveil", theme.mint),
          theme.metric_row(
            "radio",
            "Canal actif",
            connection_label(state),
            theme.mint,
          ),
          theme.metric_row(
            "code-working",
            "API locale",
            api_host(state.endpoint),
            theme.lavender,
          ),
          theme.metric_row(
            "wifi",
            "Réseau",
            health(fn(device) { device.network }),
            theme.lavender,
          ),
          theme.metric_row(
            "volume-high",
            "Audio",
            health(fn(device) { device.audio }),
            theme.moon,
          ),
          theme.metric_row(
            "cube",
            "Logiciel",
            option.then(device, fn(device) { device.firmware })
              |> option.unwrap("—"),
            theme.lavender,
          ),
        ]),
      ]),
      smartphone_dismiss_card(state, desktop),
      remote_button_card(state, desktop),
      sounds_card(state, desktop),
      history_card(state, desktop),
    ]),
  ])
}
