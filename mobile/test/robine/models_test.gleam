import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import robine/models
import robine/types.{Alarm, AlarmDraft, VolumeProfile}

fn alarm() -> types.Alarm {
  Alarm(
    id: "alarm-1",
    label: "Semaine",
    enabled: True,
    local_time: "06:45",
    days_of_week: [1, 2, 3, 4, 5],
    timezone: "Europe/Paris",
    sound_id: "rain",
    strong_sound_id: "storm",
    prewake_seconds: Some(1200),
    revision: Some(4),
    next_occurrences: [],
    volume_profile: VolumeProfile(
      start: Some(1),
      ceiling: Some(80),
      strong: None,
      ramp_seconds: Some(1200),
    ),
    light_profile: types.no_light_profile,
  )
}

pub fn alarm_payload_round_trip_test() {
  let draft = models.alarm_to_draft(Some(alarm()), [], "Europe/Paris")
  assert json.to_string(models.draft_to_payload(draft))
    == "{\"label\":\"Semaine\",\"enabled\":true,\"local_time\":\"06:45\",\"days_of_week\":[1,2,3,4,5],\"timezone\":\"Europe/Paris\",\"sound_id\":\"rain\",\"strong_sound_id\":\"storm\",\"prewake_seconds\":1200,\"volume_profile\":{\"start\":1,\"ceiling\":80,\"strong\":80,\"ramp_seconds\":1200},\"light_profile\":{\"enabled\":false,\"start_brightness\":1,\"end_brightness\":70,\"ramp_seconds\":900,\"end_behavior\":\"restore\"},\"dismiss_policy\":\"manual\",\"snooze\":{\"enabled\":false},\"revision\":4}"
  let louder = AlarmDraft(..draft, strong_volume: 95)
  assert json.to_string(models.draft_to_payload(louder))
    |> string.contains("\"strong\":95")
  assert models.draft_valid(draft)
}

pub fn nap_alarm_stays_out_of_the_regular_list_test() {
  let now = 1_768_482_000_000
  // 2026-01-15T13:00:00Z
  let regular =
    Alarm(..alarm(), id: "alarm-1", local_time: "14:20:00", days_of_week: [])
  let nap =
    Alarm(..regular, id: "nap", next_occurrences: ["2026-01-15T14:20:00+01:00"])
  assert models.regular_alarms([regular, nap]) == [regular]
  assert models.pending_nap_wake_time([regular, nap], now)
    == Some(1_768_483_200_000)
  assert models.pending_nap_wake_time([regular], now) == None
  assert models.pending_nap_wake_time([Alarm(..nap, enabled: False)], now)
    == None
  assert models.pending_nap_wake_time([nap], now + 1_800_000) == None
}

pub fn schedule_labels_test() {
  assert models.schedule_label([1, 2, 3, 4, 5]) == "En semaine"
  assert models.schedule_label([6, 7]) == "Le week-end"
  assert models.schedule_label([1, 2, 5]) == "L · M · V"
}

pub fn challenges_have_four_choices_including_the_answer_test() {
  list.each([0, 1, 2], fn(step) {
    let challenge = models.make_challenge(step)
    assert list.length(challenge.options) == 4
    assert list.contains(challenge.options, challenge.answer)
    assert list.unique(challenge.options) == challenge.options
  })
}
