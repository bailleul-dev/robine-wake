import type { Alarm, AlarmDraft, Challenge, Sound } from "./types";

export const weekdays = [
  { id: 1, short: "L", name: "Lundi" },
  { id: 2, short: "M", name: "Mardi" },
  { id: 3, short: "M", name: "Mercredi" },
  { id: 4, short: "J", name: "Jeudi" },
  { id: 5, short: "V", name: "Vendredi" },
  { id: 6, short: "S", name: "Samedi" },
  { id: 7, short: "D", name: "Dimanche" },
] as const;

export function twoDigits(value: number): string {
  return String(value).padStart(2, "0");
}

export function localTime(hour: number, minute: number): string {
  return `${twoDigits(hour)}:${twoDigits(minute)}`;
}

export function scheduleLabel(alarm: Pick<Alarm, "days_of_week">): string {
  const days = new Set(alarm.days_of_week);
  if (sameDays(days, [1, 2, 3, 4, 5])) return "En semaine";
  if (sameDays(days, [6, 7])) return "Le week-end";
  if (sameDays(days, [1, 2, 3, 4, 5, 6, 7])) return "Tous les jours";
  return weekdays
    .filter(({ id }) => days.has(id))
    .map(({ short }) => short)
    .join(" · ");
}

function sameDays(days: Set<number>, expected: number[]): boolean {
  return (
    days.size === expected.length && expected.every((day) => days.has(day))
  );
}

function defaultSound(
  sounds: Sound[],
  intensity: string,
  fallback: string,
): string {
  return (
    sounds.find((sound) => sound.intensity === intensity)?.id ??
    sounds[0]?.id ??
    fallback
  );
}

export function alarmToDraft(alarm: Alarm | null, sounds: Sound[]): AlarmDraft {
  const [rawHour, rawMinute] = (alarm?.local_time ?? "07:00").split(":");
  const hour = Number.parseInt(rawHour ?? "7", 10);
  const minute = Number.parseInt(rawMinute ?? "0", 10);
  const light = alarm?.light_profile;
  const timezone =
    Intl.DateTimeFormat().resolvedOptions().timeZone || "Europe/Paris";

  return {
    ...(alarm?.id ? { id: alarm.id } : {}),
    label: alarm?.label ?? "Mon réveil",
    enabled: alarm === null ? true : alarm.enabled,
    hour: Number.isFinite(hour) ? hour : 7,
    minute: Number.isFinite(minute) ? minute : 0,
    days: new Set(alarm?.days_of_week ?? [1, 2, 3, 4, 5]),
    timezone: alarm?.timezone ?? timezone,
    soundId: alarm?.sound_id ?? defaultSound(sounds, "gentle", "default"),
    strongSoundId:
      alarm?.strong_sound_id ?? defaultSound(sounds, "strong", "default"),
    startVolume: alarm?.volume_profile?.start ?? 15,
    ceilingVolume: alarm?.volume_profile?.ceiling ?? 85,
    prewakeMinutes: Math.max(
      1,
      Math.trunc(
        (alarm?.prewake_seconds ??
          alarm?.volume_profile?.ramp_seconds ??
          1200) / 60,
      ),
    ),
    snoozeEnabled: alarm?.snooze?.enabled ?? true,
    snoozeMinutes: Math.max(
      1,
      Math.trunc((alarm?.snooze?.duration_seconds ?? 480) / 60),
    ),
    snoozeMaximum: alarm?.snooze?.maximum ?? 3,
    ...(alarm?.revision !== undefined ? { revision: alarm.revision } : {}),
    lightEnabled: Boolean(light?.enabled),
    ...(light?.target_id ? { lightTargetId: light.target_id } : {}),
    ...(light?.target_name ? { lightTargetName: light.target_name } : {}),
    lightStartBrightness: light?.start_brightness ?? 1,
    lightEndBrightness: light?.end_brightness ?? 70,
    lightRampMinutes: Math.max(
      1,
      Math.trunc((light?.ramp_seconds ?? 900) / 60),
    ),
    lightEndBehavior: light?.end_behavior ?? "restore",
  };
}

export function draftValid(draft: AlarmDraft): boolean {
  return (
    draft.label.trim().length > 0 &&
    draft.days.size > 0 &&
    draft.startVolume <= draft.ceilingVolume &&
    draft.soundId.trim().length > 0 &&
    draft.strongSoundId.trim().length > 0 &&
    (!draft.lightEnabled || draft.lightTargetId !== undefined)
  );
}

export function draftToPayload(draft: AlarmDraft): Record<string, unknown> {
  return {
    label: draft.label.trim(),
    enabled: draft.enabled,
    local_time: localTime(draft.hour, draft.minute),
    days_of_week: [...draft.days].sort((left, right) => left - right),
    timezone: draft.timezone,
    sound_id: draft.soundId,
    strong_sound_id: draft.strongSoundId,
    prewake_seconds: 60 * draft.prewakeMinutes,
    volume_profile: {
      start: draft.startVolume,
      ceiling: draft.ceilingVolume,
      ramp_seconds: 60 * draft.prewakeMinutes,
    },
    light_profile: {
      enabled: draft.lightEnabled,
      start_brightness: draft.lightStartBrightness,
      end_brightness: draft.lightEndBrightness,
      ramp_seconds: 60 * draft.lightRampMinutes,
      end_behavior: draft.lightEndBehavior,
      ...(draft.lightTargetId ? { target_id: draft.lightTargetId } : {}),
      ...(draft.lightTargetName ? { target_name: draft.lightTargetName } : {}),
    },
    dismiss_policy: "manual",
    snooze: {
      enabled: draft.snoozeEnabled,
      duration_seconds: 60 * draft.snoozeMinutes,
      maximum: draft.snoozeMaximum,
    },
    ...(draft.revision !== undefined ? { revision: draft.revision } : {}),
  };
}

function randomInteger(maximum: number): number {
  return Math.floor(Math.random() * maximum);
}

function shuffled<T>(values: Iterable<T>): T[] {
  return [...values].sort(() => Math.random() - 0.5);
}

function choicesAround(answer: number): number[] {
  const values = new Set([answer]);
  const offsets = shuffled([-8, -6, -5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 6, 8]);
  while (values.size < 4 && offsets.length > 0)
    values.add(answer + (offsets.shift() ?? 0));
  return shuffled(values);
}

export function makeChallenge(step: number): Challenge {
  switch (step % 3) {
    case 0: {
      const left = 14 + randomInteger(25);
      const right = 6 + randomInteger(19);
      const subtract = Math.random() < 0.5;
      const answer = subtract ? left - right : left + right;
      return {
        kind: "Calcul",
        icon: "calculator-outline",
        prompt: `${left} ${subtract ? "−" : "+"} ${right} = ?`,
        instruction: "Choisissez le résultat",
        answer,
        options: choicesAround(answer),
      };
    }
    case 1: {
      const start = 2 + randomInteger(11);
      const increment = 2 + randomInteger(6);
      const values = Array.from(
        { length: 4 },
        (_, index) => start + index * increment,
      );
      const answer = start + 4 * increment;
      return {
        kind: "Suite logique",
        icon: "ellipsis-horizontal",
        prompt: `${values.join("  ·  ")}  ·  ?`,
        instruction: "Quel nombre vient ensuite ?",
        answer,
        options: choicesAround(answer),
      };
    }
    default: {
      const target = 3 + randomInteger(6);
      const amount = 2 + randomInteger(3);
      const other = Array.from({ length: 7 - amount }, () => {
        let digit = 1 + randomInteger(9);
        while (digit === target) digit = 1 + randomInteger(9);
        return digit;
      });
      const digits = shuffled([
        ...Array<number>(amount).fill(target),
        ...other,
      ]);
      return {
        kind: "Attention",
        icon: "eye-outline",
        prompt: digits.join("  "),
        instruction: `Combien de fois voyez-vous le chiffre ${target} ?`,
        answer: amount,
        options: shuffled([1, 2, 3, 4]),
      };
    }
  }
}
