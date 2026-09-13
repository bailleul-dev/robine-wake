import React, { useEffect } from "react";
import {
  Modal,
  Platform,
  Pressable,
  Text,
  View,
  type GestureResponderEvent,
} from "react-native";
import { SafeAreaProvider, SafeAreaView } from "react-native-safe-area-context";
import { StatusBar } from "expo-status-bar";
import * as actions from "./actions";
import { AlarmEditor } from "./Editor";
import { WakeChallenge } from "./WakeChallenge";
import { pathForTab, tabForPath, titleForTab } from "./routes";
import {
  AlarmsScreen,
  EveningScreen,
  MorningScreen,
  SystemScreen,
} from "./Screens";
import { clearError, setState, useAppState } from "./store";
import * as theme from "./theme";
import * as transport from "./transport";
import type { Tab, WakeSession } from "./types";

const web = Platform.OS === "web";
const tabs: Array<{ id: Tab; label: string; icon: string }> = [
  { id: "morning", label: "Matin", icon: "sunny" },
  { id: "evening", label: "Soir", icon: "moon" },
  { id: "alarms", label: "Alarmes", icon: "alarm" },
  { id: "system", label: "Réveil", icon: "sparkles" },
];

function applyTab(tab: Tab): void {
  setState("tab", tab);
  if (web) document.title = titleForTab(tab);
}

function navigate(tab: Tab): void {
  if (web) {
    const path = pathForTab(tab);
    if (path !== location.pathname) history.pushState({ tab }, "", path);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }
  applyTab(tab);
}

function routePress(tab: Tab, event: GestureResponderEvent): void {
  if (!web) {
    navigate(tab);
    return;
  }
  const nativeEvent = event.nativeEvent as typeof event.nativeEvent & {
    altKey?: boolean;
    ctrlKey?: boolean;
    metaKey?: boolean;
    shiftKey?: boolean;
    button?: number;
  };
  const modified =
    nativeEvent.altKey ||
    nativeEvent.ctrlKey ||
    nativeEvent.metaKey ||
    nativeEvent.shiftKey ||
    (nativeEvent.button ?? 0) !== 0;
  if (!modified) {
    event.preventDefault();
    navigate(tab);
  }
}

function linkProps(tab: Tab): Record<string, unknown> {
  return web
    ? { accessibilityRole: "link", href: pathForTab(tab) }
    : { accessibilityRole: "button" };
}

function TabBar(): React.JSX.Element {
  const state = useAppState();
  return (
    <theme.GlassPanel
      effect="regular"
      interactive
      tint="rgba(30,20,37,0.7)"
      fallbackBackground="rgba(24,16,28,0.98)"
      panelStyle={{
        position: "absolute",
        left: 10,
        right: 10,
        bottom: 8,
        height: 82,
        paddingTop: 8,
        paddingBottom: 18,
        paddingHorizontal: 5,
        flexDirection: "row",
        borderRadius: 29,
        borderWidth: 1,
        borderColor: "rgba(255,231,183,0.16)",
        shadowColor: "#000",
        shadowOpacity: 0.38,
        shadowRadius: 24,
        shadowOffset: { width: 0, height: 10 },
      }}
    >
      {tabs.map(({ id, label, icon }) => {
        const active = id === state.tab;
        return (
          <Pressable
            key={id}
            {...(linkProps(id) as any)}
            onPress={(event) => routePress(id, event)}
            style={theme.style({
              flex: 1,
              alignItems: "center",
              justifyContent: "center",
              gap: 3,
              borderRadius: 20,
              backgroundColor: active ? "rgba(245,207,135,0.13)" : undefined,
            })}
          >
            <theme.Icon
              name={icon}
              size={22}
              color={active ? "moon" : "muted"}
            />
            <Text
              style={theme.style({
                fontSize: 10,
                fontWeight: "750",
                color: theme.c(active ? "moon" : "muted"),
              })}
            >
              {label}
            </Text>
          </Pressable>
        );
      })}
    </theme.GlassPanel>
  );
}

function DesktopSidebar(): React.JSX.Element {
  const state = useAppState();
  return (
    <View
      style={theme.style({
        width: 256,
        paddingHorizontal: 20,
        paddingVertical: 28,
        backgroundColor: "rgba(20,14,25,0.76)",
        borderRightWidth: 1,
        borderRightColor: "rgba(255,231,183,0.09)",
      })}
    >
      <View
        style={theme.style({
          flexDirection: "row",
          alignItems: "center",
          gap: 12,
          paddingHorizontal: 8,
          marginBottom: 34,
        })}
      >
        <theme.Crescent size={34} />
        <View>
          <Text
            style={theme.style({
              fontSize: 13,
              fontWeight: "900",
              letterSpacing: 1.7,
              color: theme.c("text"),
            })}
          >
            ROBINE WAKE
          </Text>
          <Text
            style={theme.style({
              fontSize: 11,
              marginTop: 2,
              color: theme.c("muted"),
            })}
          >
            Des matins plus doux
          </Text>
        </View>
      </View>
      <theme.Eyebrow color="moon">Vos rituels</theme.Eyebrow>
      <View style={theme.style({ gap: 8, marginTop: 12 })}>
        {tabs.map(({ id, label, icon }) => {
          const active = id === state.tab;
          return (
            <Pressable
              key={id}
              {...(linkProps(id) as any)}
              onPress={(event) => routePress(id, event)}
              style={({ pressed }) =>
                theme.style({
                  height: 48,
                  paddingHorizontal: 14,
                  borderRadius: 15,
                  flexDirection: "row",
                  alignItems: "center",
                  gap: 12,
                  cursor: "pointer",
                  backgroundColor: pressed
                    ? "rgba(245,207,135,0.18)"
                    : active
                      ? "rgba(245,207,135,0.13)"
                      : "transparent",
                  borderWidth: 1,
                  borderColor: active
                    ? "rgba(245,207,135,0.24)"
                    : "transparent",
                })
              }
            >
              <theme.Icon
                name={icon}
                size={21}
                color={active ? "moon" : "muted"}
              />
              <Text
                style={theme.style({
                  fontSize: 14,
                  fontWeight: active ? "800" : "650",
                  color: theme.c(active ? "text" : "muted"),
                })}
              >
                {label}
              </Text>
              {active ? (
                <View
                  style={theme.style({
                    marginLeft: "auto",
                    width: 6,
                    height: 6,
                    borderRadius: 3,
                    backgroundColor: theme.c("moon"),
                  })}
                />
              ) : null}
            </Pressable>
          );
        })}
      </View>
      <View style={theme.style({ flex: 1 })} />
      <View
        style={theme.style({
          padding: 15,
          borderRadius: 18,
          backgroundColor: "rgba(245,207,135,0.055)",
          borderWidth: 1,
          borderColor: "rgba(245,207,135,0.12)",
        })}
      >
        <Text
          style={theme.style({
            fontSize: 11,
            fontWeight: "800",
            color: theme.c("muted"),
          })}
        >
          LE RÉVEIL VEILLE
        </Text>
        <View
          style={theme.style({
            flexDirection: "row",
            alignItems: "center",
            gap: 8,
            marginTop: 9,
          })}
        >
          <View
            style={theme.style({
              width: 8,
              height: 8,
              borderRadius: 4,
              backgroundColor: theme.c(state.httpEndpoint ? "mint" : "rose"),
            })}
          />
          <Text
            style={theme.style({
              fontSize: 13,
              fontWeight: "700",
              color: theme.c("text"),
            })}
          >
            {state.httpEndpoint
              ? "Tout est prêt pour demain"
              : "Connexion à retrouver"}
          </Text>
        </View>
        <Text
          style={theme.style({
            fontSize: 11,
            lineHeight: 16,
            marginTop: 8,
            color: theme.c("muted"),
          })}
        >
          Vous pouvez décrocher, Robine Wake garde le rythme.
        </Text>
      </View>
    </View>
  );
}

function GlobalAlarmControls({
  session,
  desktop,
}: {
  session: WakeSession;
  desktop: boolean;
}): React.JSX.Element {
  return (
    <theme.GlassPanel
      effect="regular"
      tint="rgba(83,43,58,0.68)"
      fallbackBackground="rgba(49,33,49,0.97)"
      panelStyle={{
        position: "absolute",
        left: desktop ? 280 : 14,
        right: desktop ? 24 : 14,
        bottom: desktop ? 24 : 102,
        padding: 12,
        borderRadius: 22,
        flexDirection: "row",
        flexWrap: "wrap",
        alignItems: "center",
        gap: 12,
        borderWidth: 1,
        borderColor: "rgba(255,140,163,0.35)",
        shadowColor: "#000",
        shadowOpacity: 0.35,
        shadowRadius: 18,
      }}
    >
      <View
        style={theme.style({
          width: 42,
          height: 42,
          borderRadius: 21,
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: "rgba(255,140,163,0.14)",
        })}
      >
        <theme.Icon name="pulse" size={22} color="rose" />
      </View>
      <View style={theme.style({ flex: 1 })}>
        <Text
          style={theme.style({
            fontSize: 14,
            fontWeight: "800",
            color: theme.c("text"),
          })}
        >
          Alarme en cours
        </Text>
        <Text style={theme.style({ fontSize: 12, color: theme.c("muted") })}>
          {session.audio_phase === "strong"
            ? "Son de renfort"
            : "Réveil progressif"}
        </Text>
      </View>
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
          iconName="sunny"
          variant="primary"
          compact
          onPress={() => setState("challenge", { sessionId: session.id })}
        />
      ) : (
        <Text
          style={theme.style({
            fontSize: 11,
            fontWeight: "700",
            color: theme.c("muted"),
          })}
        >
          Arrêt sur le réveil
        </Text>
      )}
    </theme.GlassPanel>
  );
}

function ErrorDialog({ message }: { message: string }): React.JSX.Element {
  return (
    <Modal visible transparent animationType="fade">
      <View
        style={theme.style({
          flex: 1,
          justifyContent: "center",
          padding: 24,
          backgroundColor: "rgba(0,0,0,0.62)",
        })}
      >
        <theme.Card highlighted>
          <View style={theme.style({ gap: 16 })}>
            <Text
              style={theme.style({
                fontSize: 20,
                fontWeight: "800",
                color: theme.c("text"),
              })}
            >
              Connexion au réveil
            </Text>
            <Text
              style={theme.style({
                fontSize: 14,
                lineHeight: 20,
                color: theme.c("muted"),
              })}
            >
              {message}
            </Text>
            <View
              style={theme.style({
                flexDirection: "row",
                justifyContent: "flex-end",
                gap: 10,
              })}
            >
              <theme.Button title="Fermer" onPress={clearError} />
              <theme.Button
                title="Réessayer"
                variant="primary"
                onPress={() => {
                  clearError();
                  void transport.reconnect();
                }}
              />
            </View>
          </View>
        </theme.Card>
      </View>
    </Modal>
  );
}

function CurrentScreen({
  tab,
  desktop,
}: {
  tab: Tab;
  desktop: boolean;
}): React.JSX.Element {
  if (tab === "evening") return <EveningScreen desktop={desktop} />;
  if (tab === "alarms") return <AlarmsScreen desktop={desktop} />;
  if (tab === "system") return <SystemScreen desktop={desktop} />;
  return <MorningScreen desktop={desktop} />;
}

export default function App(): React.JSX.Element {
  const state = useAppState();
  const desktop = theme.desktopWidth(theme.useViewportWidth());
  useEffect(() => {
    const applyBrowserRoute = (): void => {
      if (web) {
        const tab = tabForPath(location.pathname);
        if (tab) applyTab(tab);
      }
    };
    if (web) window.addEventListener("popstate", applyBrowserRoute);
    applyBrowserRoute();
    transport.start();
    return () => {
      if (web) window.removeEventListener("popstate", applyBrowserRoute);
    };
  }, []);
  return (
    <SafeAreaProvider>
      <View
        style={theme.style({ flex: 1, backgroundColor: theme.c("night950") })}
      >
        <theme.NightBackground />
        <StatusBar style="light" />
        <View
          style={theme.style({
            flex: 1,
            flexDirection: desktop ? "row" : "column",
          })}
        >
          {desktop ? <DesktopSidebar /> : null}
          <SafeAreaView edges={["top"]} style={theme.style({ flex: 1 })}>
            <CurrentScreen tab={state.tab} desktop={desktop} />
          </SafeAreaView>
        </View>
        {desktop ? null : <TabBar />}
        {state.activeSession ? (
          <GlobalAlarmControls
            session={state.activeSession}
            desktop={desktop}
          />
        ) : null}
        {state.editor ? (
          <AlarmEditor
            key={state.editor.id ?? "new"}
            initialDraft={state.editor}
          />
        ) : null}
        {state.challenge ? <WakeChallenge /> : null}
        {state.error ? <ErrorDialog message={state.error} /> : null}
      </View>
    </SafeAreaProvider>
  );
}
