import Ionicons from "@expo/vector-icons/Ionicons";
import { GlassView, isGlassEffectAPIAvailable } from "expo-glass-effect";
import { LinearGradient } from "expo-linear-gradient";
import React, {
  useEffect,
  useRef,
  useSyncExternalStore,
  type ReactNode,
} from "react";
import {
  ActivityIndicator,
  Animated,
  Dimensions,
  Platform,
  Pressable,
  Text,
  View,
} from "react-native";

export const colors = {
  night950: "#090812",
  night900: "#151020",
  night850: "#201627",
  night800: "#2A1D30",
  text: "#FFF8F1",
  muted: "#BDB1BE",
  moon: "#F5CF87",
  moonSoft: "#FFE7B7",
  lavender: "#AAA7FF",
  mint: "#78D9BC",
  rose: "#FF8CA3",
  breathingInhaleAmber: "#F5B75B",
  breathingExhaleRose: "#E0698F",
  twilightRose: "#E0698F",
} as const;

export type ColorName = keyof typeof colors;
export type LooseStyle = Record<string, unknown>;

export const c = (color: ColorName): string => colors[color];
export const style = (
  ...values: Array<LooseStyle | null | undefined | false>
): any => Object.assign({}, ...values.filter(Boolean));

const ios = Platform.OS === "ios";
export const liquidGlass =
  ios &&
  (() => {
    try {
      return isGlassEffectAPIAvailable();
    } catch {
      return false;
    }
  })();

declare const require: (module: string) => Record<string, any>;
const expoUi = liquidGlass ? require("@expo/ui/swift-ui") : null;
const expoUiModifiers = liquidGlass
  ? require("@expo/ui/swift-ui/modifiers")
  : null;
const SwiftUIHost = expoUi?.Host;
const SwiftUIButton = expoUi?.Button;

export const desktopBreakpoint = 900;
let viewportWidth = Dimensions.get("window").width;
const viewportListeners = new Set<() => void>();
Dimensions.addEventListener("change", ({ window }) => {
  viewportWidth = window.width;
  viewportListeners.forEach((listener) => listener());
});

export function useViewportWidth(): number {
  return useSyncExternalStore(
    (listener) => {
      viewportListeners.add(listener);
      return () => viewportListeners.delete(listener);
    },
    () => viewportWidth,
    () => viewportWidth,
  );
}

export const desktopWidth = (width: number): boolean =>
  width >= desktopBreakpoint;

const stars = [
  [8, 7, 2, 0.42],
  [18, 17, 2, 0.7],
  [31, 5, 1, 0.55],
  [44, 13, 2, 0.8],
  [62, 6, 2, 0.5],
  [79, 12, 1, 0.8],
  [91, 4, 2, 0.55],
  [13, 32, 1, 0.65],
  [72, 27, 2, 0.48],
  [92, 39, 1, 0.75],
  [25, 53, 2, 0.4],
  [83, 59, 2, 0.42],
  [6, 70, 1, 0.65],
  [52, 74, 2, 0.4],
  [94, 83, 1, 0.65],
] as const;

export function NightBackground(): React.JSX.Element {
  return (
    <LinearGradient
      colors={[c("night950"), c("night900"), "#211629"]}
      start={{ x: 0, y: 0 }}
      end={{ x: 1, y: 1 }}
      style={style({ position: "absolute", inset: 0 })}
    >
      <View
        style={style({
          position: "absolute",
          width: 520,
          height: 520,
          borderRadius: 999,
          right: -210,
          top: -260,
          opacity: 0.2,
          backgroundColor: "#9D5C78",
        })}
      />
      <View
        style={style({
          position: "absolute",
          width: 480,
          height: 480,
          borderRadius: 999,
          left: -260,
          bottom: -300,
          opacity: 0.13,
          backgroundColor: "#E39A62",
        })}
      />
      {stars.map(([x, y, size, opacity]) => (
        <View
          key={`${x}-${y}`}
          style={style({
            position: "absolute",
            left: `${x}%`,
            top: `${y}%`,
            width: size,
            height: size,
            borderRadius: size,
            opacity,
            backgroundColor: c("moonSoft"),
          })}
        />
      ))}
    </LinearGradient>
  );
}

export function Icon({
  name,
  size = 20,
  color = "lavender",
}: {
  name: string;
  size?: number;
  color?: ColorName | string;
}): React.JSX.Element {
  return (
    <Ionicons
      name={name as any}
      size={size}
      color={color in colors ? c(color as ColorName) : color}
    />
  );
}

export function Crescent({ size = 40 }: { size?: number }): React.JSX.Element {
  return (
    <View
      style={style({
        shadowColor: c("moon"),
        shadowOpacity: 0.35,
        shadowRadius: size * 0.3,
      })}
    >
      <Icon name="moon" size={size} color="moon" />
    </View>
  );
}

export function Eyebrow({
  children,
  color = "lavender",
}: {
  children: ReactNode;
  color?: ColorName;
}): React.JSX.Element {
  return (
    <Text
      style={style({
        fontSize: 11,
        fontWeight: "800",
        letterSpacing: 1.5,
        color: c(color),
        textTransform: "uppercase",
      })}
    >
      {children}
    </Text>
  );
}

interface GlassPanelProps {
  children?: ReactNode;
  effect?: "regular" | "clear";
  interactive?: boolean;
  tint?: string;
  fallbackBackground?: string;
  panelStyle?: LooseStyle;
}

export function GlassPanel({
  children,
  effect = "regular",
  interactive = false,
  tint = "rgba(34,24,43,0.58)",
  fallbackBackground = "rgba(31,23,39,0.9)",
  panelStyle = {},
}: GlassPanelProps): React.JSX.Element {
  return liquidGlass ? (
    <GlassView
      style={style(panelStyle)}
      glassEffectStyle={effect}
      tintColor={tint}
      colorScheme="dark"
      isInteractive={interactive}
    >
      {children}
    </GlassView>
  ) : (
    <View style={style(panelStyle, { backgroundColor: fallbackBackground })}>
      {children}
    </View>
  );
}

export function Card({
  children,
  highlighted = false,
  padding = 18,
  cardStyle,
}: {
  children?: ReactNode;
  highlighted?: boolean;
  padding?: number;
  cardStyle?: LooseStyle | undefined;
}): React.JSX.Element {
  return (
    <GlassPanel
      effect={highlighted ? "regular" : "clear"}
      tint={highlighted ? "rgba(84,54,69,0.58)" : "rgba(35,27,45,0.48)"}
      fallbackBackground={
        highlighted ? "rgba(49,33,49,0.95)" : "rgba(31,23,39,0.9)"
      }
      panelStyle={style(
        {
          padding,
          borderRadius: 24,
          borderWidth: 1,
          borderColor: highlighted
            ? "rgba(245,207,135,0.32)"
            : "rgba(255,231,183,0.12)",
          shadowColor: "#2A1020",
          shadowOpacity: 0.3,
          shadowRadius: 18,
          shadowOffset: { width: 0, height: 10 },
        },
        cardStyle,
      )}
    >
      {children}
    </GlassPanel>
  );
}

export const Divider = (): React.JSX.Element => (
  <View
    style={style({ height: 1, backgroundColor: "rgba(255,255,255,0.08)" })}
  />
);

const sfSymbols: Record<string, string> = {
  add: "plus",
  refresh: "arrow.clockwise",
  sunny: "sun.max.fill",
  play: "play.fill",
  flash: "bolt.fill",
  stop: "stop.fill",
};

export interface ButtonProps {
  title: string;
  onPress: () => void;
  variant?: "primary" | "danger";
  disabled?: boolean;
  iconName?: string;
  compact?: boolean;
  grow?: boolean;
}

function NativeGlassButton({
  title,
  onPress,
  variant,
  disabled,
  iconName,
  compact,
  grow,
}: ButtonProps): React.JSX.Element {
  const primary = variant === "primary";
  const danger = variant === "danger";
  const modifiersApi = expoUiModifiers!;
  const modifiers = [
    modifiersApi.buttonStyle(primary ? "glassProminent" : "glass"),
    modifiersApi.controlSize(compact ? "regular" : "large"),
    modifiersApi.tint(
      danger ? c("rose") : primary ? c("moon") : c("moonSoft"),
    ),
    modifiersApi.disabled(Boolean(disabled)),
    ...(grow ? [modifiersApi.frame({ maxWidth: 10_000 })] : []),
  ];
  return (
    <SwiftUIHost
      matchContents={grow ? { vertical: true, horizontal: false } : true}
      colorScheme="dark"
      ignoreSafeArea="all"
      seedColor={danger ? c("rose") : primary ? c("moon") : c("moonSoft")}
      style={style({
        minHeight: compact ? 38 : 48,
        alignSelf: grow ? "stretch" : "center",
      })}
    >
      <SwiftUIButton
        label={title}
        systemImage={iconName ? sfSymbols[iconName] : undefined}
        role={danger ? "destructive" : "default"}
        onPress={onPress}
        modifiers={modifiers}
      />
    </SwiftUIHost>
  );
}

function FallbackButton({
  title,
  onPress,
  variant,
  disabled,
  iconName,
  compact,
  grow,
}: ButtonProps): React.JSX.Element {
  const primary = variant === "primary";
  const danger = variant === "danger";
  const backgroundColor = primary
    ? c("moon")
    : danger
      ? "rgba(255,140,163,0.72)"
      : "rgba(255,231,183,0.08)";
  const foreground = primary ? c("night950") : c("text");
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) =>
        style({
          flexDirection: "row",
          alignItems: "center",
          justifyContent: "center",
          gap: 7,
          paddingHorizontal: compact ? 12 : 17,
          minHeight: compact ? 36 : 44,
          paddingVertical: compact ? 8 : 11,
          borderRadius: 999,
          cursor: disabled ? "default" : "pointer",
          alignSelf: grow ? "stretch" : undefined,
          backgroundColor,
          borderWidth: primary ? 0 : 1,
          borderColor: "rgba(255,231,183,0.12)",
          opacity: disabled ? 0.45 : pressed ? 0.72 : 1,
          transform: [{ scale: pressed ? 0.97 : 1 }],
        })
      }
    >
      {iconName ? (
        <Icon name={iconName} size={compact ? 14 : 17} color={foreground} />
      ) : null}
      <Text
        style={style({
          fontSize: compact ? 12 : 15,
          fontWeight: "800",
          color: foreground,
        })}
      >
        {title}
      </Text>
    </Pressable>
  );
}

export function Button(props: ButtonProps): React.JSX.Element {
  return liquidGlass ? (
    <NativeGlassButton {...props} />
  ) : (
    <FallbackButton {...props} />
  );
}

export function IconButton({
  iconName,
  label,
  onPress,
  disabled,
  color = "lavender",
}: {
  iconName: string;
  label: string;
  onPress: () => void;
  disabled?: boolean;
  color?: ColorName;
}): React.JSX.Element {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) =>
        style({
          width: 40,
          height: 40,
          borderRadius: 13,
          alignItems: "center",
          justifyContent: "center",
          cursor: disabled ? "default" : "pointer",
          backgroundColor: pressed
            ? "rgba(245,207,135,0.18)"
            : "rgba(255,231,183,0.07)",
          borderWidth: 1,
          borderColor: "rgba(255,231,183,0.11)",
          opacity: disabled ? 0.45 : 1,
        })
      }
    >
      <Icon name={iconName} size={20} color={color} />
    </Pressable>
  );
}

export function Toggle({
  value,
  onValueChange,
  disabled,
  accessibilityLabel,
}: {
  value: boolean;
  onValueChange: (value: boolean) => void;
  disabled?: boolean;
  accessibilityLabel: string;
}): React.JSX.Element {
  const progress = useRef(new Animated.Value(value ? 1 : 0)).current;
  useEffect(() => {
    Animated.timing(progress, {
      toValue: value ? 1 : 0,
      duration: 180,
      useNativeDriver: false,
    }).start();
  }, [progress, value]);
  const thumbOffset = progress.interpolate({
    inputRange: [0, 1],
    outputRange: [0, 22],
  });
  const trackColor = progress.interpolate({
    inputRange: [0, 1],
    outputRange: ["#332B38", "#245448"],
  });
  const borderColor = progress.interpolate({
    inputRange: [0, 1],
    outputRange: ["rgba(189,177,190,0.28)", "rgba(120,217,188,0.56)"],
  });
  const thumbColor = progress.interpolate({
    inputRange: [0, 1],
    outputRange: ["#CFC3CC", "#A9E8D5"],
  });
  return (
    <Pressable
      accessibilityRole="switch"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ checked: value, disabled: Boolean(disabled) }}
      disabled={disabled}
      hitSlop={8}
      onPress={() => onValueChange(!value)}
      style={({ pressed }) =>
        style({
          borderRadius: 999,
          cursor: disabled ? "default" : "pointer",
          outlineStyle: "none",
          opacity: disabled ? 0.42 : 1,
          transform: [{ scale: pressed ? 0.96 : 1 }],
        })
      }
    >
      <Animated.View
        style={style({
          width: 52,
          height: 30,
          padding: 3,
          borderRadius: 999,
          justifyContent: "center",
          backgroundColor: trackColor,
          borderWidth: 1,
          borderColor,
        })}
      >
        <Animated.View
          style={style({
            width: 22,
            height: 22,
            borderRadius: 999,
            backgroundColor: thumbColor,
            shadowColor: "#090812",
            shadowOpacity: 0.42,
            shadowRadius: 4,
            shadowOffset: { width: 0, height: 2 },
            transform: [{ translateX: thumbOffset }],
          })}
        />
      </Animated.View>
    </Pressable>
  );
}

export const inputStyle = (overrides?: LooseStyle): any =>
  style(
    {
      minHeight: 46,
      paddingHorizontal: 14,
      paddingVertical: 11,
      borderRadius: 13,
      borderWidth: 1,
      borderColor: "rgba(255,231,183,0.15)",
      fontSize: 14,
      color: c("text"),
      backgroundColor: "rgba(13,9,18,0.58)",
      outlineStyle: "none",
    },
    overrides,
  );
export const pickerStyle = (overrides?: LooseStyle): any =>
  style(
    {
      minHeight: 46,
      paddingHorizontal: 12,
      borderRadius: 13,
      borderWidth: 1,
      borderColor: "rgba(255,231,183,0.15)",
      color: c("text"),
      backgroundColor: c("night800"),
      cursor: "pointer",
    },
    overrides,
  );

export function MorningSky({
  desktop,
  children,
}: {
  desktop: boolean;
  children?: ReactNode;
}): React.JSX.Element {
  return (
    <View
      style={style({
        minHeight: desktop ? 336 : 268,
        overflow: "hidden",
        borderRadius: desktop ? 32 : 26,
        borderWidth: 1,
        borderColor: "rgba(255,231,183,0.16)",
        shadowColor: "#1D0D18",
        shadowOpacity: 0.45,
        shadowRadius: 30,
      })}
    >
      <LinearGradient
        colors={["#3A263D", "#211B35", "#111425"]}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={style({ position: "absolute", inset: 0 })}
      />
      <LinearGradient
        colors={[c("moonSoft"), c("moon"), "#C67A58"]}
        start={{ x: 0.2, y: 0.1 }}
        end={{ x: 0.9, y: 1 }}
        style={style({
          position: "absolute",
          width: desktop ? 190 : 142,
          height: desktop ? 190 : 142,
          borderRadius: 999,
          right: desktop ? -26 : -38,
          top: desktop ? -44 : -24,
          opacity: 0.94,
          shadowColor: c("moon"),
          shadowOpacity: 0.5,
          shadowRadius: 48,
        })}
      />
      <View
        style={style({
          position: "absolute",
          left: -50,
          right: -50,
          bottom: desktop ? -105 : -90,
          height: desktop ? 205 : 170,
          borderRadius: 999,
          backgroundColor: "rgba(41,42,69,0.96)",
          borderTopWidth: 1,
          borderTopColor: "rgba(255,255,255,0.09)",
        })}
      />
      <View
        style={style({
          position: "absolute",
          left: "18%",
          right: -90,
          bottom: desktop ? -135 : -112,
          height: desktop ? 210 : 175,
          borderRadius: 999,
          backgroundColor: "rgba(21,24,48,0.98)",
        })}
      />
      <View
        style={style({
          flex: 1,
          zIndex: 2,
          justifyContent: "center",
          padding: desktop ? 28 : 18,
        })}
      >
        {children}
      </View>
    </View>
  );
}

export function StatusPill({
  title,
  connected,
  busy,
}: {
  title: string;
  connected: boolean;
  busy: boolean;
}): React.JSX.Element {
  return (
    <GlassPanel
      effect="clear"
      tint="rgba(52,39,60,0.42)"
      fallbackBackground="rgba(255,255,255,0.07)"
      panelStyle={{
        flexDirection: "row",
        alignItems: "center",
        gap: 7,
        paddingHorizontal: 12,
        paddingVertical: 8,
        borderRadius: 999,
        borderWidth: 1,
        borderColor: "rgba(255,255,255,0.12)",
      }}
    >
      {busy ? (
        <ActivityIndicator size="small" color={c("moon")} />
      ) : (
        <View
          style={style({
            width: 7,
            height: 7,
            borderRadius: 4,
            backgroundColor: c(connected ? "mint" : "rose"),
          })}
        />
      )}
      <Text
        style={style({ fontSize: 12, fontWeight: "700", color: c("text") })}
      >
        {busy ? "Synchronisation" : title}
      </Text>
    </GlassPanel>
  );
}

export function MetricRow({
  iconName,
  title,
  detail,
  color = "lavender",
}: {
  iconName: string;
  title: string;
  detail: string;
  color?: ColorName;
}): React.JSX.Element {
  return (
    <View
      style={style({ flexDirection: "row", alignItems: "center", gap: 13 })}
    >
      <View
        style={style({
          width: 34,
          height: 34,
          borderRadius: 10,
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: "rgba(170,167,255,0.13)",
        })}
      >
        <Icon name={iconName} size={18} color={color} />
      </View>
      <Text
        style={style({
          flex: 1,
          fontSize: 14,
          fontWeight: "600",
          color: c("text"),
        })}
      >
        {title}
      </Text>
      <Text style={style({ fontSize: 14, color: c("muted") })}>{detail}</Text>
    </View>
  );
}

export function ScreenTitle({
  title,
  action,
  desktop,
}: {
  title: string;
  action: ButtonProps;
  desktop: boolean;
}): React.JSX.Element {
  return (
    <View
      style={style({
        width: "100%",
        maxWidth: desktop ? 1180 : undefined,
        alignSelf: "center",
        flexDirection: "row",
        alignItems: "center",
        paddingHorizontal: desktop ? 32 : 18,
        paddingTop: desktop ? 28 : 8,
        paddingBottom: desktop ? 20 : 14,
      })}
    >
      <Text
        style={style({
          flex: 1,
          fontSize: desktop ? 34 : 30,
          fontWeight: "800",
          color: c("text"),
        })}
      >
        {title}
      </Text>
      <Button {...action} compact />
    </View>
  );
}
