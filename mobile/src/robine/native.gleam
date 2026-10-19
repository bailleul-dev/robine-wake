//// React Native for Gleam: host components, props and the style list they
//// share. Elements are redraw elements, so components and hooks come from
//// redraw.

import gleam/list
import redraw.{type Element}
import robine/style.{type Style}

pub type Prop

/// A value React Native animates, made by `use_animated`.
pub type Animated

@external(javascript, "./native_ffi.mjs", "prop")
pub fn prop(key: String, value: a) -> Prop

@external(javascript, "./native_ffi.mjs", "style")
fn style_prop(entries: List(Style)) -> Prop

pub fn style(entries: List(Style)) -> Prop {
  style_prop(entries)
}

@external(javascript, "./native_ffi.mjs", "pressable_style")
fn pressable_style_prop(render: fn(Bool) -> List(Style)) -> Prop

/// A style depending on whether the pressable is pressed.
pub fn pressable_style(render: fn(Bool) -> List(Style)) -> Prop {
  pressable_style_prop(render)
}

@external(javascript, "./native_ffi.mjs", "none")
pub fn none() -> Element

/// Plain text, as a child of `text_`.
@external(javascript, "./native_ffi.mjs", "string")
pub fn string(content: String) -> Element

@external(javascript, "./native_ffi.mjs", "make")
fn make(name: String, props: List(Prop), children: List(Element)) -> Element

/// A JavaScript array, for props that take one.
type Array(a)

@external(javascript, "./native_ffi.mjs", "to_array")
fn to_array(list: List(a)) -> Array(a)

pub fn when(condition: Bool, render: fn() -> Element) -> Element {
  case condition {
    True -> render()
    False -> none()
  }
}

// Components ------------------------------------------------------------------

pub fn view(props: List(Prop), children: List(Element)) -> Element {
  make("view", props, children)
}

pub fn text(props: List(Prop), content: String) -> Element {
  make("text", props, [string(content)])
}

pub fn text_(props: List(Prop), children: List(Element)) -> Element {
  make("text", props, children)
}

pub fn pressable(props: List(Prop), children: List(Element)) -> Element {
  make("pressable", props, children)
}

pub fn scroll_view(props: List(Prop), children: List(Element)) -> Element {
  make("scroll_view", props, children)
}

pub fn text_input(props: List(Prop)) -> Element {
  make("text_input", props, [])
}

pub fn modal(props: List(Prop), children: List(Element)) -> Element {
  make("modal", props, children)
}

pub fn activity_indicator(props: List(Prop)) -> Element {
  make("activity_indicator", props, [])
}

pub fn animated_view(props: List(Prop), children: List(Element)) -> Element {
  make("animated_view", props, children)
}

/// An Ionicons glyph.
pub fn icon(name: String, size: Int, color: String) -> Element {
  make(
    "icon",
    [prop("name", name), prop("size", size), prop("color", color)],
    [],
  )
}

pub fn linear_gradient(
  colors: List(String),
  start: #(Float, Float),
  end: #(Float, Float),
  props: List(Prop),
  children: List(Element),
) -> Element {
  make(
    "linear_gradient",
    [
      prop("colors", to_array(colors)),
      point("start", start),
      point("end", end),
      ..props
    ],
    children,
  )
}

fn point(key: String, at: #(Float, Float)) -> Prop {
  prop(key, xy(at.0, at.1))
}

type Point

@external(javascript, "./native_ffi.mjs", "xy")
fn xy(x: Float, y: Float) -> Point

pub fn safe_area_provider(children: List(Element)) -> Element {
  make("safe_area_provider", [], children)
}

pub fn safe_area_view(props: List(Prop), children: List(Element)) -> Element {
  make("safe_area_view", props, children)
}

/// The edges a `safe_area_view` keeps clear.
pub fn edges(edges: List(String)) -> Prop {
  prop("edges", to_array(edges))
}

pub fn status_bar_light() -> Element {
  make("status_bar", [prop("style", "light")], [])
}

pub fn slider(props: List(Prop)) -> Element {
  make("slider", props, [])
}

/// A picker of `#(value, label)` choices.
pub fn picker(props: List(Prop), choices: List(#(value, String))) -> Element {
  make(
    "picker",
    props,
    list.map(choices, fn(choice) {
      make(
        "picker_item",
        [key(choice.1), prop("label", choice.1), prop("value", choice.0)],
        [],
      )
    }),
  )
}

pub fn date_time_picker(props: List(Prop)) -> Element {
  make("date_time_picker", props, [])
}

/// GlassView of expo-glass-effect, for iOS 26.
pub fn glass_view(props: List(Prop), children: List(Element)) -> Element {
  make("glass_view", props, children)
}

/// A SwiftUI host of @expo/ui, for iOS 26.
pub fn swift_host(props: List(Prop), children: List(Element)) -> Element {
  make("swift_host", props, children)
}

pub fn swift_button(props: List(Prop)) -> Element {
  make("swift_button", props, [])
}

/// A React component named `name` rendering `render(props)`, so `render` can
/// use hooks. `render` must be a top-level function: the component is made
/// once per name.
@external(javascript, "./native_ffi.mjs", "component")
pub fn component(
  name: String,
  render: fn(props) -> Element,
) -> fn(props) -> Element

/// A list prop such as `modifiers`.
pub fn list_prop(key: String, values: List(a)) -> Prop {
  prop(key, to_array(values))
}

// Common props ----------------------------------------------------------------

pub fn on_press(handler: fn() -> Nil) -> Prop {
  prop("onPress", fn(_event: a) { handler() })
}

pub fn disabled(value: Bool) -> Prop {
  prop("disabled", value)
}

pub fn role(value: String) -> Prop {
  prop("accessibilityRole", value)
}

pub fn label(value: String) -> Prop {
  prop("accessibilityLabel", value)
}

pub fn key(value: String) -> Prop {
  prop("key", value)
}

// Platform --------------------------------------------------------------------

@external(javascript, "./native_ffi.mjs", "platform_os")
fn platform_os() -> String

pub fn web() -> Bool {
  platform_os() == "web"
}

pub fn ios() -> Bool {
  platform_os() == "ios"
}

@external(javascript, "./native_ffi.mjs", "use_window_width")
pub fn use_window_width() -> Int

@external(javascript, "./native_ffi.mjs", "use_animated")
pub fn use_animated(target: Float, duration: Int) -> Animated

@external(javascript, "./native_ffi.mjs", "interpolate")
pub fn interpolate(value: Animated, from: a, to: a) -> Animated

/// A native alert; each button is `#(text, role, on_press)` where the role is
/// "default", "cancel" or "destructive".
@external(javascript, "./native_ffi.mjs", "alert")
pub fn alert(
  title: String,
  message: String,
  buttons: List(#(String, String, fn() -> Nil)),
) -> Nil

/// Gives `element` a React key, so a new key mounts a new instance.
@external(javascript, "./native_ffi.mjs", "keyed")
pub fn keyed(key: String, element: Element) -> Element

/// A JavaScript `Date` for today at this time.
pub type Date

@external(javascript, "./native_ffi.mjs", "date_at")
pub fn date_at(hour: Int, minute: Int) -> Date

/// The `onChange` of a time picker, called with the hour and minute picked.
@external(javascript, "./native_ffi.mjs", "on_time_change")
pub fn on_time_change(callback: fn(Int, Int) -> Nil) -> Prop
