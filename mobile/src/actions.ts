import { alarmToDraft, draftToPayload } from "./models";
import { getState, setState } from "./store";
import { command } from "./transport";
import type { Alarm, AlarmDraft } from "./types";

export function editAlarm(alarm: Alarm): void {
  setState("editor", alarmToDraft(alarm, getState().sounds));
}

export function createAlarm(): void {
  const draft = alarmToDraft(null, getState().sounds);
  const firstTarget = getState().hueTargets[0];
  setState(
    "editor",
    firstTarget
      ? {
          ...draft,
          lightEnabled: true,
          lightTargetId: firstTarget.id,
          lightTargetName: firstTarget.name,
        }
      : draft,
  );
}

export function closeEditor(): void {
  setState("editor", null);
}

export function saveAlarm(draft: AlarmDraft): void {
  const payload = draftToPayload(draft);
  closeEditor();
  void (draft.id
    ? command("alarm.update", { alarm_id: draft.id, alarm: payload })
    : command("alarm.create", { alarm: payload }));
}

export function deleteAlarm(alarm: Alarm | AlarmDraft): void {
  void command("alarm.delete", {
    alarm_id: alarm.id,
    revision: alarm.revision,
  });
}

export function setAlarmEnabled(alarm: Alarm, enabled: boolean): void {
  const draft = { ...alarmToDraft(alarm, getState().sounds), enabled };
  void command("alarm.update", {
    alarm_id: alarm.id,
    alarm: draftToPayload(draft),
  });
}

export const triggerAlarm = (id: string | undefined): Promise<unknown> =>
  command("alarm.trigger", { alarm_id: id });
export const triggerStrong = (id: string | undefined): Promise<unknown> =>
  command("alarm.trigger_strong", { alarm_id: id });
export const snooze = (): Promise<unknown> => command("session.snooze");
export const dismiss = (): Promise<unknown> => command("session.dismiss");
export const setSmartphoneDismiss = (enabled: boolean): Promise<unknown> =>
  command("settings.smartphone_dismiss.set", { enabled });
export const confirmClock = (): Promise<unknown> => command("clock.confirm");
export const eraseHistory = (): Promise<unknown> => command("history.erase");
export const pairHue = (host: string): Promise<unknown> =>
  command("hue.pair", { bridge_host: host });
export const refreshHue = (): Promise<unknown> => command("hue.refresh");
export const disconnectHue = (): Promise<unknown> => command("hue.disconnect");
export const startBreathing = (
  targetId: string,
  duration: number,
  volume: number,
): Promise<unknown> =>
  command("breathing.start", {
    target_id: targetId,
    duration_minutes: duration,
    volume_percent: volume,
  });
export const breathingVolume = (volume: number): Promise<unknown> =>
  command("breathing.volume", { volume_percent: volume });
export const stopBreathing = (): Promise<unknown> => command("breathing.stop");
export const beginButtonPairing = (): Promise<unknown> =>
  command("remote_button.pairing.begin", { duration_seconds: 120 });
export const removeButton = (id: string): Promise<unknown> =>
  command("remote_button.remove", { button_id: id });
