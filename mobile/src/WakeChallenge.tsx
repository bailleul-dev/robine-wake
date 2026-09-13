import { LinearGradient } from "expo-linear-gradient";
import * as Haptics from "expo-haptics";
import React, { useRef, useState } from "react";
import { Modal, Pressable, Text, View } from "react-native";
import * as actions from "./actions";
import { makeChallenge } from "./models";
import { getState, setState, useAppState } from "./store";
import * as theme from "./theme";

function Progress({ step }: { step: number }): React.JSX.Element {
  return (
    <View style={theme.style({ flexDirection: "row", gap: 8 })}>
      {Array.from({ length: 3 }, (_, index) => (
        <View
          key={index}
          style={theme.style({
            flex: 1,
            height: 7,
            borderRadius: 99,
            backgroundColor:
              index < step
                ? theme.c("mint")
                : index === step
                  ? theme.c("moon")
                  : "rgba(255,255,255,0.14)",
          })}
        />
      ))}
    </View>
  );
}

export function WakeChallenge(): React.JSX.Element {
  const state = useAppState();
  const [step, setStep] = useState(0);
  const [challenge, setChallenge] = useState(() => makeChallenge(0));
  const [feedback, setFeedback] = useState<"correct" | "incorrect" | null>(
    null,
  );
  const answering = useRef(false);

  const complete = (): void => {
    if (getState().challenge) {
      setState("challenge", null);
      void actions.dismiss();
    }
  };

  const answer = (value: number): void => {
    if (answering.current) return;
    answering.current = true;
    if (value === challenge.answer) {
      void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      setFeedback("correct");
      setTimeout(() => {
        if (step === 2) complete();
        else {
          const nextStep = step + 1;
          setStep(nextStep);
          setChallenge(makeChallenge(nextStep));
          setFeedback(null);
          answering.current = false;
        }
      }, 550);
    } else {
      void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
      setFeedback("incorrect");
      setTimeout(() => {
        setChallenge(makeChallenge(step));
        setFeedback(null);
        answering.current = false;
      }, 700);
    }
  };

  return (
    <Modal visible animationType="fade" presentationStyle="fullScreen">
      <LinearGradient
        colors={[theme.c("night950"), theme.c("night900"), "#3C342C"]}
        style={theme.style({
          flex: 1,
          paddingHorizontal: 22,
          paddingVertical: 30,
        })}
      >
        <View style={theme.style({ alignItems: "center", gap: 14 })}>
          <theme.Icon name="sunny" size={46} color="moon" />
          <Text
            style={theme.style({
              fontSize: 34,
              fontWeight: "900",
              color: theme.c("text"),
            })}
          >
            Bonjour
          </Text>
          <Text
            style={theme.style({
              fontSize: 14,
              textAlign: "center",
              lineHeight: 20,
              color: theme.c("muted"),
            })}
          >
            Résolvez trois défis pour confirmer que vous êtes bien réveillé.
          </Text>
          <View style={theme.style({ alignSelf: "stretch" })}>
            <Progress step={step} />
          </View>
        </View>
        <View style={theme.style({ flex: 1, justifyContent: "center" })}>
          <View
            style={theme.style({
              padding: 24,
              gap: 22,
              borderRadius: 28,
              backgroundColor: "rgba(255,255,255,0.08)",
              borderWidth: 1,
              borderColor: "rgba(245,207,135,0.25)",
            })}
          >
            <Text
              style={theme.style({
                textAlign: "center",
                fontSize: 12,
                fontWeight: "800",
                letterSpacing: 1.2,
                color: theme.c("rose"),
              })}
            >
              ◉ {challenge.kind.toUpperCase()}
            </Text>
            <Text
              style={theme.style({
                textAlign: "center",
                fontSize: 34,
                lineHeight: 43,
                fontWeight: "700",
                color: theme.c("text"),
              })}
            >
              {challenge.prompt}
            </Text>
            <Text
              style={theme.style({
                textAlign: "center",
                fontSize: 14,
                color: theme.c("muted"),
              })}
            >
              {challenge.instruction}
            </Text>
            <View
              style={theme.style({
                flexDirection: "row",
                flexWrap: "wrap",
                gap: 12,
              })}
            >
              {challenge.options.map((option) => (
                <Pressable
                  key={option}
                  disabled={answering.current}
                  onPress={() => answer(option)}
                  style={({ pressed }) =>
                    theme.style({
                      width: "48%",
                      minHeight: 58,
                      borderRadius: 17,
                      alignItems: "center",
                      justifyContent: "center",
                      borderWidth: 1,
                      borderColor: "rgba(255,255,255,0.1)",
                      backgroundColor: pressed
                        ? "rgba(245,207,135,0.35)"
                        : "rgba(255,255,255,0.09)",
                    })
                  }
                >
                  <Text
                    style={theme.style({
                      fontSize: 24,
                      fontWeight: "900",
                      color: theme.c("text"),
                    })}
                  >
                    {option}
                  </Text>
                </Pressable>
              ))}
            </View>
            {feedback ? (
              <Text
                style={theme.style({
                  textAlign: "center",
                  fontSize: 14,
                  fontWeight: "700",
                  color: theme.c(feedback === "correct" ? "mint" : "rose"),
                })}
              >
                {feedback === "correct"
                  ? "✓  Bien joué"
                  : "↻  Presque — nouveau défi"}
              </Text>
            ) : null}
          </View>
        </View>
        {state.activeSession?.test_mode ? (
          <theme.Button title="Arrêt direct" onPress={complete} />
        ) : null}
        <Text
          style={theme.style({
            textAlign: "center",
            fontSize: 12,
            color: theme.c("muted"),
          })}
        >
          L’alarme continue jusqu’à la résolution des trois défis.
        </Text>
      </LinearGradient>
    </Modal>
  );
}
