//! Low-level light control, driven by the Raspberry Pi which owns the 4/6
//! breathing clock (30-003).

use robine_api::{sounds, Context, Device, Easing, LightLevel, Platform, Rgb};
use chrono::{TimeZone, Utc};
use serde_json::{json, Value};

const AMBER: Rgb = Rgb { r: 255, g: 120, b: 12 };
const ROSE: Rgb = Rgb { r: 255, g: 40, b: 70 };

fn platform(light: Option<&'static str>) -> Platform {
    Platform {
        target: "esp32",
        firmware_version: "test",
        http_port: 4000,
        sounds: sounds::BUNDLED,
        remote_dismiss_enabled: false,
        audio_available: false,
        light,
    }
}

fn device() -> Device {
    Device::new(platform(Some("Flora NeoPixel")))
}

fn ctx(monotonic_ms: u64) -> Context {
    Context {
        now: Utc.with_ymd_and_hms(2026, 10, 19, 20, 0, 0).unwrap(),
        monotonic_ms,
        clock_trusted: true,
        ipv4: None,
    }
}

fn command(device: &mut Device, monotonic_ms: u64, op: &str, body: Value) -> Value {
    let request = json!({ "v": 1, "op": op, "body": body });
    let (response, outcome) = device.handle(request.to_string().as_bytes(), &ctx(monotonic_ms));
    // The light is an output, not a state change for the app.
    assert!(outcome.events.is_empty() && !outcome.persist);
    serde_json::from_slice(&response).unwrap()
}

fn ok(response: Value) -> Value {
    assert_eq!(response["status"], "ok", "unexpected response: {response}");
    response["body"].clone()
}

fn error_code(response: &Value) -> &str {
    assert_eq!(response["status"], "error", "unexpected response: {response}");
    response["error"]["code"].as_str().unwrap()
}

fn color(rgb: Rgb) -> Value {
    json!({ "r": rgb.r, "g": rgb.g, "b": rgb.b })
}

#[test]
fn listed_only_when_a_light_is_wired() {
    let mut with = device();
    let operations = ok(command(&mut with, 0, "capabilities.get", json!({})))["operations"].clone();
    assert!(operations.as_array().unwrap().contains(&json!("light.set")));

    let mut without = Device::new(platform(None));
    let response = command(&mut without, 0, "light.set", json!({ "brightness": 10 }));
    assert_eq!(error_code(&response), "unsupported_operation");
}

#[test]
fn starts_off_and_sets_immediately_without_transition() {
    let mut device = device();
    assert_eq!(device.light(), None);
    let status = ok(command(&mut device, 0, "light.get", json!({})));
    assert_eq!(status["brightness"], 0.0);

    ok(command(&mut device, 1_000, "light.set", json!({ "color": color(ROSE), "brightness": 2 })));
    let level = device.light().unwrap().level_at(1_000);
    assert_eq!(level, LightLevel { color: ROSE, brightness: 2.0 });
    assert_eq!(level.output(), Rgb { r: 5, g: 1, b: 1 });
}

/// One command per phase, like the Pi's Hue commands.
#[test]
fn a_breathing_phase_is_one_transition() {
    let mut device = device();
    ok(command(&mut device, 0, "light.set", json!({ "color": color(ROSE), "brightness": 2 })));
    let inhale = json!({
        "color": color(AMBER), "brightness": 30, "transition_ms": 4_000, "easing": "smoothstep"
    });
    ok(command(&mut device, 10_000, "light.set", inhale));

    let fade = device.light().unwrap();
    assert_eq!(fade.easing, Easing::Smoothstep);
    assert_eq!(fade.level_at(10_000).brightness, 2.0);
    assert!((fade.level_at(12_000).brightness - 16.0).abs() < 1e-4);
    assert_eq!(fade.level_at(14_000), LightLevel { color: AMBER, brightness: 30.0 });
    assert_eq!(fade.level_at(99_000).color, AMBER);

    let status = ok(command(&mut device, 13_000, "light.get", json!({})));
    assert_eq!(status["transition_remaining_ms"], 1_000);
    assert_eq!(status["target"]["brightness"], 30.0);
}

#[test]
fn a_new_command_starts_from_the_color_on_display() {
    let mut device = device();
    ok(command(&mut device, 0, "light.set", json!({ "color": color(AMBER), "brightness": 30 })));
    ok(command(&mut device, 0, "light.set", json!({ "brightness": 0, "transition_ms": 1_000 })));
    // Interrupted halfway: the next fade begins at 15 %, not at 30 %.
    ok(command(&mut device, 500, "light.set", json!({ "brightness": 10, "transition_ms": 1_000 })));
    let fade = device.light().unwrap();
    assert_eq!(fade.from.brightness, 15.0);
    assert_eq!(fade.to.color, AMBER, "the color is kept when omitted");
}

#[test]
fn rejects_invalid_values() {
    let mut device = device();
    let cases = [
        (json!({}), "invalid_brightness"),
        (json!({ "brightness": 101 }), "invalid_brightness"),
        (json!({ "brightness": 10, "color": { "r": 256, "g": 0, "b": 0 } }), "invalid_color"),
        (json!({ "brightness": 10, "color": { "r": 1 } }), "invalid_color"),
        (json!({ "brightness": 10, "transition_ms": 60_001 }), "invalid_transition"),
        (json!({ "brightness": 10, "easing": "bounce" }), "invalid_easing"),
    ];
    for (body, code) in cases {
        assert_eq!(error_code(&command(&mut device, 0, "light.set", body)), code);
    }
    assert_eq!(device.light(), None);
}
