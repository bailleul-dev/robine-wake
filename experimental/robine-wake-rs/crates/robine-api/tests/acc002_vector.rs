//! ACC-002 compatibility vector, end to end through the command boundary.
//! Own test binary: it replaces the process-wide random source.

use chrono::{TimeZone, Utc};
use robine_api::{sounds, Context, Device, Platform};
use serde_json::{json, Value};

fn fill_0x42(bytes: &mut [u8]) {
    bytes.fill(0x42);
}

#[test]
fn paired_secret_and_counter_7_match_the_specification_signature() {
    robine_core::random::set_source(fill_0x42);
    let mut device = Device::new(Platform {
        target: "esp32",
        firmware_version: "test",
        http_port: 4000,
        sounds: sounds::BUNDLED,
        remote_dismiss_enabled: false,
        audio_available: false,
    });
    let ctx = Context {
        now: Utc.with_ymd_and_hms(2026, 10, 19, 6, 0, 0).unwrap(),
        monotonic_ms: 0,
        clock_trusted: true,
        ipv4: None,
    };
    let send = |device: &mut Device, id: &str, op: &str, body: Value| -> Value {
        let request = json!({ "v": 1, "id": id, "op": op, "body": body }).to_string();
        serde_json::from_slice(&device.handle(request.as_bytes(), &ctx).0).unwrap()
    };

    send(&mut device, "1", "remote_button.pairing.begin", json!({}));
    let paired = send(
        &mut device,
        "2",
        "remote_button.pair",
        json!({ "button_id": "button-001122334455", "name": "Chevet" }),
    );
    assert_eq!(paired["body"]["secret_hex"], "42".repeat(32));

    let dismissed = send(
        &mut device,
        "3",
        "remote_button.dismiss",
        json!({
            "button_id": "button-001122334455",
            "counter": 7,
            "mac": "5afbdaf88cbe8167dd711c4492008bb956932b7351f26b60db69237639d9f995"
        }),
    );
    assert_eq!(dismissed["status"], "ok", "{dismissed}");
    assert_eq!(dismissed["body"]["session"]["terminal_reason"], "already_inactive");
}
