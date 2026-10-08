import DateTimePicker from "@react-native-community/datetimepicker";
import Slider from "@react-native-community/slider";
import { Picker } from "@react-native-picker/picker";
import React, { useState } from "react";
import {
  Alert,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
} from "react-native";
import * as actions from "./actions";
import { draftValid, weekdays } from "./models";
import { useAppState } from "./store";
import * as theme from "./theme";
import type { AlarmDraft, HueState, HueTarget, Sound } from "./types";

type SetDraft = React.Dispatch<React.SetStateAction<AlarmDraft>>;
const web = Platform.OS === "web";

function Heading({
  number,
  title,
  subtitle,
}: {
  number: string;
  title: string;
  subtitle: string;
}): React.JSX.Element {
  return (
    <View
      style={theme.style({
        flexDirection: "row",
        alignItems: "center",
        gap: 12,
      })}
    >
      <View
        style={theme.style({
          width: 28,
          height: 28,
          borderRadius: 14,
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: theme.c("moon"),
        })}
      >
        <Text
          style={theme.style({
            fontSize: 12,
            fontWeight: "900",
            color: theme.c("night950"),
          })}
        >
          {number}
        </Text>
      </View>
      <View style={theme.style({ flex: 1 })}>
        <Text
          style={theme.style({
            fontSize: 17,
            fontWeight: "700",
            color: theme.c("text"),
          })}
        >
          {title}
        </Text>
        <Text
          style={theme.style({
            fontSize: 12,
            marginTop: 2,
            color: theme.c("muted"),
          })}
        >
          {subtitle}
        </Text>
      </View>
    </View>
  );
}
function ValueSlider({
  draft,
  setDraft,
  field,
  title,
  minimum,
  maximum,
  suffix,
  color,
}: {
  draft: AlarmDraft;
  setDraft: SetDraft;
  field: keyof AlarmDraft;
  title: string;
  minimum: number;
  maximum: number;
  suffix: string;
  color: theme.ColorName;
}): React.JSX.Element {
  const value = draft[field] as number;
  return (
    <View style={theme.style({ gap: 9 })}>
      <View style={theme.style({ flexDirection: "row" })}>
        <Text
          style={theme.style({ flex: 1, fontSize: 14, color: theme.c("text") })}
        >
          {title}
        </Text>
        <Text
          style={theme.style({
            fontSize: 14,
            fontWeight: "800",
            color: theme.c(color),
          })}
        >
          {value}
          {suffix}
        </Text>
      </View>
      <Slider
        minimumValue={minimum}
        maximumValue={maximum}
        step={1}
        value={value}
        minimumTrackTintColor={theme.c(color)}
        maximumTrackTintColor="rgba(255,255,255,0.14)"
        thumbTintColor={theme.c(color)}
        onValueChange={(next) =>
          setDraft((current) => ({ ...current, [field]: Math.round(next) }))
        }
      />
    </View>
  );
}

function SoundPicker({
  draft,
  setDraft,
  field,
  label,
  detail,
  iconName,
  color,
  sounds,
}: {
  draft: AlarmDraft;
  setDraft: SetDraft;
  field: "soundId" | "strongSoundId";
  label: string;
  detail: string;
  iconName: string;
  color: theme.ColorName;
  sounds: Sound[];
}): React.JSX.Element {
  return (
    <View
      style={theme.style({
        flexDirection: "row",
        alignItems: "center",
        gap: 13,
      })}
    >
      <View
        style={theme.style({
          width: 42,
          height: 42,
          borderRadius: 13,
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: "rgba(245,207,135,0.12)",
        })}
      >
        <theme.Icon name={iconName} size={21} color={color} />
      </View>
      <View style={theme.style({ flex: 1 })}>
        <Text
          style={theme.style({
            fontSize: 14,
            fontWeight: "700",
            color: theme.c("text"),
          })}
        >
          {label}
        </Text>
        <Text style={theme.style({ fontSize: 12, color: theme.c("muted") })}>
          {detail}
        </Text>
      </View>
      <Picker
        selectedValue={draft[field]}
        onValueChange={(value) =>
          setDraft((current) => ({ ...current, [field]: value }))
        }
        dropdownIconColor={theme.c("moon")}
        style={theme.pickerStyle({ width: 180 })}
      >
        {sounds.map((sound) => (
          <Picker.Item key={sound.id} label={sound.title} value={sound.id} />
        ))}
      </Picker>
    </View>
  );
}

function TimeCard({
  draft,
  setDraft,
}: {
  draft: AlarmDraft;
  setDraft: SetDraft;
}): React.JSX.Element {
  const date = new Date();
  date.setHours(draft.hour, draft.minute, 0, 0);
  return (
    <theme.Card highlighted>
      <View style={theme.style({ alignItems: "center", gap: 12 })}>
        <theme.Eyebrow color="moon">Quand commence le matin ?</theme.Eyebrow>
        {web ? (
          <View
            style={theme.style({
              flexDirection: "row",
              alignItems: "center",
              gap: 8,
            })}
          >
            <Picker
              selectedValue={draft.hour}
              onValueChange={(hour) =>
                setDraft((current) => ({ ...current, hour }))
              }
              style={theme.pickerStyle({
                width: 104,
                fontSize: 18,
                fontWeight: "800",
              })}
            >
              {Array.from({ length: 24 }, (_, hour) => (
                <Picker.Item
                  key={hour}
                  label={String(hour).padStart(2, "0")}
                  value={hour}
                />
              ))}
            </Picker>
            <Text
              style={theme.style({
                fontSize: 28,
                fontWeight: "700",
                color: theme.c("moon"),
              })}
            >
              :
            </Text>
            <Picker
              selectedValue={draft.minute}
              onValueChange={(minute) =>
                setDraft((current) => ({ ...current, minute }))
              }
              style={theme.pickerStyle({
                width: 104,
                fontSize: 18,
                fontWeight: "800",
              })}
            >
              {Array.from({ length: 60 }, (_, minute) => (
                <Picker.Item
                  key={minute}
                  label={String(minute).padStart(2, "0")}
                  value={minute}
                />
              ))}
            </Picker>
          </View>
        ) : (
          <DateTimePicker
            value={date}
            mode="time"
            display="spinner"
            themeVariant="dark"
            minuteInterval={1}
            onChange={(_, nextDate) => {
              if (nextDate)
                setDraft((current) => ({
                  ...current,
                  hour: nextDate.getHours(),
                  minute: nextDate.getMinutes(),
                }));
            }}
            style={theme.style({ height: 126, width: 260 })}
          />
        )}
        <TextInput
          value={draft.label}
          onChangeText={(label) =>
            setDraft((current) => ({ ...current, label }))
          }
          placeholder="Nom du réveil"
          placeholderTextColor={theme.c("muted")}
          textAlign="center"
          style={theme.inputStyle({
            alignSelf: "stretch",
            fontSize: 17,
            fontWeight: "700",
          })}
        />
        <View
          style={theme.style({
            alignSelf: "stretch",
            flexDirection: "row",
            alignItems: "center",
          })}
        >
          <Text
            style={theme.style({
              flex: 1,
              fontSize: 14,
              fontWeight: "700",
              color: theme.c("text"),
            })}
          >
            Alarme active
          </Text>
          <theme.Toggle
            value={draft.enabled}
            accessibilityLabel="Alarme active"
            onValueChange={(enabled) =>
              setDraft((current) => ({ ...current, enabled }))
            }
          />
        </View>
      </View>
    </theme.Card>
  );
}

function ScheduleCard({
  draft,
  setDraft,
}: {
  draft: AlarmDraft;
  setDraft: SetDraft;
}): React.JSX.Element {
  return (
    <theme.Card>
      <View style={theme.style({ gap: 16 })}>
        <Heading
          number="1"
          title="Votre rythme"
          subtitle="Les jours où cette alarme revient"
        />
        <View style={theme.style({ flexDirection: "row", gap: 7 })}>
          {weekdays.map(({ id, short, name }) => {
            const selected = draft.days.has(id);
            return (
              <Pressable
                key={id}
                accessibilityLabel={name}
                onPress={() =>
                  setDraft((current) => {
                    const days = new Set(current.days);
                    selected ? days.delete(id) : days.add(id);
                    return { ...current, days };
                  })
                }
                style={theme.style({
                  flex: 1,
                  height: 38,
                  borderRadius: 19,
                  alignItems: "center",
                  justifyContent: "center",
                  backgroundColor: selected
                    ? theme.c("moon")
                    : "rgba(255,255,255,0.06)",
                })}
              >
                <Text
                  style={theme.style({
                    fontSize: 12,
                    fontWeight: "800",
                    color: selected ? theme.c("night950") : theme.c("muted"),
                  })}
                >
                  {short}
                </Text>
              </Pressable>
            );
          })}
        </View>
        <Text style={theme.style({ fontSize: 12, color: theme.c("muted") })}>
          🌍 {draft.timezone}
        </Text>
      </View>
    </theme.Card>
  );
}

function SoundCard({
  draft,
  setDraft,
  sounds,
}: {
  draft: AlarmDraft;
  setDraft: SetDraft;
  sounds: Sound[];
}): React.JSX.Element {
  return (
    <theme.Card>
      <View style={theme.style({ gap: 16 })}>
        <Heading
          number="2"
          title="Voyage sonore"
          subtitle="Doux d’abord, plus présent ensuite"
        />
        <SoundPicker
          draft={draft}
          setDraft={setDraft}
          field="soundId"
          label="Première lumière"
          detail="Commence en douceur"
          iconName="sunny"
          color="moon"
          sounds={sounds}
        />
        <theme.Divider />
        <SoundPicker
          draft={draft}
          setDraft={setDraft}
          field="strongSoundId"
          label="Renfort"
          detail="Prend le relais si nécessaire"
          iconName="pulse"
          color="rose"
          sounds={sounds}
        />
        <Text style={theme.style({ fontSize: 12, color: theme.c("muted") })}>
          ◉ La sortie locale du réveil reste prioritaire pendant une alarme.
        </Text>
      </View>
    </theme.Card>
  );
}

function LightCard({
  draft,
  setDraft,
  targets,
  hue,
}: {
  draft: AlarmDraft;
  setDraft: SetDraft;
  targets: HueTarget[];
  hue: HueState | null;
}): React.JSX.Element {
  const available = Boolean(hue?.configured && targets.length);
  return (
    <theme.Card>
      <View style={theme.style({ gap: 16 })}>
        <Heading
          number="3"
          title="Lever de lumière"
          subtitle="Une ambiance Philips Hue progressive"
        />
        {available ? (
          <>
            <View
              style={theme.style({
                flexDirection: "row",
                alignItems: "center",
              })}
            >
              <Text
                style={theme.style({
                  flex: 1,
                  fontSize: 14,
                  fontWeight: "700",
                  color: theme.c("text"),
                })}
              >
                Allumer progressivement
              </Text>
              <theme.Toggle
                value={draft.lightEnabled}
                accessibilityLabel="Allumer progressivement"
                onValueChange={(lightEnabled) =>
                  setDraft((current) => ({
                    ...current,
                    lightEnabled,
                    ...(lightEnabled && !current.lightTargetId && targets[0]
                      ? {
                          lightTargetId: targets[0].id,
                          lightTargetName: targets[0].name,
                        }
                      : {}),
                  }))
                }
              />
            </View>
            {draft.lightEnabled ? (
              <>
                <Picker
                  selectedValue={draft.lightTargetId ?? ""}
                  onValueChange={(id) => {
                    const target = targets.find(
                      (candidate) => candidate.id === id,
                    );
                    setDraft((current) => ({
                      ...current,
                      lightTargetId: id,
                      ...(target ? { lightTargetName: target.name } : {}),
                    }));
                  }}
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
                <ValueSlider
                  draft={draft}
                  setDraft={setDraft}
                  field="lightStartBrightness"
                  title="Première lueur"
                  minimum={1}
                  maximum={draft.lightEndBrightness}
                  suffix="%"
                  color="moon"
                />
                <ValueSlider
                  draft={draft}
                  setDraft={setDraft}
                  field="lightEndBrightness"
                  title="Lumière finale"
                  minimum={draft.lightStartBrightness}
                  maximum={100}
                  suffix="%"
                  color="mint"
                />
                <ValueSlider
                  draft={draft}
                  setDraft={setDraft}
                  field="lightRampMinutes"
                  title="Durée lumière"
                  minimum={1}
                  maximum={60}
                  suffix=" min"
                  color="lavender"
                />
                <Picker
                  selectedValue={draft.lightEndBehavior}
                  onValueChange={(lightEndBehavior) =>
                    setDraft((current) => ({ ...current, lightEndBehavior }))
                  }
                  dropdownIconColor={theme.c("moon")}
                  style={theme.pickerStyle()}
                >
                  <Picker.Item
                    label="Après l’arrêt · Restaurer"
                    value="restore"
                  />
                  <Picker.Item label="Après l’arrêt · Éteindre" value="off" />
                  <Picker.Item label="Après l’arrêt · Laisser" value="leave" />
                </Picker>
              </>
            ) : null}
          </>
        ) : (
          <Text style={theme.style({ fontSize: 14, color: theme.c("muted") })}>
            💡 Connectez d’abord un pont depuis l’onglet Réveil.
          </Text>
        )}
      </View>
    </theme.Card>
  );
}

function RampCard({
  draft,
  setDraft,
}: {
  draft: AlarmDraft;
  setDraft: SetDraft;
}): React.JSX.Element {
  return (
    <theme.Card>
      <View style={theme.style({ gap: 18 })}>
        <Heading
          number="4"
          title="Montée progressive"
          subtitle="Le plafond est atteint à l’heure du réveil"
        />
        <ValueSlider
          draft={draft}
          setDraft={setDraft}
          field="startVolume"
          title="Départ"
          minimum={0}
          maximum={draft.ceilingVolume}
          suffix="%"
          color="mint"
        />
        <ValueSlider
          draft={draft}
          setDraft={setDraft}
          field="ceilingVolume"
          title="Plafond"
          minimum={draft.startVolume}
          maximum={100}
          suffix="%"
          color="rose"
        />
        <ValueSlider
          draft={draft}
          setDraft={setDraft}
          field="prewakeMinutes"
          title="Commencer avant l’heure"
          minimum={1}
          maximum={60}
          suffix=" min avant"
          color="lavender"
        />
        <ValueSlider
          draft={draft}
          setDraft={setDraft}
          field="strongVolume"
          title="Volume du son de renfort"
          minimum={0}
          maximum={100}
          suffix="%"
          color="rose"
        />
        <Text
          style={theme.style({
            fontSize: 12,
            lineHeight: 17,
            color: theme.c("muted"),
          })}
        >
          Le volume reste au plafond pendant 5 minutes à l’heure choisie, puis
          le son de renfort prend le relais à son propre volume.
        </Text>
        <View
          style={theme.style({
            height: 24,
            flexDirection: "row",
            alignItems: "flex-end",
            gap: 4,
          })}
        >
          {Array.from({ length: 12 }, (_, index) => (
            <View
              key={index}
              style={theme.style({
                flex: 1,
                height: 5 + index * 1.5,
                borderRadius: 999,
                backgroundColor:
                  index < (12 * draft.ceilingVolume) / 100
                    ? theme.c("lavender")
                    : "rgba(255,255,255,0.05)",
                opacity: 0.35 + index * 0.045,
              })}
            />
          ))}
        </View>
      </View>
    </theme.Card>
  );
}

function TestCard({ draft }: { draft: AlarmDraft }): React.JSX.Element {
  return (
    <theme.Card>
      <View style={theme.style({ gap: 14 })}>
        <View
          style={theme.style({
            flexDirection: "row",
            alignItems: "center",
            gap: 13,
          })}
        >
          <theme.Icon name="play" size={22} color="moon" />
          <View style={theme.style({ flex: 1 })}>
            <Text
              style={theme.style({
                fontSize: 17,
                fontWeight: "700",
                color: theme.c("text"),
              })}
            >
              Lancer ce réveil
            </Text>
            <Text
              style={theme.style({ fontSize: 12, color: theme.c("muted") })}
            >
              Reproduit exactement la séquence du matin
            </Text>
          </View>
        </View>
        <View style={theme.style({ flexDirection: "row", gap: 10 })}>
          <View style={theme.style({ flex: 1 })}>
            <theme.Button
              title="Réveil complet"
              grow
              onPress={() => {
                void actions.triggerAlarm(draft.id);
              }}
            />
          </View>
          <View style={theme.style({ flex: 1 })}>
            <theme.Button
              title="Tester fort"
              variant="primary"
              grow
              onPress={() => {
                void actions.triggerStrong(draft.id);
              }}
            />
          </View>
        </View>
      </View>
    </theme.Card>
  );
}

function confirmDelete(draft: AlarmDraft): void {
  Alert.alert("Supprimer cette alarme ?", undefined, [
    { text: "Annuler", style: "cancel" },
    {
      text: "Supprimer",
      style: "destructive",
      onPress: () => {
        actions.closeEditor();
        actions.deleteAlarm(draft);
      },
    },
  ]);
}

export function AlarmEditor({
  initialDraft,
}: {
  initialDraft: AlarmDraft;
}): React.JSX.Element {
  const [draft, setDraft] = useState(initialDraft);
  const state = useAppState();
  const desktop = theme.desktopWidth(theme.useViewportWidth());
  return (
    <Modal
      visible
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={actions.closeEditor}
    >
      <View
        style={theme.style({ flex: 1, backgroundColor: theme.c("night950") })}
      >
        <theme.NightBackground />
        <View
          style={theme.style({
            width: "100%",
            maxWidth: desktop ? 960 : undefined,
            alignSelf: "center",
            paddingTop: 18,
            paddingHorizontal: 18,
            paddingBottom: 12,
            flexDirection: "row",
            alignItems: "center",
          })}
        >
          <theme.Button title="Annuler" compact onPress={actions.closeEditor} />
          <Text
            style={theme.style({
              flex: 1,
              textAlign: "center",
              fontSize: 17,
              fontWeight: "700",
              color: theme.c("text"),
            })}
          >
            {draft.id ? "Modifier l’alarme" : "Nouvelle alarme"}
          </Text>
          <View style={theme.style({ width: 76 })} />
        </View>
        <ScrollView
          contentContainerStyle={theme.style({
            width: "100%",
            maxWidth: desktop ? 960 : undefined,
            alignSelf: "center",
            padding: 18,
            paddingBottom: 48,
            gap: 18,
          })}
          showsVerticalScrollIndicator={false}
        >
          <TimeCard draft={draft} setDraft={setDraft} />
          <ScheduleCard draft={draft} setDraft={setDraft} />
          <SoundCard draft={draft} setDraft={setDraft} sounds={state.sounds} />
          <LightCard
            draft={draft}
            setDraft={setDraft}
            targets={state.hueTargets}
            hue={state.hue}
          />
          <RampCard draft={draft} setDraft={setDraft} />
          {draft.id ? <TestCard draft={draft} /> : null}
          <theme.Button
            title={draft.id ? "Enregistrer les changements" : "Créer l’alarme"}
            variant="primary"
            grow
            disabled={!draftValid(draft) || state.busy}
            onPress={() => actions.saveAlarm(draft)}
          />
          {draft.id ? (
            <theme.Button
              title="Supprimer l’alarme"
              variant="danger"
              grow
              onPress={() => confirmDelete(draft)}
            />
          ) : null}
        </ScrollView>
      </View>
    </Modal>
  );
}
