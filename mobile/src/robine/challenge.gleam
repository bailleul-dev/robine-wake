//// The small puzzles solved before the phone may stop an alarm.

import gleam/int
import gleam/list
import gleam/string

/// `[0, 1, …, count - 1]`.
pub fn indices(count: Int) -> List(Int) {
  int.range(from: count - 1, to: -1, with: [], run: list.prepend)
}

pub type ChallengeKind {
  Calculation
  Sequence
  Attention
}

pub type Challenge {
  Challenge(
    kind: ChallengeKind,
    prompt: String,
    instruction: String,
    answer: Int,
    options: List(Int),
  )
}

pub fn kind_label(kind: ChallengeKind) -> String {
  case kind {
    Calculation -> "Calcul"
    Sequence -> "Suite logique"
    Attention -> "Attention"
  }
}

/// Four distinct choices around the answer, including it.
fn choices_around(answer: Int) -> List(Int) {
  [-8, -6, -5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 6, 8]
  |> list.shuffle
  |> list.take(3)
  |> list.map(fn(offset) { answer + offset })
  |> list.prepend(answer)
  |> list.shuffle
}

pub fn make_challenge(step: Int) -> Challenge {
  case step % 3 {
    0 -> {
      let left = 14 + int.random(25)
      let right = 6 + int.random(19)
      let subtract = int.random(2) == 0
      let answer = case subtract {
        True -> left - right
        False -> left + right
      }
      let operator = case subtract {
        True -> " − "
        False -> " + "
      }
      Challenge(
        kind: Calculation,
        prompt: int.to_string(left)
          <> operator
          <> int.to_string(right)
          <> " = ?",
        instruction: "Choisissez le résultat",
        answer:,
        options: choices_around(answer),
      )
    }
    1 -> {
      let start = 2 + int.random(11)
      let increment = 2 + int.random(6)
      let values =
        indices(4)
        |> list.map(fn(index) { int.to_string(start + index * increment) })
      let answer = start + 4 * increment
      Challenge(
        kind: Sequence,
        prompt: string.join(values, "  ·  ") <> "  ·  ?",
        instruction: "Quel nombre vient ensuite ?",
        answer:,
        options: choices_around(answer),
      )
    }
    _ -> {
      let target = 3 + int.random(6)
      let amount = 2 + int.random(3)
      let other =
        list.repeat(Nil, 7 - amount)
        |> list.map(fn(_) { other_digit(target) })
      let digits = list.shuffle(list.append(list.repeat(target, amount), other))
      Challenge(
        kind: Attention,
        prompt: digits |> list.map(int.to_string) |> string.join("  "),
        instruction: "Combien de fois voyez-vous le chiffre "
          <> int.to_string(target)
          <> " ?",
        answer: amount,
        options: list.shuffle([1, 2, 3, 4]),
      )
    }
  }
}

fn other_digit(target: Int) -> Int {
  let digit = 1 + int.random(9)
  case digit == target {
    True -> other_digit(target)
    False -> digit
  }
}

// Progress --------------------------------------------------------------------

pub const steps = 3

pub type Progress {
  /// The puzzle of this step waits for an answer.
  Asking(step: Int, puzzle: Challenge)
  /// The answer shows for a moment before moving on.
  Answered(step: Int, puzzle: Challenge, correct: Bool)
}

pub type Next {
  Ask(Progress)
  Solved
}

pub fn start() -> Progress {
  Asking(step: 0, puzzle: make_challenge(0))
}

/// Only the first answer to a puzzle counts.
pub fn answer(progress: Progress, value: Int) -> Progress {
  case progress {
    Asking(step:, puzzle:) ->
      Answered(step:, puzzle:, correct: value == puzzle.answer)
    Answered(..) -> progress
  }
}

/// How long the answer shows, in milliseconds.
pub fn pause(progress: Progress) -> Int {
  case progress {
    Asking(..) -> 0
    Answered(correct: True, ..) -> 550
    Answered(correct: False, ..) -> 700
  }
}

/// A right answer moves to the next step; a wrong one asks a new puzzle.
pub fn advance(progress: Progress) -> Next {
  case progress {
    Asking(..) -> Ask(progress)
    Answered(step:, correct: True, ..) if step + 1 >= steps -> Solved
    Answered(step:, correct: True, ..) ->
      Ask(Asking(step: step + 1, puzzle: make_challenge(step + 1)))
    Answered(step:, correct: False, ..) ->
      Ask(Asking(step:, puzzle: make_challenge(step)))
  }
}
