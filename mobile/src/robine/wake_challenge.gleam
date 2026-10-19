//// Three small puzzles to solve before the phone may stop the alarm.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import redraw.{type Element}
import redraw/ref
import robine/actions
import robine/challenge.{type Challenge}
import robine/command
import robine/native
import robine/platform
import robine/store
import robine/style.{type Style} as s
import robine/theme

fn label(styles: List(Style), content: String) -> Element {
  native.text([native.style(styles)], content)
}

fn progress_bar(step: Int) -> Element {
  native.view(
    [native.style([s.flex_direction("row"), s.gap(8)])],
    list.map(challenge.indices(challenge.steps), fn(index) {
      native.view(
        [
          native.key(int.to_string(index)),
          native.style([
            s.flex(1),
            s.height(7),
            s.border_radius(99),
            s.background_color(case int.compare(index, step) {
              order.Lt -> theme.mint
              order.Eq -> theme.moon
              order.Gt -> "rgba(255,255,255,0.14)"
            }),
          ]),
        ],
        [],
      )
    }),
  )
}

fn complete() -> Nil {
  case store.get_state().challenge {
    Some(_) -> {
      actions.close_challenge()
      actions.send(command.Dismiss)
      Nil
    }
    None -> Nil
  }
}

pub fn wake_challenge() -> Element {
  native.component("WakeChallenge", render_wake_challenge)(Nil)
}

fn render_wake_challenge(_props: Nil) -> Element {
  let state = store.use_app_state()
  let #(progress, set_progress) = redraw.use_lazy_state(challenge.start)
  let answering = redraw.use_ref_(False)

  let answer = fn(value: Int) {
    case ref.current(answering) {
      True -> Nil
      False -> {
        ref.assign(answering, True)
        let answered = challenge.answer(progress, value)
        set_progress(answered)
        platform.haptic(case answered {
          challenge.Answered(correct:, ..) -> correct
          challenge.Asking(..) -> False
        })
        platform.set_timeout(challenge.pause(answered), fn() {
          case challenge.advance(answered) {
            challenge.Solved -> complete()
            challenge.Ask(next) -> {
              set_progress(next)
              ref.assign(answering, False)
            }
          }
        })
        Nil
      }
    }
  }
  let feedback = case progress {
    challenge.Answered(correct:, ..) -> Some(correct)
    challenge.Asking(..) -> None
  }

  let test_mode = case state.clock.active_session {
    Some(session) -> session.test_mode
    None -> False
  }
  native.modal(
    [
      native.prop("visible", True),
      native.prop("animationType", "fade"),
      native.prop("presentationStyle", "fullScreen"),
    ],
    [
      native.linear_gradient(
        [theme.night950, theme.night900, "#3C342C"],
        #(0.5, 0.0),
        #(0.5, 1.0),
        [
          native.style([
            s.flex(1),
            s.padding_horizontal(22),
            s.padding_vertical(30),
          ]),
        ],
        [
          native.view([native.style([s.align_items("center"), s.gap(14)])], [
            theme.icon("sunny", 46, theme.moon),
            label(
              [s.font_size(34), s.font_weight("900"), s.color(theme.text)],
              "Bonjour",
            ),
            label(
              [
                s.font_size(14),
                s.text_align("center"),
                s.line_height(20),
                s.color(theme.muted),
              ],
              "Résolvez trois défis pour confirmer que vous êtes bien réveillé.",
            ),
            native.view([native.style([s.align_self("stretch")])], [
              progress_bar(progress.step),
            ]),
          ]),
          native.view([native.style([s.flex(1), s.justify_content("center")])], [
            challenge_card(
              progress.puzzle,
              feedback,
              ref.current(answering),
              answer,
            ),
          ]),
          native.when(test_mode, fn() {
            theme.button("Arrêt direct", complete) |> theme.render
          }),
          label(
            [s.text_align("center"), s.font_size(12), s.color(theme.muted)],
            "L’alarme continue jusqu’à la résolution des trois défis.",
          ),
        ],
      ),
    ],
  )
}

fn challenge_card(
  puzzle: Challenge,
  feedback: Option(Bool),
  answering: Bool,
  answer: fn(Int) -> Nil,
) -> Element {
  native.view(
    [
      native.style([
        s.padding(24),
        s.gap(22),
        s.border_radius(28),
        s.background_color("rgba(255,255,255,0.08)"),
        s.border_width(1),
        s.border_color("rgba(245,207,135,0.25)"),
      ]),
    ],
    [
      label(
        [
          s.text_align("center"),
          s.font_size(12),
          s.font_weight("800"),
          s.letter_spacing(1.2),
          s.color(theme.rose),
        ],
        "◉ " <> string.uppercase(challenge.kind_label(puzzle.kind)),
      ),
      label(
        [
          s.text_align("center"),
          s.font_size(34),
          s.line_height(43),
          s.font_weight("700"),
          s.color(theme.text),
        ],
        puzzle.prompt,
      ),
      label(
        [s.text_align("center"), s.font_size(14), s.color(theme.muted)],
        puzzle.instruction,
      ),
      native.view(
        [
          native.style([
            s.flex_direction("row"),
            s.flex_wrap("wrap"),
            s.gap(12),
          ]),
        ],
        list.map(puzzle.options, fn(option) {
          native.pressable(
            [
              native.key(int.to_string(option)),
              native.disabled(answering),
              native.on_press(fn() { answer(option) }),
              native.pressable_style(fn(pressed) {
                [
                  s.width_pct("48%"),
                  s.min_height(58),
                  s.border_radius(17),
                  s.align_items("center"),
                  s.justify_content("center"),
                  s.border_width(1),
                  s.border_color("rgba(255,255,255,0.1)"),
                  s.background_color(case pressed {
                    True -> "rgba(245,207,135,0.35)"
                    False -> "rgba(255,255,255,0.09)"
                  }),
                ]
              }),
            ],
            [
              label(
                [s.font_size(24), s.font_weight("900"), s.color(theme.text)],
                int.to_string(option),
              ),
            ],
          )
        }),
      ),
      case feedback {
        Some(correct) ->
          label(
            [
              s.text_align("center"),
              s.font_size(14),
              s.font_weight("700"),
              s.color(case correct {
                True -> theme.mint
                False -> theme.rose
              }),
            ],
            case correct {
              True -> "✓  Bien joué"
              False -> "↻  Presque — nouveau défi"
            },
          )
        None -> native.none()
      },
    ],
  )
}
