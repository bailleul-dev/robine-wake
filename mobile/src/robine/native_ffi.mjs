// React Native host components for Gleam. A prop is a [key, value] pair; the
// style props of one element are merged into a single style object.

import React from "react";
import * as RN from "react-native";
import Ionicons from "@expo/vector-icons/Ionicons";
import { LinearGradient } from "expo-linear-gradient";
import { SafeAreaProvider, SafeAreaView } from "react-native-safe-area-context";
import { StatusBar } from "expo-status-bar";
import Slider from "@react-native-community/slider";
import { Picker } from "@react-native-picker/picker";
import DateTimePicker from "@react-native-community/datetimepicker";
import { GlassView } from "expo-glass-effect";
import { liquid_glass } from "./theme_ffi.mjs";

const swiftUi = liquid_glass ? require("@expo/ui/swift-ui") : null;

export function prop(key, value) {
  return [key, value];
}

export function to_array(list) {
  return list.toArray();
}

export function xy(x, y) {
  return { x, y };
}

export function props(list) {
  const result = {};
  for (const [key, value] of list.toArray()) {
    if (key === "style" && result.style !== undefined) {
      const previous = result.style;
      result.style =
        typeof previous === "function" || typeof value === "function"
          ? (state) => ({ ...resolve(previous, state), ...resolve(value, state) })
          : { ...previous, ...value };
    } else {
      result[key] = value;
    }
  }
  return result;
}

function resolve(style, state) {
  return typeof style === "function" ? style(state) : style;
}

export function style(entries) {
  const result = {};
  for (const [key, value] of entries.toArray()) result[key] = value;
  return ["style", result];
}

export function pressable_style(render) {
  return ["style", ({ pressed }) => style(render(pressed))[1]];
}

export function none() {
  return null;
}

export function string(content) {
  return content;
}

function element(type, list, children) {
  return React.createElement(type, props(list), ...children.toArray());
}

const host = {
  view: RN.View,
  text: RN.Text,
  pressable: RN.Pressable,
  scroll_view: RN.ScrollView,
  text_input: RN.TextInput,
  modal: RN.Modal,
  activity_indicator: RN.ActivityIndicator,
  animated_view: RN.Animated.View,
  icon: Ionicons,
  linear_gradient: LinearGradient,
  safe_area_provider: SafeAreaProvider,
  safe_area_view: SafeAreaView,
  status_bar: StatusBar,
  slider: Slider,
  picker: Picker,
  picker_item: Picker.Item,
  date_time_picker: DateTimePicker,
  glass_view: GlassView,
  swift_host: swiftUi?.Host,
  swift_button: swiftUi?.Button,
};

const components = new Map();

/// A React component named `name` rendering `render(props)`. `render` must be
/// a top-level function: the component is made once per name.
export function component(name, render) {
  if (!components.has(name)) {
    const Component = ({ props }) => render(props);
    Component.displayName = name;
    components.set(name, Component);
  }
  const Component = components.get(name);
  return (props) => React.createElement(Component, { props });
}

export function make(name, list, children) {
  return element(host[name], list, children);
}

export function platform_os() {
  return RN.Platform.OS;
}

export function use_window_width() {
  return RN.useWindowDimensions().width;
}

/// An Animated.Value following `target` over `duration` milliseconds.
export function use_animated(target, duration) {
  const value = React.useRef(new RN.Animated.Value(target)).current;
  React.useEffect(() => {
    RN.Animated.timing(value, {
      toValue: target,
      duration,
      useNativeDriver: false,
    }).start();
  }, [value, target, duration]);
  return value;
}

export function interpolate(value, from, to) {
  return value.interpolate({ inputRange: [0, 1], outputRange: [from, to] });
}

export function alert(title, message, buttons) {
  RN.Alert.alert(
    title,
    message === "" ? undefined : message,
    buttons.toArray().map(([text, role, onPress]) => ({
      text,
      style: role === "default" ? undefined : role,
      onPress,
    })),
  );
}

export function keyed(key, element) {
  return React.cloneElement(element, { key });
}

export function date_at(hour, minute) {
  const date = new Date();
  date.setHours(hour, minute, 0, 0);
  return date;
}

export function on_time_change(callback) {
  return ["onChange", (_event, date) => {
    if (date) callback(date.getHours(), date.getMinutes());
  }];
}
