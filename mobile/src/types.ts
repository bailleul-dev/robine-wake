export type Tab = "morning" | "evening" | "alarms" | "system";

export interface Sound {
  id: string;
  title: string;
  artist?: string | null;
  intensity?: string | null;
}

export interface HueTarget {
  id: string;
  name: string;
}

export interface Alarm {
  id: string;
  label: string;
  enabled: boolean;
  local_time: string;
  days_of_week: number[];
  one_shot_date?: string | null;
  timezone: string;
  sound_id: string;
  strong_sound_id: string;
  prewake_seconds?: number;
  revision?: number;
  next_occurrences?: string[];
  volume_profile?: {
    start?: number;
    ceiling?: number;
    ramp_seconds?: number;
  };
  light_profile?: {
    enabled?: boolean;
    target_id?: string;
    target_name?: string;
    start_brightness?: number;
    end_brightness?: number;
    ramp_seconds?: number;
    end_behavior?: string;
  };
}

export interface AlarmDraft {
  id?: string;
  label: string;
  enabled: boolean;
  hour: number;
  minute: number;
  days: Set<number>;
  timezone: string;
  soundId: string;
  strongSoundId: string;
  startVolume: number;
  ceilingVolume: number;
  prewakeMinutes: number;
  revision?: number;
  lightEnabled: boolean;
  lightTargetId?: string;
  lightTargetName?: string;
  lightStartBrightness: number;
  lightEndBrightness: number;
  lightRampMinutes: number;
  lightEndBehavior: string;
}

export interface WakeSession {
  id: string;
  state?: string;
  audio_phase?: string;
  test_mode?: boolean;
  smartphone_dismiss_allowed?: boolean;
  ended_at?: string;
}

export interface BreathingState {
  active?: boolean;
  phase?: string;
  phase_duration_ms?: number;
  phase_started_at?: string;
  phase_elapsed_ms?: number;
  remaining_seconds?: number;
  target_id?: string;
  audio?: { active?: boolean; volume_percent?: number };
}

export interface HueState {
  configured?: boolean;
  state?: string;
  bridge_host?: string;
  target_count?: number;
  breathing?: BreathingState;
}

export interface RemoteButtonState {
  pairing?: { active?: boolean };
  buttons?: Array<{ id: string; name: string; last_seen_at?: string }>;
}

export interface DeviceState {
  clock_trusted?: boolean;
  network?: { state?: string };
  audio?: { state?: string };
  firmware?: { version?: string };
}

export interface AppState {
  tab: Tab;
  connection: "scanning" | "connecting" | "connected" | "disconnected";
  transport: "http" | "bluetooth" | null;
  httpEndpoint: string | null;
  busy: boolean;
  error: string | null;
  alarms: Alarm[];
  sounds: Sound[];
  device: DeviceState | null;
  recentSessions: WakeSession[];
  activeSession: WakeSession | null;
  smartphoneDismiss: { enabled?: boolean; locked?: boolean };
  hue: HueState | null;
  hueTargets: HueTarget[];
  remoteButton: RemoteButtonState | null;
  breathingSynchronizedAt: Date | null;
  editor: AlarmDraft | null;
  challenge: { sessionId: string } | null;
  lastUpdated: Date | null;
}

export interface Challenge {
  kind: string;
  icon: string;
  prompt: string;
  instruction: string;
  answer: number;
  options: number[];
}

export type CommandBody = Record<string, unknown>;
