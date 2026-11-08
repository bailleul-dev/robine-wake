import gleam/list
import gleam/option.{None, Some}
import robine/challenge
import robine/command
import robine/draft_test
import robine/id
import robine/level
import robine/light
import robine/nap
import robine/session
import robine/snapshot
import robine/store

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
  assert command.encode(command.StartNap(nap.length(20)), "id-1")
    == "{\"v\":1,\"id\":\"id-1\",\"op\":\"nap.start\",\"body\":{\"duration_minutes\":20}}"
  // The revision deleted is the one read with the alarm.
  assert command.encode(command.DeleteAlarm(draft_test.week_alarm()), "id-2")
    == "{\"v\":1,\"id\":\"id-2\",\"op\":\"alarm.delete\",\"body\":{\"alarm_id\":\"alarm-1\",\"revision\":4}}"
  let assert Ok(cadence) = light.cadence("0-4-0-6")
  let breathing =
    command.StartBreathing(
      cadence:,
      length: light.length(3),
      volume: level.percent(250),
    )
  assert command.encode(breathing, "id-3")
    == "{\"v\":1,\"id\":\"id-3\",\"op\":\"breathing.start\",\"body\":{\"cadence\":\"0-4-0-6\",\"duration_minutes\":3,\"volume_percent\":100}}"
  let night =
    command.SetNightRadio(enabled: True, start: "23:30", until: "06:45")
  assert command.encode(night, "id-4")
    == "{\"v\":1,\"id\":\"id-4\",\"op\":\"settings.night_radio.set\",\"body\":{\"enabled\":true,\"start\":\"23:30\",\"end\":\"06:45\"}}"
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

pub fn naps_last_from_one_to_180_minutes_test() {
  assert nap.minutes(nap.length(0)) == 1
  assert nap.minutes(nap.length(500)) == 180
  assert nap.ramp_minutes(nap.length(1)) == 1
  assert nap.ramp_minutes(nap.length(20)) == 2
}

pub fn a_challenge_outlives_its_session_harmlessly_test() {
  let ringing = fn(name) {
    session.Active(
      id: id.from_string(name),
      stage: session.Ringing,
      phase: session.GentlePhase,
      test_mode: False,
      phone_may_dismiss: True,
    )
  }
  let state =
    store.AppState(
      ..store.initial_state,
      challenge: Some(id.from_string("monday")),
    )
  let with = fn(active) {
    store.AppState(
      ..state,
      clock: snapshot.Snapshot(..state.clock, active_session: active),
    )
  }
  assert store.challenged(with(Some(ringing("monday"))))
    == Some(ringing("monday"))
  // Stopped on the clock, then another alarm rings: the old challenge is gone.
  assert store.challenged(with(None)) == None
  assert store.challenged(with(Some(ringing("tuesday")))) == None
}
