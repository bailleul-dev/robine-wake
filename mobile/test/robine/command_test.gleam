import gleam/list
import robine/challenge
import robine/command

pub fn replies_are_checked_against_their_request_test() {
  let ok = "{\"v\":1,\"id\":\"a\",\"status\":\"ok\",\"body\":{}}"
  assert command.reply(command.CancelNap, "a", ok) == Ok(command.Done)
  assert command.reply(command.CancelNap, "b", ok) == Error(command.Mismatched)
  assert command.reply(command.CancelNap, "a", "<html>")
    == Error(command.Unreadable)
  let future = "{\"v\":2,\"id\":\"a\",\"status\":\"ok\"}"
  assert command.reply(command.CancelNap, "a", future)
    == Error(command.UnsupportedVersion)
}

pub fn refusals_are_typed_test() {
  let refused =
    "{\"v\":1,\"id\":\"a\",\"status\":\"error\",\"error\":{\"code\":\"stale_revision\"}}"
  assert command.reply(command.CancelNap, "a", refused)
    == Error(command.Refused(command.StaleRevision))
  let unknown =
    "{\"v\":1,\"id\":\"a\",\"status\":\"error\",\"error\":{\"code\":\"overheated\"}}"
  let assert Error(failure) = command.reply(command.CancelNap, "a", unknown)
  assert failure == command.Refused(command.OtherRefusal("overheated"))
  assert command.describe(failure)
    == "Le réveil a refusé la commande (overheated)"
}

pub fn requests_carry_the_operation_and_its_body_test() {
  assert command.encode(command.StartNap(20), "id-1")
    == "{\"v\":1,\"id\":\"id-1\",\"op\":\"nap.start\",\"body\":{\"duration_minutes\":20}}"
  assert command.encode(command.DeleteAlarm("a", 3), "id-2")
    == "{\"v\":1,\"id\":\"id-2\",\"op\":\"alarm.delete\",\"body\":{\"alarm_id\":\"a\",\"revision\":3}}"
  assert !command.changes_state(command.GetState)
  assert command.changes_state(command.Dismiss)
}

pub fn three_right_answers_solve_the_challenge_test() {
  let solve = fn(progress: challenge.Progress) {
    let answered = challenge.answer(progress, progress.puzzle.answer)
    // A second tap on the same puzzle changes nothing.
    assert challenge.answer(answered, progress.puzzle.answer + 1) == answered
    challenge.advance(answered)
  }
  let assert challenge.Ask(second) = solve(challenge.start())
  assert second.step == 1
  let assert challenge.Ask(third) = solve(second)
  assert solve(third) == challenge.Solved
}

pub fn a_wrong_answer_asks_another_puzzle_of_the_same_step_test() {
  let first = challenge.start()
  let wrong = challenge.answer(first, first.puzzle.answer + 100)
  assert challenge.pause(wrong) == 700
  let assert challenge.Ask(again) = challenge.advance(wrong)
  assert again.step == 0
}

pub fn puzzles_have_four_choices_including_the_answer_test() {
  list.each([0, 1, 2], fn(step) {
    let puzzle = challenge.make_challenge(step)
    assert list.length(puzzle.options) == 4
    assert list.contains(puzzle.options, puzzle.answer)
    assert list.unique(puzzle.options) == puzzle.options
  })
}
