import assert from "node:assert/strict";
import test from "node:test";
import {
  alarmToDraft,
  draftToPayload,
  draftValid,
  makeChallenge,
  pendingNapWakeTime,
  regularAlarms,
  scheduleLabel,
} from "../src/models";
import type { Alarm } from "../src/types";

test("alarm payload round-trip", () => {
  const alarm: Alarm = {
    id: "alarm-1",
    label: "Semaine",
    enabled: true,
    local_time: "06:45",
    days_of_week: [1, 2, 3, 4, 5],
    timezone: "Europe/Paris",
    sound_id: "rain",
    strong_sound_id: "storm",
    prewake_seconds: 1200,
    revision: 4,
    volume_profile: { start: 1, ceiling: 80, ramp_seconds: 1200 },
  };
  const draft = alarmToDraft(alarm, []);
  const payload = draftToPayload(draft);
  assert.equal(payload.local_time, "06:45");
  assert.equal(payload.prewake_seconds, 1200);
  assert.equal(payload.revision, 4);
  assert.deepEqual(payload.days_of_week, [1, 2, 3, 4, 5]);
  assert.deepEqual(payload.snooze, { enabled: false });
  assert.equal(draftValid(draft), true);
});

test("the nap alarm stays out of the regular alarm list", () => {
  const now = new Date("2026-01-15T13:00:00Z");
  const base = {
    label: "Sieste",
    local_time: "14:20:00",
    days_of_week: [],
    timezone: "Europe/Paris",
    sound_id: "rain",
    strong_sound_id: "storm",
  };
  const regular: Alarm = { ...base, id: "alarm-1", enabled: true };
  const nap: Alarm = {
    ...base,
    id: "nap",
    enabled: true,
    next_occurrences: ["2026-01-15T14:20:00+01:00"],
  };
  assert.deepEqual(regularAlarms([regular, nap]), [regular]);
  assert.equal(
    pendingNapWakeTime([regular, nap], now)?.toISOString(),
    "2026-01-15T13:20:00.000Z",
  );
  assert.equal(pendingNapWakeTime([regular], now), null);
  assert.equal(pendingNapWakeTime([{ ...nap, enabled: false }], now), null);
  assert.equal(
    pendingNapWakeTime([nap], new Date("2026-01-15T13:30:00Z")),
    null,
  );
});

test("schedule labels", () => {
  assert.equal(scheduleLabel({ days_of_week: [1, 2, 3, 4, 5] }), "En semaine");
  assert.equal(scheduleLabel({ days_of_week: [6, 7] }), "Le week-end");
  assert.equal(scheduleLabel({ days_of_week: [1, 2, 5] }), "L · M · V");
});

test("challenges have four choices including the answer", () => {
  for (let step = 0; step < 3; step += 1) {
    const challenge = makeChallenge(step);
    assert.equal(challenge.options.length, 4);
    assert.equal(challenge.options.includes(challenge.answer), true);
  }
});
