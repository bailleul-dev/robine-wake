// iOS 26 Liquid Glass: whether GlassView and the SwiftUI buttons of @expo/ui
// can be used, and the SwiftUI modifiers of those buttons.

import { Platform } from "react-native";
import { isGlassEffectAPIAvailable } from "expo-glass-effect";

export const liquid_glass =
  Platform.OS === "ios" &&
  (() => {
    try {
      return isGlassEffectAPIAvailable();
    } catch {
      return false;
    }
  })();

const modifiers = liquid_glass ? require("@expo/ui/swift-ui/modifiers") : null;

export function is_liquid_glass() {
  return liquid_glass;
}

export function modifier(name, argument) {
  return modifiers[name](argument);
}

export function frame_max_width(width) {
  return modifiers.frame({ maxWidth: width });
}

export function match_vertical() {
  return { vertical: true, horizontal: false };
}
