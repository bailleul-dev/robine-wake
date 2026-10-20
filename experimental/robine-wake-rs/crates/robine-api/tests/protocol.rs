//! Protocol compatibility with the mobile app (`mobile/src/actions.ts`,
//! `transport.ts`) and the remote button firmware (`hardware/remote_button`).

use chrono::{DateTime, Duration, TimeZone, Utc};
use robine_api::{sounds, Context, Device, Platform, SESSION_CHANGED, STATE_CHANGED};
use serde_json::{json, Value};
use std::sync::atomic::{AtomicU64, Ordering};

fn platform() -> Platform {
    Platform {
        target: "esp32",
        firmware_version: "test",
        http_port: 4000,
        sounds: sounds::BUNDLED,
        remote_dismiss_enabled: false,
        audio_available: false,
        light: None,
        light_pixels: 0,
    }
}

/// Monday 19 October 2026, 06:00 UTC (08:00 in Paris).
fn monday() -> DateTime<Utc> {
    Utc.with_ymd_and_hms(2026, 10, 19, 6, 0, 0).unwrap()
}

fn ctx(now: DateTime<Utc>) -> Context {
    Context {
        now,
        monotonic_ms: (now - monday()).num_milliseconds().max(0) as u64 + 1_000_000,
        clock_trusted: true,
        ipv4: Some([192, 168, 1, 154]),
    }
}

/// Sends a command with a fresh request id, like `makeRequestId` in the app.
fn command(device: &mut Device, now: DateTime<Utc>, op: &str, body: Value) -> Value {
    static NEXT_ID: AtomicU64 = AtomicU64::new(1);
    let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    let request = json!({ "v": 1, "id": format!("request-{id}"), "op": op, "body": body });
    let (response, _) = device.handle(request.to_string().as_bytes(), &ctx(now));
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

/// `draftToPayload` of the app for a 07:30 weekday alarm.
fn app_alarm(revision: Option<i64>) -> Value {
    let mut payload = json!({
        "label": "Réveil",
        "enabled": true,
        "local_time": "07:30:00",
        "days_of_week": [1, 2, 3, 4, 5],
        "timezone": "Europe/Paris",
        "sound_id": "jungle_sunrise",
        "strong_sound_id": "wake_up_call",
        "prewake_seconds": 1200,
        "volume_profile": { "start": 10, "ceiling": 70, "strong": 85, "ramp_seconds": 1200 },
        "light_profile": {
            "enabled": false,
            "start_brightness": 1,
            "end_brightness": 70,
            "ramp_seconds": 900,
            "end_behavior": "restore"
        },
        "dismiss_policy": "manual",
        "snooze": { "enabled": false }
    });
    if let Some(revision) = revision {
        payload["revision"] = json!(revision);
    }
    payload
}

#[test]
fn state_get_has_the_shape_the_app_reads() {
    let mut device = Device::new(platform());
    let state = ok(command(&mut device, monday(), "state.get", json!({})));

    for key in [
        "device",
        "alarms",
        "sounds",
        "recent_sessions",
        "active_session",
        "smartphone_dismiss",
        "hue",
        "hue_targets",
        "remote_button",
        "transport",
    ] {
        assert!(state.get(key).is_some(), "missing {key}");
    }
    assert_eq!(state["device"]["clock_trusted"], true);
    assert_eq!(
        state["transport"]["http_endpoints"],
        json!(["http://192.168.1.154:4000/api/v1/command"])
    );
    assert_eq!(state["smartphone_dismiss"], json!({ "enabled": false, "locked": true }));
    assert_eq!(state["sounds"].as_array().unwrap().len(), sounds::BUNDLED.len());
    assert!(state["active_session"].is_null());
}

#[test]
fn alarms_follow_the_app_create_update_delete_cycle() {
    let mut device = Device::new(platform());
    let now = monday();

    let created = ok(command(&mut device, now, "alarm.create", app_alarm(None)));
    let id = created["id"].as_str().unwrap().to_string();
    assert_eq!(created["revision"], 1);
    assert_eq!(created["local_time"], "07:30:00");
    // Tuesday 07:30 in Paris (CEST, UTC+2).
    assert_eq!(created["next_occurrences"][0], "2026-10-20T07:30:00+02:00");

    let mut disabled = app_alarm(Some(1));
    disabled["enabled"] = json!(false);
    let updated = ok(command(&mut device, now, "alarm.update", json!({ "alarm_id": id, "alarm": disabled })));
    assert_eq!(updated["revision"], 2);
    assert_eq!(updated["enabled"], false);
    assert_eq!(updated["next_occurrences"], json!([]));

    let stale = command(&mut device, now, "alarm.update", json!({ "alarm_id": id, "alarm": app_alarm(Some(1)) }));
    assert_eq!(error_code(&stale), "revision_conflict");

    let missing = command(&mut device, now, "alarm.delete", json!({ "alarm_id": id }));
    assert_eq!(error_code(&missing), "invalid_body");

    let deleted = ok(command(&mut device, now, "alarm.delete", json!({ "alarm_id": id, "revision": 2 })));
    assert_eq!(deleted["deleted"], id);
    assert_eq!(ok(command(&mut device, now, "state.get", json!({})))["alarms"], json!([]));
}

#[test]
fn rejects_unknown_sounds_and_invalid_fields() {
    let mut device = Device::new(platform());
    let mut alarm = app_alarm(None);
    alarm["sound_id"] = json!("missing.mp3");
    let response = command(&mut device, monday(), "alarm.create", alarm);
    assert_eq!(error_code(&response), "validation_failed");
    assert_eq!(
        response["error"]["details"]["sound_id"],
        "does not reference an available validated sound"
    );

    let response = command(&mut device, monday(), "alarm.create", json!({ "local_time": "25:00" }));
    assert_eq!(error_code(&response), "validation_failed");
}

#[test]
fn nap_creates_then_replaces_then_cancels_the_nap_alarm() {
    let mut device = Device::new(platform());
    let now = monday();
    ok(command(&mut device, now, "alarm.create", app_alarm(None)));

    let nap = ok(command(&mut device, now, "nap.start", json!({ "duration_minutes": 20 })));
    assert_eq!(nap["id"], "nap");
    assert_eq!(nap["label"], "Sieste");
    assert_eq!(nap["one_shot_date"], "2026-10-19");
    assert_eq!(nap["local_time"], "08:20:00");
    assert_eq!(nap["prewake_seconds"], 120);
    assert_eq!(nap["sound_id"], "jungle_sunrise");

    let longer = ok(command(&mut device, now, "nap.start", json!({ "duration_minutes": 30 })));
    assert_eq!(longer["revision"], 2);
    assert_eq!(longer["local_time"], "08:30:00");

    let invalid = command(&mut device, now, "nap.start", json!({ "duration_minutes": 0 }));
    assert_eq!(error_code(&invalid), "validation_failed");

    ok(command(&mut device, now, "nap.cancel", json!({})));
    let alarms = ok(command(&mut device, now, "state.get", json!({})))["alarms"].clone();
    assert!(alarms.as_array().unwrap().iter().all(|alarm| alarm["id"] != "nap"));
}

#[test]
fn nap_rings_once_then_disables_itself() {
    let mut device = Device::new(platform());
    let start = monday();
    ok(command(&mut device, start, "nap.start", json!({ "duration_minutes": 10 })));

    // The two-minute ramp starts eight minutes after the nap began.
    assert!(device.tick(&ctx(start + Duration::minutes(7))).events.is_empty());
    let outcome = device.tick(&ctx(start + Duration::minutes(8)));
    assert!(outcome.persist);
    assert!(outcome.events.contains(&SESSION_CHANGED));
    assert!(device.audio().is_some());

    let state = ok(command(&mut device, start + Duration::minutes(8), "state.get", json!({})));
    assert_eq!(state["active_session"]["alarm_id"], "nap");
    assert_eq!(state["alarms"][0]["enabled"], false);
}

/// Scheduler fires at `local_time - prewake`; only the remote button stops a
/// real alarm, with the HMAC and counter of the button firmware.
#[test]
fn scheduled_alarm_rings_and_only_the_remote_button_stops_it() {
    let mut device = Device::new(platform());
    let now = monday();
    ok(command(&mut device, now, "alarm.create", app_alarm(None)));
    device.refresh_schedule(&ctx(now));

    // Pair the button the way `remote_button.pairing.begin` then `pair` do.
    ok(command(&mut device, now, "remote_button.pairing.begin", json!({ "duration_seconds": 120 })));
    let paired = ok(command(
        &mut device,
        now,
        "remote_button.pair",
        json!({ "button_id": "screen-01", "name": "Chevet" }),
    ));
    assert_eq!(paired["next_counter"], 1);
    let secret = hex::decode(paired["secret_hex"].as_str().unwrap()).unwrap();

    // Tuesday 07:30 Paris = 05:30 UTC, the gentle ramp starts 20 minutes before.
    let ramp = Utc.with_ymd_and_hms(2026, 10, 20, 5, 10, 0).unwrap();
    assert!(!device.tick(&ctx(ramp - Duration::seconds(1))).persist);
    let outcome = device.tick(&ctx(ramp));
    assert_eq!(outcome.events, vec![SESSION_CHANGED]);
    let audio = device.audio().unwrap();
    assert_eq!((audio.sound_id, audio.gain), ("jungle_sunrise", 10));

    // The phone is refused: getting up is the point.
    let refused = command(&mut device, ramp, "session.dismiss", json!({}));
    assert_eq!(error_code(&refused), "smartphone_dismiss_disabled");

    // The button polls `session.get` without an id.
    let (polled, _) = device.handle(br#"{"v":1,"op":"session.get","body":{}}"#, &ctx(ramp));
    let polled: Value = serde_json::from_slice(&polled).unwrap();
    assert_eq!(polled["id"], Value::Null);
    assert_eq!(polled["body"]["active_session"]["state"], "ringing");

    let mac = robine_core::remote_button::compute_dismiss_hmac(&secret, "screen-01", 1).unwrap();
    let dismiss = json!({ "button_id": "screen-01", "counter": 1, "mac": mac });
    let stopped = ok(command(&mut device, ramp, "remote_button.dismiss", dismiss.clone()));
    assert_eq!(stopped["accepted"], true);
    assert_eq!(stopped["duplicate"], false);
    assert_eq!(stopped["session"]["state"], "dismissed");
    assert_eq!(stopped["session"]["terminal_reason"], "remote_button");
    assert!(device.audio().is_none());

    // A Wi-Fi retry of the same press is acknowledged, an older one rejected.
    let retry = ok(command(&mut device, ramp + Duration::seconds(1), "remote_button.dismiss", dismiss));
    assert_eq!(retry["duplicate"], true);
    let bad = json!({ "button_id": "screen-01", "counter": 2, "mac": "00".repeat(32) });
    let rejected = command(&mut device, ramp, "remote_button.dismiss", bad);
    assert_eq!(error_code(&rejected), "invalid_remote_button_signature");

    let state = ok(command(&mut device, ramp, "state.get", json!({})));
    assert_eq!(state["recent_sessions"][0]["state"], "dismissed");
    assert_eq!(state["remote_button"]["buttons"][0]["last_counter"], 1);
    assert!(state["remote_button"]["buttons"][0].get("secret_hex").is_none());

    // The next occurrence is Wednesday.
    let wednesday = Utc.with_ymd_and_hms(2026, 10, 21, 5, 10, 0).unwrap();
    assert!(device.tick(&ctx(wednesday)).events.contains(&SESSION_CHANGED));
}

#[test]
fn test_alarms_can_be_stopped_from_the_phone() {
    let mut device = Device::new(platform());
    let now = monday();
    let id = ok(command(&mut device, now, "alarm.create", app_alarm(None)))["id"].clone();

    assert_eq!(ok(command(&mut device, now, "alarm.trigger", json!({ "alarm_id": id })))["state"], "starting");
    let busy = command(&mut device, now, "alarm.trigger_strong", json!({ "alarm_id": id }));
    assert_eq!(error_code(&busy), "active_session");

    let session = ok(command(&mut device, now, "session.dismiss", json!({})));
    assert_eq!(session["state"], "dismissed");
    assert_eq!(session["test_mode"], true);

    ok(command(&mut device, now, "alarm.trigger_strong", json!({ "alarm_id": id })));
    assert_eq!(device.audio().unwrap().sound_id, "wake_up_call");
    assert_eq!(device.audio().unwrap().gain, 85);

    let idle = ok(command(&mut device, now, "session.dismiss", json!({})));
    assert_eq!(idle["state"], "dismissed");
    let idle = ok(command(&mut device, now, "session.dismiss", json!({})));
    assert_eq!(idle, json!({ "state": "idle", "terminal_reason": "already_inactive" }));
}

#[test]
fn pairing_requires_an_open_window() {
    let mut device = Device::new(platform());
    let now = monday();
    let closed = command(&mut device, now, "remote_button.pair", json!({ "button_id": "b1", "name": "Chevet" }));
    assert_eq!(error_code(&closed), "pairing_window_closed");

    ok(command(&mut device, now, "remote_button.pairing.begin", json!({ "duration_seconds": 30 })));
    device.tick(&ctx(now + Duration::seconds(31)));
    let expired = command(
        &mut device,
        now + Duration::seconds(31),
        "remote_button.pair",
        json!({ "button_id": "b1", "name": "Chevet" }),
    );
    assert_eq!(error_code(&expired), "pairing_window_closed");

    let removed = command(&mut device, now, "remote_button.remove", json!({ "button_id": "b1" }));
    assert_eq!(error_code(&removed), "remote_button_not_paired");
}

#[test]
fn replayed_request_ids_are_idempotent() {
    let mut device = Device::new(platform());
    let request = json!({ "v": 1, "id": "same", "op": "alarm.create", "body": app_alarm(None) }).to_string();

    let (first, outcome) = device.handle(request.as_bytes(), &ctx(monday()));
    assert!(outcome.persist);
    assert_eq!(outcome.events, vec![STATE_CHANGED]);
    let (second, outcome) = device.handle(request.as_bytes(), &ctx(monday()));
    assert_eq!(first, second);
    assert!(!outcome.persist);

    let reused = json!({ "v": 1, "id": "same", "op": "nap.cancel", "body": {} }).to_string();
    let (response, _) = device.handle(reused.as_bytes(), &ctx(monday()));
    assert_eq!(error_code(&serde_json::from_slice(&response).unwrap()), "request_id_reused");

    let state = ok(command(&mut device, monday(), "state.get", json!({})));
    assert_eq!(state["alarms"].as_array().unwrap().len(), 1);
}

#[test]
fn envelope_errors_match_the_elixir_codes() {
    let mut device = Device::new(platform());
    let cases: [(&[u8], &str); 4] = [
        (b"not json", "invalid_envelope"),
        (br#"{"v":2,"id":"x","op":"state.get"}"#, "unsupported_version"),
        (br#"{"v":1,"id":"y"}"#, "invalid_envelope"),
        (br#"{"v":1,"id":"z","op":"hue.pair","body":{}}"#, "unsupported_operation"),
    ];
    for (request, code) in cases {
        let (response, _) = device.handle(request, &ctx(monday()));
        assert_eq!(error_code(&serde_json::from_slice(&response).unwrap()), code);
    }
}

#[test]
fn snapshot_survives_a_restart_and_resumes_a_ringing_alarm() {
    let mut device = Device::new(platform());
    let now = monday();
    ok(command(&mut device, now, "alarm.create", app_alarm(None)));
    device.refresh_schedule(&ctx(now));
    let ramp = Utc.with_ymd_and_hms(2026, 10, 20, 5, 10, 0).unwrap();
    device.tick(&ctx(ramp));
    assert!(device.audio().is_some());

    // Power cut two minutes later.
    let snapshot = device.snapshot();
    let mut restored = Device::restore(platform(), &snapshot).unwrap();
    let after = ramp + Duration::minutes(2);
    restored.refresh_schedule(&ctx(after));
    assert!(restored.audio().is_none());

    let outcome = restored.tick(&ctx(after));
    assert!(outcome.events.contains(&SESSION_CHANGED));
    assert!(restored.audio().is_some(), "the alarm rings again after a restart");

    let state = ok(command(&mut restored, after, "state.get", json!({})));
    assert_eq!(state["recent_sessions"][1]["state"], "interrupted");
    assert_eq!(state["alarms"].as_array().unwrap().len(), 1);
}

#[test]
fn untrusted_clock_never_fires_alarms() {
    let mut device = Device::new(platform());
    ok(command(&mut device, monday(), "nap.start", json!({ "duration_minutes": 1 })));
    let mut later = ctx(monday() + Duration::minutes(5));
    later.clock_trusted = false;
    assert!(device.tick(&later).events.is_empty());
    assert!(device.audio().is_none());
}
