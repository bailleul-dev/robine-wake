//// The alarm editor, a sheet above the app with its own copy of the draft.

import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import redraw.{type Element}
import robine/actions
import robine/alarm.{type Alarm}
import robine/calendar
import robine/challenge
import robine/command
import robine/draft.{type Draft, type Origin, Draft} as alarm_draft
import robine/id.{type Id}
import robine/level
import robine/native
import robine/sound.{type Sound}
import robine/store
import robine/style.{type Style} as s
import robine/theme

type SetDraft =
  fn(fn(Draft) -> Draft) -> Nil

fn pick(condition: Bool, when_true: a, when_false: a) -> a {
  case condition {
    True -> when_true
    False -> when_false
  }
}

fn ignore(_sent: a) -> Nil {
  Nil
}

fn row(styles: List(Style), children: List(Element)) -> Element {
  native.view([native.style([s.flex_direction("row"), ..styles])], children)
}

fn column(styles: List(Style), children: List(Element)) -> Element {
  native.view([native.style(styles)], children)
}

fn label(styles: List(Style), content: String) -> Element {
  native.text([native.style(styles)], content)
}

fn heading(number: String, title: String, subtitle: String) -> Element {
  row([s.align_items("center"), s.gap(12)], [
    native.view(
      [
        native.style([
          s.width(28),
          s.height(28),
          s.border_radius(14),
          s.align_items("center"),
          s.justify_content("center"),
          s.background_color(theme.moon),
        ]),
      ],
      [
        label(
          [s.font_size(12), s.font_weight("900"), s.color(theme.night950)],
          number,
        ),
      ],
    ),
    column([s.flex(1)], [
      label([s.font_size(17), s.font_weight("700"), s.color(theme.text)], title),
      label([s.font_size(12), s.margin_top(2), s.color(theme.muted)], subtitle),
    ]),
  ])
}

fn value_slider(
  title: String,
  value: Int,
  minimum: Int,
  maximum: Int,
  suffix: String,
  color: String,
  on_change: fn(Int) -> Nil,
) -> Element {
  column([s.gap(9)], [
    row([], [
      label([s.flex(1), s.font_size(14), s.color(theme.text)], title),
      label(
        [s.font_size(14), s.font_weight("800"), s.color(color)],
        int.to_string(value) <> suffix,
      ),
    ]),
    native.slider([
      native.prop("minimumValue", minimum),
      native.prop("maximumValue", maximum),
      native.prop("step", 1),
      native.prop("value", value),
      native.prop("minimumTrackTintColor", color),
      native.prop("maximumTrackTintColor", "rgba(255,255,255,0.14)"),
      native.prop("thumbTintColor", color),
      native.prop("onValueChange", fn(next: Float) {
        on_change(float.round(next))
      }),
    ]),
  ])
}

fn sound_picker(
  value: Id(Sound),
  title: String,
  detail: String,
  icon: String,
  color: String,
  sounds: List(Sound),
  on_change: fn(Id(Sound)) -> Nil,
) -> Element {
  row([s.align_items("center"), s.gap(13)], [
    native.view(
      [
        native.style([
          s.width(42),
          s.height(42),
          s.border_radius(13),
          s.align_items("center"),
          s.justify_content("center"),
          s.background_color("rgba(245,207,135,0.12)"),
        ]),
      ],
      [theme.icon(icon, 21, color)],
    ),
    column([s.flex(1)], [
      label([s.font_size(14), s.font_weight("700"), s.color(theme.text)], title),
      label([s.font_size(12), s.color(theme.muted)], detail),
    ]),
    native.picker(
      [
        native.prop("selectedValue", id.to_string(value)),
        native.prop("onValueChange", fn(text: String) {
          case id.find(sounds, text, fn(sound) { sound.id }) {
            Ok(sound) -> on_change(sound.id)
            Error(Nil) -> Nil
          }
        }),
        native.prop("dropdownIconColor", theme.moon),
        native.style(theme.picker_style([s.width(180)])),
      ],
      list.map(sounds, fn(sound) { #(id.to_string(sound.id), sound.title) }),
    ),
  ])
}

/// Moves the draft to this time; pickers only offer valid hours and minutes.
fn set_time(set_draft: SetDraft, hour: Int, minute: Int) -> Nil {
  set_draft(fn(current) {
    Draft(
      ..current,
      time: calendar.time(hour, minute) |> result.unwrap(current.time),
    )
  })
}

fn time_card(draft: Draft, set_draft: SetDraft) -> Element {
  let hour = calendar.hour(draft.time)
  let minute = calendar.minute(draft.time)
  theme.card(True, [], [
    column([s.align_items("center"), s.gap(12)], [
      theme.eyebrow("Quand commence le matin ?", theme.moon),
      case native.web() {
        True ->
          row([s.align_items("center"), s.gap(8)], [
            number_picker(hour, 24, fn(hour) {
              set_time(set_draft, hour, minute)
            }),
            label(
              [s.font_size(28), s.font_weight("700"), s.color(theme.moon)],
              ":",
            ),
            number_picker(minute, 60, fn(minute) {
              set_time(set_draft, hour, minute)
            }),
          ])
        False ->
          native.date_time_picker([
            native.prop("value", native.date_at(hour, minute)),
            native.prop("mode", "time"),
            native.prop("display", "spinner"),
            native.prop("themeVariant", "dark"),
            native.prop("minuteInterval", 1),
            native.on_time_change(fn(hour, minute) {
              set_time(set_draft, hour, minute)
            }),
            native.style([s.height(126), s.width(260)]),
          ])
      },
      native.text_input([
        native.prop("value", draft.label),
        native.prop("onChangeText", fn(label: String) {
          set_draft(fn(current) { Draft(..current, label:) })
        }),
        native.prop("placeholder", "Nom du réveil"),
        native.prop("placeholderTextColor", theme.muted),
        native.prop("textAlign", "center"),
        native.style(
          theme.input_style([
            s.align_self("stretch"),
            s.font_size(17),
            s.font_weight("700"),
          ]),
        ),
      ]),
      row([s.align_self("stretch"), s.align_items("center")], [
        label(
          [
            s.flex(1),
            s.font_size(14),
            s.font_weight("700"),
            s.color(theme.text),
          ],
          "Alarme active",
        ),
        theme.toggle(draft.enabled, "Alarme active", False, fn(enabled) {
          set_draft(fn(current) { Draft(..current, enabled:) })
        }),
      ]),
    ]),
  ])
}

fn number_picker(value: Int, count: Int, on_change: fn(Int) -> Nil) -> Element {
  native.picker(
    [
      native.prop("selectedValue", value),
      native.prop("onValueChange", on_change),
      native.style(
        theme.picker_style([s.width(104), s.font_size(18), s.font_weight("800")]),
      ),
    ],
    list.map(challenge.indices(count), fn(number) {
      #(number, calendar.two_digits(number))
    }),
  )
}

fn schedule_card(draft: Draft, set_draft: SetDraft) -> Element {
  theme.card(False, [], [
    column([s.gap(16)], [
      heading("1", "Votre rythme", "Les jours où cette alarme revient"),
      row(
        [s.gap(7)],
        list.map(calendar.week, fn(day) {
          let selected = set.contains(draft.days, day)
          native.pressable(
            [
              native.key(int.to_string(calendar.number(day))),
              native.label(calendar.name(day)),
              native.on_press(fn() { set_draft(alarm_draft.toggle_day(_, day)) }),
              native.style([
                s.flex(1),
                s.height(38),
                s.border_radius(19),
                s.align_items("center"),
                s.justify_content("center"),
                s.background_color(pick(
                  selected,
                  theme.moon,
                  "rgba(255,255,255,0.06)",
                )),
              ]),
            ],
            [
              label(
                [
                  s.font_size(12),
                  s.font_weight("800"),
                  s.color(pick(selected, theme.night950, theme.muted)),
                ],
                calendar.initial(day),
              ),
            ],
          )
        }),
      ),
      label([s.font_size(12), s.color(theme.muted)], "🌍 " <> draft.timezone),
    ]),
  ])
}

fn sound_card(
  draft: Draft,
  set_draft: SetDraft,
  sounds: List(Sound),
) -> Element {
  theme.card(False, [], [
    column([s.gap(16)], [
      heading("2", "Voyage sonore", "Doux d’abord, plus présent ensuite"),
      sound_picker(
        draft.sound,
        "Première lumière",
        "Commence en douceur",
        "sunny",
        theme.moon,
        sounds,
        fn(sound) { set_draft(fn(current) { Draft(..current, sound:) }) },
      ),
      theme.divider(),
      sound_picker(
        draft.strong_sound,
        "Renfort",
        "Prend le relais si nécessaire",
        "pulse",
        theme.rose,
        sounds,
        fn(strong_sound) {
          set_draft(fn(current) { Draft(..current, strong_sound:) })
        },
      ),
      label(
        [s.font_size(12), s.color(theme.muted)],
        "◉ La sortie locale du réveil reste prioritaire pendant une alarme.",
      ),
    ]),
  ])
}

fn light_card(draft: Draft, set_draft: SetDraft) -> Element {
  theme.card(False, [], [
    column([s.gap(16)], [
      heading(
        "3",
        "Lever de soleil",
        "Le ruban lumineux s’éclaire pendant la montée, du premier orange à la lumière du jour à l’heure du réveil",
      ),
      row([s.align_items("center")], [
        label(
          [
            s.flex(1),
            s.font_size(14),
            s.font_weight("700"),
            s.color(theme.text),
          ],
          "Allumer le ruban",
        ),
        theme.toggle(draft.dawn, "Allumer le ruban", False, fn(dawn) {
          set_draft(fn(current) { Draft(..current, dawn:) })
        }),
      ]),
      ..case draft.dawn {
        False -> []
        True -> [
          native.picker(
            [
              native.prop(
                "selectedValue",
                alarm.afterwards_code(draft.afterwards),
              ),
              native.prop("onValueChange", fn(code: String) {
                case alarm.afterwards_from_code(code) {
                  Ok(afterwards) ->
                    set_draft(fn(current) { Draft(..current, afterwards:) })
                  Error(Nil) -> Nil
                }
              }),
              native.prop("dropdownIconColor", theme.moon),
              native.style(theme.picker_style([])),
            ],
            list.map([alarm.TurnOff, alarm.Leave], fn(choice) {
              #(alarm.afterwards_code(choice), alarm.afterwards_label(choice))
            }),
          ),
        ]
      }
    ]),
  ])
}

fn ramp_card(draft: Draft, set_draft: SetDraft) -> Element {
  let ceiling = level.percent_to_int(draft.ceiling_volume)
  theme.card(False, [], [
    column([s.gap(18)], [
      heading(
        "4",
        "Montée progressive",
        "Le plafond est atteint à l’heure du réveil",
      ),
      value_slider(
        "Départ",
        level.percent_to_int(draft.start_volume),
        0,
        ceiling,
        "%",
        theme.mint,
        fn(value) {
          set_draft(fn(current) {
            Draft(..current, start_volume: level.percent(value))
          })
        },
      ),
      value_slider(
        "Plafond",
        ceiling,
        level.percent_to_int(draft.start_volume),
        100,
        "%",
        theme.rose,
        fn(value) {
          set_draft(fn(current) {
            Draft(..current, ceiling_volume: level.percent(value))
          })
        },
      ),
      value_slider(
        "Commencer avant l’heure",
        alarm.ramp_minutes(draft.ramp),
        1,
        60,
        " min avant",
        theme.lavender,
        fn(value) {
          set_draft(fn(current) { Draft(..current, ramp: alarm.ramp(value)) })
        },
      ),
      value_slider(
        "Volume du son de renfort",
        level.percent_to_int(draft.strong_volume),
        0,
        100,
        "%",
        theme.rose,
        fn(value) {
          set_draft(fn(current) {
            Draft(..current, strong_volume: level.percent(value))
          })
        },
      ),
      label(
        [s.font_size(12), s.line_height(17), s.color(theme.muted)],
        "Le volume reste au plafond pendant 5 minutes à l’heure choisie, puis le son de renfort prend le relais à son propre volume.",
      ),
      row(
        [s.height(24), s.align_items("flex-end"), s.gap(4)],
        list.map(challenge.indices(12), fn(index) {
          native.view(
            [
              native.key(int.to_string(index)),
              native.style([
                s.flex(1),
                s.raw("height", 5.0 +. int.to_float(index) *. 1.5),
                s.border_radius(999),
                s.background_color(pick(
                  index * 100 < 12 * ceiling,
                  theme.lavender,
                  "rgba(255,255,255,0.05)",
                )),
                s.opacity(0.35 +. int.to_float(index) *. 0.045),
              ]),
            ],
            [],
          )
        }),
      ),
    ]),
  ])
}

fn test_card(alarm_id: Id(Alarm)) -> Element {
  theme.card(False, [], [
    column([s.gap(14)], [
      row([s.align_items("center"), s.gap(13)], [
        theme.icon("play", 22, theme.moon),
        column([s.flex(1)], [
          label(
            [s.font_size(17), s.font_weight("700"), s.color(theme.text)],
            "Lancer ce réveil",
          ),
          label(
            [s.font_size(12), s.color(theme.muted)],
            "Reproduit exactement la séquence du matin",
          ),
        ]),
      ]),
      row([s.gap(10)], [
        column([s.flex(1)], [
          theme.button("Réveil complet", fn() {
            ignore(actions.send(command.TriggerAlarm(alarm_id)))
          })
          |> theme.grow
          |> theme.render,
        ]),
        column([s.flex(1)], [
          theme.button("Tester fort", fn() {
            ignore(actions.send(command.TriggerStrong(alarm_id)))
          })
          |> theme.primary
          |> theme.grow
          |> theme.render,
        ]),
      ]),
    ]),
  ])
}

fn confirm_delete(alarm: Alarm) -> Nil {
  native.alert("Supprimer cette alarme ?", "", [
    #("Annuler", "cancel", fn() { Nil }),
    #("Supprimer", "destructive", fn() { actions.delete_alarm(alarm) }),
  ])
}

fn origin_key(origin: Origin) -> String {
  case origin {
    alarm_draft.Existing(alarm) -> id.to_string(alarm.id)
    alarm_draft.New -> "new"
  }
}

pub fn alarm_editor(initial_draft: Draft) -> Element {
  native.keyed(
    origin_key(initial_draft.origin),
    native.component("AlarmEditor", render_alarm_editor)(initial_draft),
  )
}

fn render_alarm_editor(initial_draft: Draft) -> Element {
  let #(draft, set_draft) = redraw.use_state_(initial_draft)
  let state = store.use_app_state()
  let desktop = theme.desktop_width(theme.use_viewport_width())
  let editing = alarm_draft.editing(draft)
  let checked = alarm_draft.validate(draft)
  let width = [s.width_pct("100%"), ..pick(desktop, [s.max_width(960)], [])]
  native.modal(
    [
      native.prop("visible", True),
      native.prop("animationType", "slide"),
      native.prop("presentationStyle", "pageSheet"),
      native.prop("onRequestClose", actions.close_editor),
    ],
    [
      column([s.flex(1), s.background_color(theme.night950)], [
        theme.night_background(),
        row(
          list.append(width, [
            s.align_self("center"),
            s.padding_top(18),
            s.padding_horizontal(18),
            s.padding_bottom(12),
            s.align_items("center"),
          ]),
          [
            theme.button("Annuler", actions.close_editor)
              |> theme.compact
              |> theme.render,
            label(
              [
                s.flex(1),
                s.text_align("center"),
                s.font_size(17),
                s.font_weight("700"),
                s.color(theme.text),
              ],
              pick(editing, "Modifier l’alarme", "Nouvelle alarme"),
            ),
            native.view([native.style([s.width(76)])], []),
          ],
        ),
        native.scroll_view(
          [
            native.prop(
              "contentContainerStyle",
              style_object(
                list.append(width, [
                  s.align_self("center"),
                  s.padding(18),
                  s.padding_bottom(48),
                  s.gap(18),
                ]),
              ),
            ),
            native.prop("showsVerticalScrollIndicator", False),
          ],
          [
            time_card(draft, set_draft),
            schedule_card(draft, set_draft),
            sound_card(draft, set_draft, state.clock.sounds),
            light_card(draft, set_draft),
            ramp_card(draft, set_draft),
            case draft.origin {
              alarm_draft.Existing(alarm) -> test_card(alarm.id)
              alarm_draft.New -> native.none()
            },
            theme.button(
              pick(editing, "Enregistrer les changements", "Créer l’alarme"),
              fn() { actions.save_alarm(draft) },
            )
              |> theme.primary
              |> theme.grow
              |> theme.disabled(result.is_error(checked) || state.busy)
              |> theme.render,
            case checked {
              Error([problem, ..]) ->
                label(
                  [s.font_size(12), s.text_align("center"), s.color(theme.rose)],
                  alarm_draft.describe(problem),
                )
              _ -> native.none()
            },
            case draft.origin {
              alarm_draft.Existing(alarm) ->
                theme.button("Supprimer l’alarme", fn() {
                  confirm_delete(alarm)
                })
                |> theme.danger
                |> theme.grow
                |> theme.render
              alarm_draft.New -> native.none()
            },
          ],
        ),
      ]),
    ],
  )
}

type StyleObject

@external(javascript, "./screens_ffi.mjs", "style_object")
fn style_object(entries: List(Style)) -> StyleObject
