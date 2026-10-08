import AsyncStorage from "@react-native-async-storage/async-storage";
import Slider from "@react-native-community/slider";
import { Picker } from "@react-native-picker/picker";
import React, { useEffect, useMemo, useState } from "react";
import {
  Alert,
  Pressable,
  ScrollView,
  Settings,
  Text,
  TextInput,
  View,
} from "react-native";
import * as actions from "./actions";
import {
  napMaximumRampMinutes,
  pendingNapWakeTime,
  regularAlarms,
  scheduleLabel,
} from "./models";
import { setState, useAppState } from "./store";
import * as theme from "./theme";
import * as transport from "./transport";
import type {
  Alarm,
  AppState,
  BreathingState,
  HueState,
  WakeSession,
} from "./types";

const eveningVolumeStorageKey = "robineWake.eveningVolumePercent.v4";

function validVolume(value: unknown): number | undefined {
  const number =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number(value)
        : Number.NaN;
  return Number.isFinite(number) && number >= 0 && number <= 100
    ? Math.round(number)
    : undefined;
}

function useEveningVolume(): [number, (value: unknown) => void] {
  const [volume, setVolume] = useState(60);
  useEffect(() => {
    void AsyncStorage.getItem(eveningVolumeStorageKey)
      .then((stored) => {
        const loaded =
          validVolume(stored) ??
          validVolume(Settings?.get(eveningVolumeStorageKey));
        if (loaded !== undefined) {
          setVolume(loaded);
          void AsyncStorage.setItem(eveningVolumeStorageKey, String(loaded));
        }
      })
      .catch(() => undefined);
  }, []);
  const update = (value: unknown): void => {
    const next = validVolume(value);
    if (next === undefined) return;
    setVolume(next);
    void AsyncStorage.setItem(eveningVolumeStorageKey, String(next));
  };
  return [volume, update];
}

const pageContentStyle = (
  desktop: boolean,
  overrides?: theme.LooseStyle,
): any =>
  theme.style(
    {
      width: "100%",
      maxWidth: desktop ? 1180 : undefined,
      alignSelf: "center",
      paddingHorizontal: desktop ? 32 : 18,
      paddingTop: desktop ? 8 : 0,
      paddingBottom: desktop ? 40 : 120,
      gap: desktop ? 22 : 18,
    },
    overrides,
  );
const dashboardCardStyle = (desktop: boolean): theme.LooseStyle | undefined =>
  desktop ? { flexBasis: "47%", flexGrow: 1, minWidth: 320 } : undefined;

function connectionLabel(state: AppState): string {
  switch (state.connection) {
    case "scanning":
      return "Recherche…";
    case "connecting":
      return "Connexion…";
    case "connected":
      return state.transport === "http" ? "Wi-Fi" : "À proximité";
    case "disconnected":
      return "Déconnecté";
    default:
      return "Bluetooth indisponible";
  }
}

function BrandHeader(): React.JSX.Element {
  const state = useAppState();
  return (
    <View
      style={theme.style({
        flexDirection: "row",
        alignItems: "center",
        gap: 12,
      })}
    >
      <theme.Crescent size={28} />
      <View style={theme.style({ flex: 1 })}>
        <Text
          style={theme.style({
            fontSize: 12,
            fontWeight: "800",
            letterSpacing: 1.8,
            color: theme.c("text"),
          })}
        >
          ROBINE WAKE
        </Text>
        <Text
          style={theme.style({
            fontSize: 12,
            marginTop: 2,
            color: theme.c("muted"),
          })}
        >
          Un réveil qui commence doucement
        </Text>
      </View>
      <theme.StatusPill
        title={connectionLabel(state)}
        connected={Boolean(
          state.httpEndpoint || state.connection === "connected",
        )}
        busy={state.busy}
      />
    </View>
  );
}

function DashboardGreeting(): React.JSX.Element {
  const state = useAppState();
  return (
    <View
      style={theme.style({
        flexDirection: "row",
        alignItems: "flex-end",
        gap: 18,
        paddingVertical: 8,
      })}
    >
      <View style={theme.style({ flex: 1, gap: 5 })}>
        <theme.Eyebrow color="moon">Votre cocon</theme.Eyebrow>
        <Text
          style={theme.style({
            fontSize: 32,
            fontWeight: "750",
            letterSpacing: -0.8,
            color: theme.c("text"),
          })}
        >
          Bonsoir
        </Text>
        <Text style={theme.style({ fontSize: 14, color: theme.c("muted") })}>
          Le réveil veille sur votre prochain matin.
        </Text>
      </View>
      <theme.StatusPill
        title={connectionLabel(state)}
        connected={Boolean(
          state.httpEndpoint || state.connection === "connected",
        )}
        busy={state.busy}
      />
    </View>
  );
}

function ClockHero(): React.JSX.Element {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 30_000);
    return () => clearInterval(timer);
  }, []);
  const time = new Intl.DateTimeFormat("fr-FR", {
    hour: "2-digit",
    minute: "2-digit",
  }).format(now);
  const day = new Intl.DateTimeFormat("fr-FR", {
    weekday: "long",
    day: "numeric",
    month: "long",
  }).format(now);
  return (
    <View
      style={theme.style({ alignItems: "center", paddingVertical: 20, gap: 8 })}
    >
      <theme.Eyebrow color="moon">Votre matin</theme.Eyebrow>
      <Text
        style={theme.style({
          fontSize: 68,
          lineHeight: 76,
          fontWeight: "500",
          fontVariant: ["tabular-nums"],
          color: theme.c("text"),
        })}
      >
        {time}
      </Text>
      <Text style={theme.style({ fontSize: 15, color: theme.c("muted") })}>
        {day}
      </Text>
      <Text
        style={theme.style({
          fontSize: 12,
          marginTop: 8,
          color: theme.c("moonSoft"),
        })}
      >
        Tout est calme. Robine Wake garde le rythme.
      </Text>
    </View>
  );
}

function CompactAlarmRow({ alarm }: { alarm: Alarm }): React.JSX.Element {
  return (
    <View
      style={theme.style({
        flexDirection: "row",
        alignItems: "center",
        gap: 12,
        opacity: alarm.enabled ? 1 : 0.5,
      })}
    >
      <Text
        style={theme.style({
          fontSize: 23,
          fontWeight: "700",
          fontVariant: ["tabular-nums"],
          color: theme.c("text"),
        })}
      >
        {alarm.local_time.slice(0, 5)}
      </Text>
      <View style={theme.style({ flex: 1 })}>
        <Text
          style={theme.style({
            fontSize: 14,
            fontWeight: "700",
            color: theme.c("text"),
          })}
        >
          {alarm.label}
        </Text>
        <Text
          style={theme.style({
            fontSize: 12,
            marginTop: 2,
            color: theme.c("muted"),
          })}
        >
          {scheduleLabel(alarm)}
        </Text>
      </View>
      <theme.Icon name="chevron-forward" size={16} color="muted" />
    </View>
  );
}

export function ActiveSessionCard({
  session,
}: {
  session: WakeSession;
}): React.JSX.Element {
  return (
    <theme.Card highlighted>
      <View style={theme.style({ gap: 15 })}>
        <View
          style={theme.style({ flexDirection: "row", alignItems: "center" })}
        >
          <theme.Eyebrow color="rose">Réveil en cours</theme.Eyebrow>
          <View style={theme.style({ flex: 1 })} />
          <theme.Icon name="pulse" size={22} color="rose" />
        </View>
        <Text
          style={theme.style({
            fontSize: 20,
            fontWeight: "700",
            color: theme.c("text"),
          })}
        >
          {session.audio_phase === "strong"
            ? "Le son de renfort joue"
            : "La lumière sonore monte doucement"}
        </Text>
        <View
          style={theme.style({
            flexDirection: "row",
            flexWrap: "wrap",
            gap: 12,
          })}
        >
          {session.test_mode ? (
            <theme.Button
              title="Arrêt direct"
              compact
              onPress={() => {
                void actions.dismiss();
              }}
            />
          ) : null}
          {session.smartphone_dismiss_allowed !== false ? (
            <theme.Button
              title={session.test_mode ? "Tester l’arrêt" : "Je suis levé"}
              variant="primary"
              onPress={() => setState("challenge", { sessionId: session.id })}
            />
          ) : (
            <View
              style={theme.style({
                flexDirection: "row",
                alignItems: "center",
                gap: 7,
              })}
            >
              <theme.Icon
                name="phone-portrait-outline"
                size={17}
                color="muted"
              />
              <Text
                style={theme.style({
                  fontSize: 11,
                  fontWeight: "700",
                  color: theme.c("muted"),
                })}
              >
                Arrêt sur le réveil
              </Text>
            </View>
          )}
        </View>
      </View>
    </theme.Card>
  );
}

function ClockWarning(): React.JSX.Element {
  return (
    <theme.Card>
      <View
        style={theme.style({
          flexDirection: "row",
          alignItems: "center",
          gap: 14,
        })}
      >
        <theme.Icon name="time" size={28} color="moon" />
        <View style={theme.style({ flex: 1 })}>
          <Text
            style={theme.style({
              fontSize: 17,
              fontWeight: "700",
              color: theme.c("text"),
            })}
          >
            Heure à confirmer
          </Text>
          <Text
            style={theme.style({
              fontSize: 12,
              marginTop: 3,
              color: theme.c("muted"),
            })}
          >
            Vérifiez l’heure avant d’activer un réveil.
          </Text>
        </View>
        <theme.Button
          title="Confirmer"
          compact
          onPress={() => {
            void actions.confirmClock();
          }}
        />
      </View>
    </theme.Card>
  );
}

function NextWakeCard({ alarm }: { alarm: Alarm | undefined }): React.JSX.Element {
  if (!alarm)
    return (
      <Pressable onPress={actions.createAlarm}>
        <theme.Card highlighted>
          <View style={theme.style({ alignItems: "center", gap: 14 })}>
            <theme.Icon name="alarm" size={34} color="moon" />
            <Text
              style={theme.style({
                fontSize: 17,
                fontWeight: "700",
                color: theme.c("text"),
              })}
            >
              Préparer votre premier matin
            </Text>
            <Text
              style={theme.style({
                fontSize: 14,
                textAlign: "center",
                color: theme.c("muted"),
              })}
            >
              Choisissez l’heure, le voyage sonore et la montée progressive.
            </Text>
            <theme.Button
              title="Créer une alarme"
              variant="primary"
              onPress={actions.createAlarm}
            />
          </View>
        </theme.Card>
      </Pressable>
    );
  const ramp = alarm.prewake_seconds ?? alarm.volume_profile?.ramp_seconds ?? 0;
  return (
    <Pressable onPress={() => actions.editAlarm(alarm)}>
      <theme.Card highlighted>
        <View style={theme.style({ gap: 15 })}>
          <View style={theme.style({ flexDirection: "row" })}>
            <theme.Eyebrow color="moon">Prochain réveil</theme.Eyebrow>
            <View style={theme.style({ flex: 1 })} />
            <theme.Icon name="chevron-forward" size={17} color="muted" />
          </View>
          <View
            style={theme.style({
              flexDirection: "row",
              alignItems: "baseline",
            })}
          >
            <Text
              style={theme.style({
                flex: 1,
                fontSize: 46,
                fontWeight: "700",
                fontVariant: ["tabular-nums"],
                color: theme.c("text"),
              })}
            >
              {alarm.local_time.slice(0, 5)}
            </Text>
            <Text
              style={theme.style({
                fontSize: 17,
                fontWeight: "700",
                color: theme.c("moonSoft"),
              })}
            >
              {alarm.label}
            </Text>
          </View>
          <View style={theme.style({ flexDirection: "row", gap: 17 })}>
            <Text
              style={theme.style({ fontSize: 12, color: theme.c("muted") })}
            >
              ◫ {scheduleLabel(alarm)}
            </Text>
            <Text
              style={theme.style({ fontSize: 12, color: theme.c("muted") })}
            >
              〽 {Math.trunc(ramp / 60)} min avant
            </Text>
          </View>
        </View>
      </theme.Card>
    </Pressable>
  );
}

function NapCard({ alarms }: { alarms: Alarm[] }): React.JSX.Element {
  const busy = useAppState().busy;
  const [minutes, setMinutes] = useState(20);
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 15_000);
    return () => clearInterval(timer);
  }, []);
  const wakeTime = pendingNapWakeTime(alarms, now);
  const remaining = wakeTime
    ? Math.max(1, Math.ceil((wakeTime.getTime() - now.getTime()) / 60_000))
    : 0;
  const ramp = Math.min(napMaximumRampMinutes, minutes);
  return (
    <theme.Card>
      <View style={theme.style({ gap: 14 })}>
        <View
          style={theme.style({ flexDirection: "row", alignItems: "center" })}
        >
          <theme.Eyebrow color="lavender">Sieste</theme.Eyebrow>
          <View style={theme.style({ flex: 1 })} />
          <theme.Icon name="moon" size={20} color="lavender" />
        </View>
        {wakeTime ? (
          <>
            <View
              style={theme.style({
                flexDirection: "row",
                alignItems: "baseline",
                gap: 12,
              })}
            >
              <Text
                style={theme.style({
                  fontSize: 34,
                  fontWeight: "700",
                  fontVariant: ["tabular-nums"],
                  color: theme.c("text"),
                })}
              >
                {new Intl.DateTimeFormat("fr-FR", {
                  hour: "2-digit",
                  minute: "2-digit",
                }).format(wakeTime)}
              </Text>
              <Text
                style={theme.style({
                  flex: 1,
                  fontSize: 14,
                  color: theme.c("muted"),
                })}
              >
                Réveil dans {remaining} min
              </Text>
            </View>
            <theme.Button
              title="Annuler la sieste"
              iconName="stop"
              grow
              disabled={busy}
              onPress={() => {
                void actions.cancelNap();
              }}
            />
          </>
        ) : (
          <>
            <View style={theme.style({ flexDirection: "row" })}>
              <Text
                style={theme.style({
                  flex: 1,
                  fontSize: 14,
                  fontWeight: "700",
                  color: theme.c("text"),
                })}
              >
                Durée
              </Text>
              <Text
                style={theme.style({
                  fontSize: 14,
                  fontWeight: "700",
                  color: theme.c("lavender"),
                })}
              >
                {minutes} min
              </Text>
            </View>
            <Slider
              minimumValue={5}
              maximumValue={120}
              step={5}
              value={minutes}
              minimumTrackTintColor={theme.c("lavender")}
              maximumTrackTintColor="rgba(255,255,255,0.15)"
              thumbTintColor={theme.c("lavender")}
              onValueChange={(value) => setMinutes(Math.round(value))}
            />
            <Text
              style={theme.style({ fontSize: 12, color: theme.c("muted") })}
            >
              Le son monte pendant les {ramp} dernières minutes.
            </Text>
            <theme.Button
              title="Lancer la sieste"
              iconName="play"
              variant="primary"
              grow
              disabled={busy}
              onPress={() => {
                void actions.startNap(minutes);
              }}
            />
          </>
        )}
      </View>
    </theme.Card>
  );
}

function AlarmListCard({ alarms }: { alarms: Alarm[] }): React.JSX.Element {
  return (
    <theme.Card>
      <View style={theme.style({ gap: 14 })}>
        <View
          style={theme.style({ flexDirection: "row", alignItems: "center" })}
        >
          <theme.Eyebrow>Vos alarmes</theme.Eyebrow>
          <View style={theme.style({ flex: 1 })} />
          <theme.IconButton
            iconName="add"
            label="Ajouter une alarme"
            onPress={actions.createAlarm}
          />
        </View>
        {alarms.length ? (
          alarms.slice(0, 3).map((alarm, index) => (
            <React.Fragment key={alarm.id}>
              {index > 0 ? <theme.Divider /> : null}
              <Pressable onPress={() => actions.editAlarm(alarm)}>
                <CompactAlarmRow alarm={alarm} />
              </Pressable>
            </React.Fragment>
          ))
        ) : (
          <Text style={theme.style({ fontSize: 14, color: theme.c("muted") })}>
            Aucune alarme enregistrée.
          </Text>
        )}
      </View>
    </theme.Card>
  );
}

export function MorningScreen({
  desktop,
}: {
  desktop: boolean;
}): React.JSX.Element {
  const state = useAppState();
  const alarms = regularAlarms(state.alarms);
  const nextAlarm = alarms
    .filter((alarm) => alarm.enabled)
    .sort((left, right) =>
      (left.next_occurrences?.[0] ?? left.local_time).localeCompare(
        right.next_occurrences?.[0] ?? right.local_time,
      ),
    )[0];
  return (
    <ScrollView
      contentContainerStyle={pageContentStyle(desktop)}
      showsVerticalScrollIndicator={false}
    >
      {desktop ? <DashboardGreeting /> : <BrandHeader />}
      {desktop ? (
        <View
          style={theme.style({
            flexDirection: "row",
            alignItems: "flex-start",
            gap: 22,
          })}
        >
          <View style={theme.style({ flex: 0.82, gap: 22 })}>
            <theme.MorningSky desktop>
              <ClockHero />
            </theme.MorningSky>
            {state.activeSession ? (
              <ActiveSessionCard session={state.activeSession} />
            ) : null}
            {state.device?.clock_trusted === false ? <ClockWarning /> : null}
          </View>
          <View style={theme.style({ flex: 1.18, gap: 22 })}>
            <NextWakeCard alarm={nextAlarm} />
            <NapCard alarms={state.alarms} />
            <AlarmListCard alarms={alarms} />
          </View>
        </View>
      ) : (
        <>
          <theme.MorningSky desktop={false}>
            <ClockHero />
          </theme.MorningSky>
          {state.activeSession ? (
            <ActiveSessionCard session={state.activeSession} />
          ) : null}
          {state.device?.clock_trusted === false ? <ClockWarning /> : null}
          <NextWakeCard alarm={nextAlarm} />
          <NapCard alarms={state.alarms} />
          <AlarmListCard alarms={alarms} />
        </>
      )}
    </ScrollView>
  );
}

function confirmFullAlarm(alarm: Alarm): void {
  const ramp = alarm.prewake_seconds ?? alarm.volume_profile?.ramp_seconds ?? 0;
  Alert.alert(
    `Lancer « ${alarm.label} » comme demain matin ?`,
    `La séquence réelle démarre maintenant : montée pendant ${Math.trunc(ramp / 60)} minutes, plafond pendant 5 minutes, puis son de renfort.`,
    [
      { text: "Annuler", style: "cancel" },
      {
        text: "Lancer le réveil complet",
        onPress: () => {
          void actions.triggerAlarm(alarm.id);
        },
      },
    ],
  );
}

function confirmStrong(alarm: Alarm): void {
  Alert.alert(
    `Tester directement la phase forte de « ${alarm.label} » ?`,
    "Le son de renfort démarrera au volume maximal configuré et les couleurs alterneront toutes les 3 secondes.",
    [
      { text: "Annuler", style: "cancel" },
      {
        text: "Lancer la phase forte",
        onPress: () => {
          void actions.triggerStrong(alarm.id);
        },
      },
    ],
  );
}

function AlarmCard({ alarm }: { alarm: Alarm }): React.JSX.Element {
  const state = useAppState();
  return (
    <theme.Card>
      <View style={theme.style({ gap: 14, opacity: alarm.enabled ? 1 : 0.55 })}>
        <View
          style={theme.style({
            flexDirection: "row",
            alignItems: "flex-start",
          })}
        >
          <Pressable
            style={theme.style({ flex: 1 })}
            onPress={() => actions.editAlarm(alarm)}
          >
            <Text
              style={theme.style({
                fontSize: 38,
                fontWeight: "700",
                fontVariant: ["tabular-nums"],
                color: theme.c("text"),
              })}
            >
              {alarm.local_time.slice(0, 5)}
            </Text>
            <Text
              style={theme.style({
                fontSize: 17,
                fontWeight: "700",
                marginTop: 4,
                color: theme.c("text"),
              })}
            >
              {alarm.label}
            </Text>
            <Text
              style={theme.style({
                fontSize: 14,
                marginTop: 5,
                color: theme.c("muted"),
              })}
            >
              {scheduleLabel(alarm)}
            </Text>
          </Pressable>
          <theme.Toggle
            value={alarm.enabled}
            disabled={state.busy}
            accessibilityLabel={`Activer l’alarme ${alarm.label}`}
            onValueChange={(enabled) => actions.setAlarmEnabled(alarm, enabled)}
          />
        </View>
        <theme.Divider />
        <View
          style={theme.style({
            flexDirection: "row",
            alignItems: "center",
            gap: 9,
          })}
        >
          <Text
            style={theme.style({
              flex: 1,
              fontSize: 12,
              fontWeight: "700",
              color: theme.c("lavender"),
            })}
          >
            🔈 Doux → 🔊 Renfort
          </Text>
          <theme.Button
            title="Réveil complet"
            iconName="play"
            variant="primary"
            compact
            disabled={state.busy}
            onPress={() => confirmFullAlarm(alarm)}
          />
          <theme.Button
            title="Fort"
            iconName="flash"
            variant="danger"
            compact
            disabled={state.busy}
            onPress={() => confirmStrong(alarm)}
          />
        </View>
      </View>
    </theme.Card>
  );
}

export function AlarmsScreen({
  desktop,
}: {
  desktop: boolean;
}): React.JSX.Element {
  const state = useAppState();
  const alarms = regularAlarms(state.alarms);
  return (
    <View style={theme.style({ flex: 1 })}>
      <theme.ScreenTitle
        title="Alarmes"
        desktop={desktop}
        action={{
          title: "Ajouter",
          iconName: "add",
          onPress: actions.createAlarm,
          disabled: state.busy,
        }}
      />
      <ScrollView
        contentContainerStyle={pageContentStyle(desktop)}
        showsVerticalScrollIndicator={false}
      >
        {alarms.length ? (
          <View
            style={theme.style({
              flexDirection: desktop ? "row" : "column",
              flexWrap: desktop ? "wrap" : "nowrap",
              gap: 16,
            })}
          >
            {alarms.map((alarm) => (
              <View
                key={alarm.id}
                style={theme.style(
                  desktop ? { flexBasis: "47%", flexGrow: 1 } : undefined,
                )}
              >
                <AlarmCard alarm={alarm} />
              </View>
            ))}
          </View>
        ) : (
          <theme.Card highlighted>
            <View
              style={theme.style({
                alignItems: "center",
                gap: 16,
                paddingVertical: 20,
              })}
            >
              <theme.Crescent size={50} />
              <Text
                style={theme.style({
                  fontSize: 22,
                  fontWeight: "700",
                  color: theme.c("text"),
                })}
              >
                Vos matins commencent ici
              </Text>
              <Text
                style={theme.style({
                  fontSize: 14,
                  textAlign: "center",
                  color: theme.c("muted"),
                })}
              >
                Créez un réveil à deux étapes, doux puis plus présent si
                nécessaire.
              </Text>
              <theme.Button
                title="Créer une alarme"
                variant="primary"
                onPress={actions.createAlarm}
              />
            </View>
          </theme.Card>
        )}
      </ScrollView>
    </View>
  );
}

function PhaseLegend({
  color,
  title,
  detail,
}: {
  color: theme.ColorName;
  title: string;
  detail: string;
}): React.JSX.Element {
  return (
    <View
      style={theme.style({
        flex: 1,
        flexDirection: "row",
        alignItems: "center",
        gap: 9,
        padding: 11,
        borderRadius: 13,
        backgroundColor: "rgba(255,255,255,0.05)",
      })}
    >
      <View
        style={theme.style({
          width: 12,
          height: 12,
          borderRadius: 6,
          backgroundColor: theme.c(color),
        })}
      />
      <View style={theme.style({ flex: 1 })}>
        <Text
          style={theme.style({
            fontSize: 12,
            fontWeight: "700",
            color: theme.c("text"),
          })}
        >
          {title}
        </Text>
        <Text
          style={theme.style({
            fontSize: 10,
            marginTop: 1,
            color: theme.c("muted"),
          })}
        >
          {detail}
        </Text>
      </View>
    </View>
  );
}

function BreathingGuide({
  breathing,
}: {
  breathing: BreathingState;
}): React.JSX.Element {
  const [tick, setTick] = useState(Date.now());
  useEffect(() => {
    const timer = setInterval(() => setTick(Date.now()), 250);
    return () => clearInterval(timer);
  }, []);
  const phase = breathing.phase ?? "inhale";
  const duration = Math.max(
    1,
    breathing.phase_duration_ms ?? (phase === "inhale" ? 4_000 : 6_000),
  );
  const started = breathing.phase_started_at
    ? new Date(breathing.phase_started_at).getTime()
    : undefined;
  const elapsed = started
    ? Math.max(0, tick - started)
    : (breathing.phase_elapsed_ms ?? 0);
  const progress = Math.min(1, elapsed / duration);
  const inhale = phase === "inhale";
  const color: theme.ColorName = inhale
    ? "breathingInhaleAmber"
    : "breathingExhaleRose";
  const size = 118 + 54 * (inhale ? progress : 1 - progress);
  return (
    <View
      style={theme.style({ alignItems: "center", gap: 14, paddingVertical: 8 })}
    >
      <View
        style={theme.style({
          width: 190,
          height: 190,
          alignItems: "center",
          justifyContent: "center",
        })}
      >
        <View
          style={theme.style({
            width: size,
            height: size,
            borderRadius: 999,
            backgroundColor: theme.c(color),
            opacity: 0.82,
            shadowColor: theme.c(color),
            shadowOpacity: 0.5,
            shadowRadius: 28,
          })}
        />
        <Text
          style={theme.style({
            position: "absolute",
            fontSize: 20,
            fontWeight: "800",
            color: theme.c("text"),
          })}
        >
          {inhale ? "Inspirez" : "Expirez"}
        </Text>
      </View>
      <Text style={theme.style({ fontSize: 13, color: theme.c("muted") })}>
        {breathing.remaining_seconds ?? "—"} s restantes
      </Text>
    </View>
  );
}

function VolumeControl({
  volume,
  active,
  setVolume,
}: {
  volume: number;
  active: boolean;
  setVolume: (value: unknown) => void;
}): React.JSX.Element {
  return (
    <View
      style={theme.style({
        gap: 8,
        padding: 12,
        borderRadius: 13,
        backgroundColor: "rgba(255,255,255,0.05)",
      })}
    >
      <View style={theme.style({ flexDirection: "row" })}>
        <Text
          style={theme.style({
            flex: 1,
            fontSize: 14,
            fontWeight: "700",
            color: theme.c("text"),
          })}
        >
          {volume === 0 ? "🔇" : "🔊"} Volume
        </Text>
        <Text
          style={theme.style({
            fontSize: 14,
            fontWeight: "700",
            color: theme.c("moon"),
          })}
        >
          {volume} %
        </Text>
      </View>
      <Slider
        minimumValue={0}
        maximumValue={100}
        step={5}
        value={volume}
        minimumTrackTintColor={theme.c("moon")}
        maximumTrackTintColor="rgba(255,255,255,0.15)"
        thumbTintColor={theme.c("moon")}
        onValueChange={(value) => setVolume(Math.round(value))}
        onSlidingComplete={(value) => {
          if (active) void actions.breathingVolume(Math.round(value));
        }}
      />
    </View>
  );
}

export function EveningScreen({
  desktop,
}: {
  desktop: boolean;
}): React.JSX.Element {
  const state = useAppState();
  const [targetId, setTargetId] = useState("");
  const [duration, setDuration] = useState(10);
  const [volume, setVolume] = useEveningVolume();
  const targets = state.hueTargets;
  const breathing = state.hue?.breathing ?? {};
  const active = Boolean(breathing.active);
  const selected = targets.some((target) => target.id === targetId)
    ? targetId
    : (breathing.target_id ?? targets[0]?.id ?? "");
  useEffect(() => {
    if (!targetId.trim() && selected.trim()) setTargetId(selected);
  }, [selected, targetId]);
  useEffect(() => {
    const activeVolume = breathing.audio?.volume_percent;
    if (active && activeVolume !== undefined && activeVolume !== volume)
      setVolume(activeVolume);
  }, [active, breathing.audio?.volume_percent, setVolume, volume]);

  return (
    <View style={theme.style({ flex: 1 })}>
      <theme.ScreenTitle
        title="Le soir"
        desktop={desktop}
        action={{
          title: "Actualiser",
          iconName: "refresh",
          disabled: state.busy,
          onPress: () => {
            if (state.hue?.configured) void actions.refreshHue();
            else void transport.refresh();
          },
        }}
      />
      <ScrollView
        contentContainerStyle={pageContentStyle(
          desktop,
          desktop
            ? {
                flexDirection: "row",
                flexWrap: "wrap",
                alignItems: "flex-start",
              }
            : undefined,
        )}
        showsVerticalScrollIndicator={false}
      >
        <theme.Card highlighted cardStyle={dashboardCardStyle(desktop)}>
          <View style={theme.style({ alignItems: "center", gap: 14 })}>
            <theme.Crescent size={44} />
            <theme.Eyebrow color="twilightRose">Rituel du soir</theme.Eyebrow>
            <Text
              style={theme.style({
                fontSize: 23,
                fontWeight: "700",
                color: theme.c("text"),
              })}
            >
              Ralentir avant la nuit
            </Text>
            <Text
              style={theme.style({
                fontSize: 14,
                textAlign: "center",
                color: theme.c("muted"),
              })}
            >
              Une respiration guidée par la lumière, douce et autonome, pour
              laisser la journée retomber.
            </Text>
          </View>
        </theme.Card>
        <theme.Card
          highlighted={active}
          cardStyle={dashboardCardStyle(desktop)}
        >
          <View style={theme.style({ gap: 15 })}>
            <View style={theme.style({ flexDirection: "row" })}>
              <theme.Eyebrow color="twilightRose">
                Respiration 4 / 6
              </theme.Eyebrow>
              <View style={theme.style({ flex: 1 })} />
              <theme.Icon name="bulb" size={21} color="breathingInhaleAmber" />
            </View>
            {active ? (
              <>
                <BreathingGuide breathing={breathing} />
                <Text
                  style={theme.style({
                    fontSize: 12,
                    fontWeight: "700",
                    color: theme.c(breathing.audio?.active ? "mint" : "rose"),
                  })}
                >
                  {breathing.audio?.active
                    ? "🔊  Jardin sonore synchronisé avec la lumière"
                    : "🔇  La lumière continue sans ambiance sonore"}
                </Text>
                <VolumeControl volume={volume} active setVolume={setVolume} />
                <theme.Button
                  title="Terminer et restaurer la lumière"
                  iconName="stop"
                  variant="primary"
                  disabled={state.busy}
                  onPress={() => {
                    void actions.stopBreathing();
                  }}
                />
              </>
            ) : (
              <>
                <Text
                  style={theme.style({
                    fontSize: 14,
                    lineHeight: 20,
                    color: theme.c("muted"),
                  })}
                >
                  L’orage reste naturel et constant. La lumière glisse
                  directement de l’ambre doré au rose crépusculaire, sans passer
                  par le blanc ; seule son intensité évolue lentement.
                </Text>
                <View style={theme.style({ flexDirection: "row", gap: 14 })}>
                  <PhaseLegend
                    color="breathingInhaleAmber"
                    title="Inspiration"
                    detail="4 s · ambre doré · 2 → 30 %"
                  />
                  <PhaseLegend
                    color="breathingExhaleRose"
                    title="Expiration"
                    detail="6 s · rose crépusculaire · 30 → 2 %"
                  />
                </View>
                <Picker
                  selectedValue={selected}
                  onValueChange={setTargetId}
                  dropdownIconColor={theme.c("moon")}
                  style={theme.pickerStyle()}
                >
                  {targets.map((target) => (
                    <Picker.Item
                      key={target.id}
                      label={target.name}
                      value={target.id}
                    />
                  ))}
                </Picker>
                <Picker
                  selectedValue={duration}
                  onValueChange={setDuration}
                  dropdownIconColor={theme.c("moon")}
                  style={theme.pickerStyle()}
                >
                  {[3, 5, 10, 15, 20, 30].map((minutes) => (
                    <Picker.Item
                      key={minutes}
                      label={`${minutes} minutes`}
                      value={minutes}
                    />
                  ))}
                </Picker>
                <VolumeControl
                  volume={volume}
                  active={false}
                  setVolume={setVolume}
                />
                <theme.Button
                  title="Commencer la séance"
                  iconName="play"
                  variant="primary"
                  disabled={
                    state.busy || !state.hue?.configured || !selected.trim()
                  }
                  onPress={() => {
                    void actions.startBreathing(selected, duration, volume);
                  }}
                />
                {!state.hue?.configured ? (
                  <Text
                    style={theme.style({
                      fontSize: 12,
                      color: theme.c("rose"),
                    })}
                  >
                    💡 Configurez d’abord Philips Hue dans l’onglet Réveil.
                  </Text>
                ) : state.hue.state !== "available" ? (
                  <theme.Button
                    title="Réessayer la connexion Hue"
                    compact
                    disabled={state.busy}
                    onPress={() => {
                      void actions.refreshHue();
                    }}
                  />
                ) : null}
              </>
            )}
          </View>
        </theme.Card>
      </ScrollView>
    </View>
  );
}

function statusLabel(value?: string): string {
  if (value === "available") return "Disponible";
  if (value === "unavailable") return "Indisponible";
  return value ? `${value.charAt(0).toUpperCase()}${value.slice(1)}` : "—";
}

function dateLabel(value?: string): string {
  return value
    ? new Intl.DateTimeFormat("fr-FR", {
        dateStyle: "short",
        timeStyle: "short",
      }).format(new Date(value))
    : "—";
}

interface Bridge {
  id: string;
  host: string;
  name: string;
}
interface Discovery {
  state: "idle" | "searching" | "found" | "unavailable";
  bridges: Bridge[];
}

async function discoverHue(
  setDiscovery: React.Dispatch<React.SetStateAction<Discovery>>,
): Promise<void> {
  setDiscovery({ state: "searching", bridges: [] });
  try {
    const response = await fetch("https://discovery.meethue.com/");
    const values = (await response.json()) as Array<{
      id: string;
      internalipaddress: string;
    }>;
    const bridges = values.map((bridge) => ({
      id: bridge.id,
      host: bridge.internalipaddress,
      name: `Pont Hue ${bridge.id}`,
    }));
    setDiscovery({ state: bridges.length ? "found" : "unavailable", bridges });
  } catch {
    setDiscovery({ state: "unavailable", bridges: [] });
  }
}

function HueCard({
  bridgeHost,
  setBridgeHost,
  discovery,
  setDiscovery,
  desktop,
}: {
  bridgeHost: string;
  setBridgeHost: (value: string) => void;
  discovery: Discovery;
  setDiscovery: React.Dispatch<React.SetStateAction<Discovery>>;
  desktop: boolean;
}): React.JSX.Element {
  const state = useAppState();
  const hue = state.hue;
  return (
    <theme.Card
      highlighted={hue?.state === "available"}
      cardStyle={dashboardCardStyle(desktop)}
    >
      <View style={theme.style({ gap: 15 })}>
        <View style={theme.style({ flexDirection: "row" })}>
          <theme.Eyebrow color="moon">Philips Hue</theme.Eyebrow>
          <View style={theme.style({ flex: 1 })} />
          <theme.Icon name="bulb" size={22} color="moon" />
        </View>
        {hue?.configured ? (
          <>
            <theme.MetricRow
              iconName="git-network"
              title="Pont local"
              detail={hue.bridge_host ?? "Connecté"}
              color={hue.state === "available" ? "mint" : "rose"}
            />
            <theme.MetricRow
              iconName="albums"
              title="Pièces et zones"
              detail={`${hue.target_count ?? 0} disponibles`}
            />
            <View style={theme.style({ flexDirection: "row", gap: 10 })}>
              <theme.Button
                title="Actualiser"
                onPress={() => {
                  void actions.refreshHue();
                }}
              />
              <theme.Button
                title="Déconnecter"
                variant="danger"
                onPress={() => {
                  void actions.disconnectHue();
                }}
              />
            </View>
          </>
        ) : (
          <>
            <Text
              style={theme.style({
                fontSize: 14,
                lineHeight: 20,
                color: theme.c("muted"),
              })}
            >
              Les ponts Hue présents sur le même réseau sont découverts
              automatiquement. Appuyez sur le bouton rond du pont juste avant de
              le connecter.
            </Text>
            {discovery.state === "searching" ? (
              <Text
                style={theme.style({ fontSize: 13, color: theme.c("muted") })}
              >
                ◌ Recherche des ponts Hue…
              </Text>
            ) : null}
            {discovery.state === "found"
              ? discovery.bridges.map((bridge) => (
                  <Pressable
                    key={bridge.id}
                    onPress={() => {
                      setBridgeHost(bridge.host);
                      void actions.pairHue(bridge.host);
                    }}
                  >
                    <View
                      style={theme.style({
                        flexDirection: "row",
                        alignItems: "center",
                        gap: 12,
                        padding: 12,
                        borderRadius: 13,
                        backgroundColor: "rgba(255,255,255,0.06)",
                      })}
                    >
                      <theme.Icon
                        name="shield-checkmark"
                        size={20}
                        color="moon"
                      />
                      <View style={theme.style({ flex: 1 })}>
                        <Text
                          style={theme.style({
                            fontSize: 14,
                            fontWeight: "700",
                            color: theme.c("text"),
                          })}
                        >
                          {bridge.name}
                        </Text>
                        <Text
                          style={theme.style({
                            fontSize: 12,
                            color: theme.c("muted"),
                          })}
                        >
                          {bridge.host}
                        </Text>
                      </View>
                      <Text
                        style={theme.style({
                          fontSize: 12,
                          fontWeight: "700",
                          color: theme.c("moon"),
                        })}
                      >
                        Connecter ›
                      </Text>
                    </View>
                  </Pressable>
                ))
              : null}
            {discovery.state === "unavailable" ? (
              <Text
                style={theme.style({ fontSize: 12, color: theme.c("rose") })}
              >
                ⚠ Aucun pont résolu. Utilisez l’adresse manuelle.
              </Text>
            ) : null}
            <theme.Button
              title="Rechercher à nouveau"
              compact
              disabled={discovery.state === "searching"}
              onPress={() => {
                void discoverHue(setDiscovery);
              }}
            />
            <TextInput
              value={bridgeHost}
              onChangeText={setBridgeHost}
              placeholder="Adresse manuelle · ex. 192.168.1.42"
              placeholderTextColor={theme.c("muted")}
              autoCapitalize="none"
              autoCorrect={false}
              keyboardType="url"
              style={theme.inputStyle()}
            />
            <theme.Button
              title="Connecter cette adresse"
              variant="primary"
              disabled={!bridgeHost.trim() || state.busy}
              onPress={() => {
                void actions.pairHue(bridgeHost.trim());
              }}
            />
          </>
        )}
        {hue?.state === "unavailable" ? (
          <Text style={theme.style({ fontSize: 12, color: theme.c("rose") })}>
            ⚠ Le pont est enregistré mais momentanément inaccessible.
          </Text>
        ) : null}
      </View>
    </theme.Card>
  );
}

function RemoteButtonCard({
  desktop,
}: {
  desktop: boolean;
}): React.JSX.Element {
  const state = useAppState();
  const remote = state.remoteButton;
  const pairing = Boolean(remote?.pairing?.active);
  return (
    <theme.Card highlighted={pairing} cardStyle={dashboardCardStyle(desktop)}>
      <View style={theme.style({ gap: 15 })}>
        <View style={theme.style({ flexDirection: "row" })}>
          <theme.Eyebrow color="mint">Bouton déporté</theme.Eyebrow>
          <View style={theme.style({ flex: 1 })} />
          <theme.Icon name="radio-button-on" size={21} color="mint" />
        </View>
        <Text
          style={theme.style({
            fontSize: 14,
            lineHeight: 20,
            color: theme.c("muted"),
          })}
        >
          Arrêt sécurisé en LoRa 868 MHz. Le Raspberry écoute directement le
          bouton, sans Internet ni routeur. Chaque appui est signé et protégé
          contre le rejeu.
        </Text>
        {(remote?.buttons ?? []).map((button) => (
          <View
            key={button.id}
            style={theme.style({
              flexDirection: "row",
              alignItems: "center",
              gap: 12,
            })}
          >
            <theme.Icon name="shield-checkmark" size={21} color="mint" />
            <View style={theme.style({ flex: 1 })}>
              <Text
                style={theme.style({
                  fontSize: 14,
                  fontWeight: "700",
                  color: theme.c("text"),
                })}
              >
                {button.name}
              </Text>
              <Text
                style={theme.style({ fontSize: 12, color: theme.c("muted") })}
              >
                {button.last_seen_at
                  ? dateLabel(button.last_seen_at)
                  : "Jamais utilisé"}
              </Text>
            </View>
            <theme.Button
              title="Oublier"
              variant="danger"
              compact
              disabled={state.busy}
              onPress={() => {
                void actions.removeButton(button.id);
              }}
            />
          </View>
        ))}
        {pairing ? (
          <Text
            style={theme.style({
              fontSize: 12,
              fontWeight: "700",
              color: theme.c("moon"),
            })}
          >
            ⌁ Association ouverte pendant 2 minutes. Maintenez maintenant le
            bouton physique enfoncé.
          </Text>
        ) : (
          <theme.Button
            title="Associer un bouton"
            variant="primary"
            disabled={state.busy}
            onPress={() => {
              void actions.beginButtonPairing();
            }}
          />
        )}
      </View>
    </theme.Card>
  );
}

function SmartphoneDismissCard({
  desktop,
}: {
  desktop: boolean;
}): React.JSX.Element {
  const state = useAppState();
  const enabled = state.smartphoneDismiss.enabled !== false;
  const locked = Boolean(state.smartphoneDismiss.locked || state.activeSession);
  return (
    <theme.Card highlighted={!enabled} cardStyle={dashboardCardStyle(desktop)}>
      <View style={theme.style({ gap: 13 })}>
        <View
          style={theme.style({ flexDirection: "row", alignItems: "center" })}
        >
          <theme.Eyebrow color="rose">Arrêt de l’alarme</theme.Eyebrow>
          <View style={theme.style({ flex: 1 })} />
          <theme.Toggle
            value={enabled}
            disabled={locked || state.busy}
            accessibilityLabel="Autoriser l’arrêt de l’alarme depuis le smartphone"
            onValueChange={(value) => {
              void actions.setSmartphoneDismiss(value);
            }}
          />
        </View>
        <Text
          style={theme.style({
            fontSize: 14,
            lineHeight: 20,
            color: theme.c("muted"),
          })}
        >
          {enabled
            ? "Le smartphone peut arrêter une alarme après le défi de réveil."
            : "L’alarme doit être arrêtée depuis le réveil ou le bouton déporté."}
        </Text>
        {locked ? (
          <View
            style={theme.style({
              flexDirection: "row",
              alignItems: "center",
              gap: 8,
            })}
          >
            <theme.Icon name="lock-closed" size={16} color="moon" />
            <Text
              style={theme.style({
                fontSize: 11,
                fontWeight: "700",
                color: theme.c("moon"),
              })}
            >
              Réglage verrouillé sur le réveil.
            </Text>
          </View>
        ) : null}
      </View>
    </theme.Card>
  );
}

export function SystemScreen({
  desktop,
}: {
  desktop: boolean;
}): React.JSX.Element {
  const state = useAppState();
  const [bridgeHost, setBridgeHost] = useState("");
  const [discovery, setDiscovery] = useState<Discovery>({
    state: "idle",
    bridges: [],
  });
  useEffect(() => {
    if (!state.hue?.configured && discovery.state === "idle")
      void discoverHue(setDiscovery);
  }, [discovery.state, state.hue?.configured]);
  const apiHost =
    state.httpEndpoint?.replace(/^https?:\/\//, "").split(":")[0] ??
    "À découvrir";
  return (
    <View style={theme.style({ flex: 1 })}>
      <theme.ScreenTitle
        title="Le réveil"
        desktop={desktop}
        action={{
          title: "Actualiser",
          iconName: "refresh",
          disabled: state.busy,
          onPress: () => {
            void transport.refresh();
          },
        }}
      />
      <ScrollView
        contentContainerStyle={pageContentStyle(
          desktop,
          desktop
            ? {
                flexDirection: "row",
                flexWrap: "wrap",
                alignItems: "flex-start",
              }
            : undefined,
        )}
        showsVerticalScrollIndicator={false}
      >
        <theme.Card cardStyle={dashboardCardStyle(desktop)}>
          <View style={theme.style({ gap: 14 })}>
            <theme.Eyebrow color="mint">État du réveil</theme.Eyebrow>
            <theme.MetricRow
              iconName="radio"
              title="Canal actif"
              detail={connectionLabel(state)}
              color="mint"
            />
            <theme.MetricRow
              iconName="code-working"
              title="API locale"
              detail={apiHost}
            />
            <theme.MetricRow
              iconName="wifi"
              title="Réseau"
              detail={statusLabel(state.device?.network?.state)}
            />
            <theme.MetricRow
              iconName="volume-high"
              title="Audio"
              detail={statusLabel(state.device?.audio?.state)}
              color="moon"
            />
            <theme.MetricRow
              iconName="cube"
              title="Logiciel"
              detail={state.device?.firmware?.version ?? "—"}
            />
          </View>
        </theme.Card>
        <HueCard
          bridgeHost={bridgeHost}
          setBridgeHost={setBridgeHost}
          discovery={discovery}
          setDiscovery={setDiscovery}
          desktop={desktop}
        />
        <SmartphoneDismissCard desktop={desktop} />
        <RemoteButtonCard desktop={desktop} />
        <theme.Card cardStyle={dashboardCardStyle(desktop)}>
          <View style={theme.style({ gap: 15 })}>
            <theme.Eyebrow color="moon">Bibliothèque sonore</theme.Eyebrow>
            {state.sounds.slice(0, 8).map((sound) => (
              <View
                key={sound.id}
                style={theme.style({
                  flexDirection: "row",
                  alignItems: "center",
                  gap: 12,
                })}
              >
                <theme.Icon
                  name={
                    sound.intensity === "strong" ? "pulse" : "musical-notes"
                  }
                  size={20}
                  color={sound.intensity === "strong" ? "rose" : "moon"}
                />
                <View style={theme.style({ flex: 1 })}>
                  <Text
                    style={theme.style({
                      fontSize: 14,
                      fontWeight: "600",
                      color: theme.c("text"),
                    })}
                  >
                    {sound.title}
                  </Text>
                  {sound.artist ? (
                    <Text
                      style={theme.style({
                        fontSize: 12,
                        color: theme.c("muted"),
                      })}
                    >
                      {sound.artist}
                    </Text>
                  ) : null}
                </View>
                <Text
                  style={theme.style({
                    fontSize: 10,
                    fontWeight: "800",
                    color: theme.c("muted"),
                  })}
                >
                  {(sound.intensity ?? "").toUpperCase()}
                </Text>
              </View>
            ))}
          </View>
        </theme.Card>
        {state.recentSessions.length ? (
          <theme.Card cardStyle={dashboardCardStyle(desktop)}>
            <View style={theme.style({ gap: 14 })}>
              <View
                style={theme.style({
                  flexDirection: "row",
                  alignItems: "center",
                })}
              >
                <theme.Eyebrow>Matins récents</theme.Eyebrow>
                <View style={theme.style({ flex: 1 })} />
                <theme.Button
                  title="Effacer"
                  variant="danger"
                  compact
                  onPress={() =>
                    Alert.alert("Effacer tout l’historique ?", undefined, [
                      { text: "Annuler", style: "cancel" },
                      {
                        text: "Effacer",
                        style: "destructive",
                        onPress: () => {
                          void actions.eraseHistory();
                        },
                      },
                    ])
                  }
                />
              </View>
              {state.recentSessions.slice(0, 5).map((session) => (
                <theme.MetricRow
                  key={session.id}
                  iconName={
                    session.state === "dismissed" ? "checkmark-circle" : "time"
                  }
                  title={
                    session.state
                      ? `${session.state.charAt(0).toUpperCase()}${session.state.slice(1)}`
                      : "Session"
                  }
                  detail={dateLabel(session.ended_at)}
                  color={session.state === "dismissed" ? "mint" : "lavender"}
                />
              ))}
            </View>
          </theme.Card>
        ) : null}
      </ScrollView>
    </View>
  );
}
