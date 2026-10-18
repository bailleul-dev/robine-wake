//! V1 Command Protocol and Idempotency Cache (API-002, ACC-002).
//!
//! Processes versioned `POST /api/v1/command` envelopes from mobile app and ESP32 buttons
//! with an in-memory bounded idempotency cache to deduplicate network retries.

use chrono::Utc;
use robine_core::alarm::Alarm;
use robine_core::remote_button::PairedButton;
use robine_core::session::DismissSource;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use crate::audio::AudioSink;
use crate::clock::Clock;
use crate::events::EventStream;
use crate::lora::LoraService;
use crate::session_manager::SessionManager;
use crate::sounds::Sounds;
use crate::store::Store;

const CACHE_CAPACITY: usize = 64;
const CACHE_TTL_SECS: u64 = 300; // 5 minutes (API-002, ACC-002)

#[derive(Clone, Debug, Deserialize)]
pub struct CommandEnvelope {
    #[allow(dead_code)]
    pub v: u32,
    pub id: String,
    pub op: String,
    #[serde(default)]
    pub body: Value,
}

#[derive(Clone, Debug, Serialize)]
pub struct CommandResponse {
    pub v: u32,
    pub id: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<Value>,
}

struct CacheEntry {
    response: CommandResponse,
    inserted: Instant,
}

pub struct CommandHandler {
    store: Arc<Store>,
    sessions: Arc<SessionManager>,
    clock: Arc<Clock>,
    #[allow(dead_code)]
    sounds: Arc<Sounds>,
    audio: Arc<AudioSink>,
    lora: Option<Arc<LoraService>>,
    events: EventStream,
    cache: Mutex<HashMap<String, CacheEntry>>,
}

impl CommandHandler {
    #[allow(dead_code)]
    pub fn new(
        store: Arc<Store>,
        sessions: Arc<SessionManager>,
        clock: Arc<Clock>,
        sounds: Arc<Sounds>,
        audio: Arc<AudioSink>,
        events: EventStream,
    ) -> Self {
        Self::with_lora(store, sessions, clock, sounds, audio, events, None)
    }

    pub fn with_lora(
        store: Arc<Store>,
        sessions: Arc<SessionManager>,
        clock: Arc<Clock>,
        sounds: Arc<Sounds>,
        audio: Arc<AudioSink>,
        events: EventStream,
        lora: Option<Arc<LoraService>>,
    ) -> Self {
        Self {
            store,
            sessions,
            clock,
            sounds,
            audio,
            lora,
            events,
            cache: Mutex::new(HashMap::new()),
        }
    }

    /// Process a command envelope, consulting the idempotence cache first (API-002.2).
    pub async fn handle(&self, envelope: CommandEnvelope) -> CommandResponse {
        // 1. Check idempotency cache
        {
            let cache = self.cache.lock().unwrap();
            if let Some(entry) = cache.get(&envelope.id) {
                if entry.inserted.elapsed().as_secs() < CACHE_TTL_SECS {
                    return entry.response.clone();
                }
            }
        }

        // 2. Execute operation
        let response = self.execute(&envelope).await;

        // 3. Cache response (LRU-bounded)
        {
            let mut cache = self.cache.lock().unwrap();
            if cache.len() >= CACHE_CAPACITY {
                let oldest = cache
                    .iter()
                    .min_by_key(|(_, v)| v.inserted)
                    .map(|(k, _)| k.clone());
                if let Some(k) = oldest {
                    cache.remove(&k);
                }
            }
            cache.insert(
                envelope.id.clone(),
                CacheEntry {
                    response: response.clone(),
                    inserted: Instant::now(),
                },
            );
        }

        response
    }

    async fn execute(&self, env: &CommandEnvelope) -> CommandResponse {
        let now = Utc::now();

        match env.op.as_str() {
            "capabilities.get" => ok(
                &env.id,
                json!({
                    "airplay": self.audio.airplay_available(),
                    "bluetooth": self.audio.bluetooth_available(),
                    "hue": false,
                    "guided_breathing": false,
                    "lora": self.lora.as_ref().map(|l| l.is_available()).unwrap_or(false),
                    "remote_button": true,
                    "mcp": true,
                }),
            ),

            "state.get" => {
                let alarms: Vec<Value> = self
                    .store
                    .list()
                    .iter()
                    .map(|a| alarm_json(a, now))
                    .collect();
                ok(
                    &env.id,
                    json!({
                        "alarms": alarms,
                        "sessions": self.store.raw("sessions"),
                        "active_session": self.sessions.active_snapshot(),
                        "smartphone_dismiss": {
                            "enabled": self.store.get_smartphone_dismiss_enabled(),
                            "locked": false,
                        },
                        "clock": {
                            "now": now.to_rfc3339(),
                            "quality": self.clock.quality(),
                        }
                    }),
                )
            }

            "alarm.create" => match self.store.create(&env.body, now) {
                Ok(alarm) => {
                    self.events.publish("state.changed", None);
                    ok(&env.id, json!({ "alarm": alarm_json(&alarm, now) }))
                }
                Err(e) => err(&env.id, "validation_failed", json!(format!("{e:?}"))),
            },

            "alarm.update" => {
                let id = env.body.get("id").and_then(Value::as_str).unwrap_or("");
                match self.store.update(id, &env.body, now) {
                    Ok(alarm) => {
                        self.events.publish("state.changed", None);
                        ok(&env.id, json!({ "alarm": alarm_json(&alarm, now) }))
                    }
                    Err(e) => err(&env.id, "update_failed", json!(format!("{e:?}"))),
                }
            }

            "alarm.delete" => {
                let id = env.body.get("id").and_then(Value::as_str).unwrap_or("");
                let revision = env.body.get("revision");
                match self.store.delete(id, revision) {
                    Ok(()) => {
                        self.events.publish("state.changed", None);
                        ok(&env.id, json!({ "deleted": true }))
                    }
                    Err(e) => err(&env.id, "delete_failed", json!(format!("{e:?}"))),
                }
            }

            "alarm.preview" => match Alarm::new(&env.body, now) {
                Ok(alarm) => ok(&env.id, json!({ "alarm": alarm_json(&alarm, now) })),
                Err(errors) => err(&env.id, "validation_failed", json!(errors)),
            },

            "alarm.trigger" => {
                let id = env.body.get("id").and_then(Value::as_str).unwrap_or("");
                let alarm = match self.store.list().into_iter().find(|a| a.id == id) {
                    Some(a) => a,
                    None => return err(&env.id, "not_found", json!("alarm not found")),
                };

                match self.sessions.trigger_alarm(&alarm, now).await {
                    Ok(session) => ok(&env.id, json!({ "session": session })),
                    Err(e) => err(&env.id, "trigger_failed", json!(e)),
                }
            }

            // ALM-003: Nap mode
            "nap.start" => {
                let minutes = env
                    .body
                    .get("duration_minutes")
                    .or_else(|| env.body.get("minutes"))
                    .and_then(Value::as_u64)
                    .unwrap_or(0) as u32;

                match self.store.start_nap(minutes, now) {
                    Ok(alarm) => {
                        self.events.publish("state.changed", None);
                        ok(&env.id, json!({ "alarm": alarm_json(&alarm, now) }))
                    }
                    Err(e) => err(&env.id, "validation_failed", json!(format!("{e:?}"))),
                }
            }

            "nap.cancel" => match self.store.cancel_nap() {
                Ok(()) => {
                    self.events.publish("state.changed", None);
                    ok(&env.id, json!({ "cancelled": true }))
                }
                Err(e) => err(&env.id, "cancel_failed", json!(format!("{e:?}"))),
            },

            "session.get" => ok(
                &env.id,
                json!({ "active_session": self.sessions.active_snapshot() }),
            ),

            "session.snooze" => match self.sessions.snooze(now).await {
                Ok(session) => ok(&env.id, json!({ "session": session })),
                Err(e) => err(&env.id, &e, json!(e)),
            },

            "session.dismiss" => match self.sessions.dismiss(DismissSource::RemoteApi, now).await {
                Ok(session) => ok(&env.id, json!({ "session": session })),
                Err(e) => err(&env.id, &e, json!(e)),
            },

            // ACC-002: ESP32 Wi-Fi button dismiss request with HMAC and monotonic counter
            "remote_button.dismiss" => {
                let button_id = env
                    .body
                    .get("identifiant")
                    .or_else(|| env.body.get("button_id"))
                    .and_then(Value::as_str)
                    .unwrap_or("");
                let counter = env
                    .body
                    .get("compteur")
                    .or_else(|| env.body.get("counter"))
                    .and_then(Value::as_u64)
                    .unwrap_or(0);
                let signature = env
                    .body
                    .get("signature")
                    .and_then(Value::as_str)
                    .unwrap_or("");

                let mut button = match self.store.get_button(button_id) {
                    Some(b) => b,
                    None => return err(&env.id, "unknown_button", json!("button not paired")),
                };

                match button.verify_and_advance(counter, signature) {
                    Ok(robine_core::remote_button::ButtonResult::DismissAccepted) => {
                        // ACC-002.3: Persist counter BEFORE stopping the session
                        if let Err(e) = self.store.save_button(&button) {
                            return err(&env.id, "storage_error", json!(format!("{e:?}")));
                        }

                        // Dismiss session via physical/remote button source
                        let session = self
                            .sessions
                            .dismiss(DismissSource::RemoteButton, now)
                            .await
                            .ok();
                        ok(
                            &env.id,
                            json!({
                                "dismissed": true,
                                "session": session,
                            }),
                        )
                    }
                    Ok(robine_core::remote_button::ButtonResult::DuplicateAcknowledged) => ok(
                        &env.id,
                        json!({ "dismissed": false, "reason": "duplicate" }),
                    ),
                    Err(e) => err(&env.id, "invalid_button_signature", json!(e.to_string())),
                }
            }

            "remote_button.pair" => {
                let button_id = env.body.get("id").and_then(Value::as_str).unwrap_or("");
                if button_id.is_empty() {
                    return err(&env.id, "invalid_id", json!("button id required"));
                }
                let mut secret = Vec::with_capacity(32);
                secret.extend_from_slice(uuid::Uuid::new_v4().as_bytes());
                secret.extend_from_slice(uuid::Uuid::new_v4().as_bytes());

                let button = PairedButton::new(button_id, secret.clone(), 0);
                match self.store.save_button(&button) {
                    Ok(()) => ok(
                        &env.id,
                        json!({
                            "button_id": button.id,
                            "secret": hex::encode(secret),
                        }),
                    ),
                    Err(e) => err(&env.id, "storage_error", json!(format!("{e:?}"))),
                }
            }

            "settings.smartphone_dismiss.set" => {
                let enabled = env
                    .body
                    .get("enabled")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                match self.store.set_smartphone_dismiss_enabled(enabled) {
                    Ok(()) => {
                        self.events.publish("state.changed", None);
                        ok(&env.id, json!({ "smartphone_dismiss_enabled": enabled }))
                    }
                    Err(e) => err(&env.id, "storage_error", json!(format!("{e:?}"))),
                }
            }

            "clock.confirm" => {
                self.clock.confirm();
                ok(&env.id, json!({ "confirmed": true }))
            }

            "history.erase" => match self.store.clear_history() {
                Ok(()) => {
                    self.events.publish("state.changed", None);
                    ok(&env.id, json!({ "history_erased": true }))
                }
                Err(e) => err(&env.id, "storage_error", json!(format!("{e:?}"))),
            },

            "device.factory_reset" => {
                let confirmation = env
                    .body
                    .get("confirmation")
                    .and_then(Value::as_str)
                    .unwrap_or("");
                if confirmation != "RESET" {
                    return err(
                        &env.id,
                        "invalid_confirmation",
                        json!("confirmation must be RESET"),
                    );
                }
                match self.store.factory_reset() {
                    Ok(()) => {
                        self.events.publish("state.changed", None);
                        ok(&env.id, json!({ "factory_reset": true }))
                    }
                    Err(e) => err(&env.id, "storage_error", json!(format!("{e:?}"))),
                }
            }

            "camera.calibrate" => err(
                &env.id,
                "capability_unavailable",
                json!("camera feature removed"),
            ),

            // ACC-001: Philips Hue excluded from v2 scope
            "hue.pair" | "hue.refresh" | "hue.disconnect" => err(
                &env.id,
                "capability_unavailable",
                json!("Philips Hue feature removed from v2 scope"),
            ),

            // AUD-004: Guided breathing excluded from v2 scope
            "breathing.start" | "breathing.volume" | "breathing.stop" => err(
                &env.id,
                "capability_unavailable",
                json!("guided breathing feature removed from v2 scope"),
            ),

            unknown => err(
                &env.id,
                "unknown_operation",
                json!(format!("operation '{unknown}' not supported")),
            ),
        }
    }
}

fn ok(id: &str, body: Value) -> CommandResponse {
    CommandResponse {
        v: 1,
        id: id.to_string(),
        status: "ok".to_string(),
        body: Some(body),
        error: None,
    }
}

fn err(id: &str, code: &str, details: Value) -> CommandResponse {
    CommandResponse {
        v: 1,
        id: id.to_string(),
        status: "error".to_string(),
        body: None,
        error: Some(json!({ "code": code, "details": details })),
    }
}

fn alarm_json(alarm: &Alarm, now: chrono::DateTime<Utc>) -> Value {
    let occurrences: Vec<Value> = if alarm.enabled {
        alarm
            .next_occurrences(5, now)
            .iter()
            .map(|at| json!(at.to_rfc3339_opts(chrono::SecondsFormat::Secs, false)))
            .collect()
    } else {
        Vec::new()
    };
    let mut map = alarm.to_map();
    map.insert("next_occurrences".into(), Value::Array(occurrences));
    Value::Object(map)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audio::AudioSink;
    use robine_core::remote_button::compute_dismiss_hmac;

    #[tokio::test]
    async fn handles_v1_commands_and_caches_idempotently() {
        let scratch = std::env::temp_dir().join(format!("cmd-test-{}", uuid::Uuid::new_v4()));
        let store = Arc::new(Store::open(scratch.join("db.json"), |_| true));
        let audio = Arc::new(AudioSink::new());
        let events = EventStream::new();
        let sessions = Arc::new(SessionManager::new(audio.clone(), store.clone(), events.clone()));
        let clock = Arc::new(Clock::new());
        let sounds = Arc::new(Sounds::open(scratch.join("sounds")));

        let handler = CommandHandler::new(store, sessions, clock, sounds, audio.clone(), events);

        // 1. capabilities.get
        let env = CommandEnvelope {
            v: 1,
            id: "cmd-1".into(),
            op: "capabilities.get".into(),
            body: Value::Null,
        };
        let resp1 = handler.handle(env.clone()).await;
        assert_eq!(resp1.status, "ok");
        let body = resp1.body.unwrap();
        assert_eq!(body["remote_button"], json!(true));
        assert_eq!(body["mcp"], json!(true));

        // 2. Replay with same ID -> exact same cached response (API-002.2)
        let resp2 = handler.handle(env).await;
        assert_eq!(resp2.id, "cmd-1");
        assert_eq!(resp2.status, "ok");
    }

    #[tokio::test]
    async fn verifies_esp32_button_dismiss_command() {
        let scratch = std::env::temp_dir().join(format!("cmd-btn-{}", uuid::Uuid::new_v4()));
        let store = Arc::new(Store::open(scratch.join("db.json"), |_| true));
        let audio = Arc::new(AudioSink::new());
        let events = EventStream::new();
        let sessions = Arc::new(SessionManager::new(audio.clone(), store.clone(), events.clone()));
        let clock = Arc::new(Clock::new());
        let sounds = Arc::new(Sounds::open(scratch.join("sounds")));

        // Pair button with ACC-002 test vector
        let secret = vec![0x42u8; 32];
        let button = PairedButton::new("button-001122334455", secret.clone(), 6);
        store.save_button(&button).unwrap();

        let handler = CommandHandler::new(store, sessions, clock, sounds, audio.clone(), events);

        let sig = compute_dismiss_hmac(&secret, "button-001122334455", 7).unwrap();
        let env = CommandEnvelope {
            v: 1,
            id: "cmd-btn-1".into(),
            op: "remote_button.dismiss".into(),
            body: json!({
                "identifiant": "button-001122334455",
                "compteur": 7,
                "signature": sig,
            }),
        };

        let resp = handler.handle(env).await;
        assert_eq!(resp.status, "ok");
        assert_eq!(resp.body.unwrap()["dismissed"], json!(true));
    }

    #[tokio::test]
    async fn returns_capability_unavailable_for_excluded_features() {
        let scratch = std::env::temp_dir().join(format!("cmd-ex-{}", uuid::Uuid::new_v4()));
        let store = Arc::new(Store::open(scratch.join("db.json"), |_| true));
        let audio = Arc::new(AudioSink::new());
        let events = EventStream::new();
        let sessions = Arc::new(SessionManager::new(audio.clone(), store.clone(), events.clone()));
        let clock = Arc::new(Clock::new());
        let sounds = Arc::new(Sounds::open(scratch.join("sounds")));
        let handler = CommandHandler::new(store, sessions, clock, sounds, audio.clone(), events);

        for op in [
            "hue.pair",
            "hue.refresh",
            "hue.disconnect",
            "breathing.start",
            "breathing.volume",
            "breathing.stop",
            "camera.calibrate",
        ] {
            let env = CommandEnvelope {
                v: 1,
                id: format!("test-{op}"),
                op: op.into(),
                body: Value::Null,
            };
            let resp = handler.handle(env).await;
            assert_eq!(resp.status, "error");
            assert_eq!(
                resp.error.as_ref().unwrap()["code"],
                "capability_unavailable",
                "op {op} did not return capability_unavailable"
            );
        }
    }

    #[tokio::test]
    async fn handles_nap_commands() {
        let scratch = std::env::temp_dir().join(format!("cmd-nap-{}", uuid::Uuid::new_v4()));
        let store = Arc::new(Store::open(scratch.join("db.json"), |_| true));
        let audio = Arc::new(AudioSink::new());
        let events = EventStream::new();
        let sessions = Arc::new(SessionManager::new(audio.clone(), store.clone(), events.clone()));
        let clock = Arc::new(Clock::new());
        let sounds = Arc::new(Sounds::open(scratch.join("sounds")));
        let handler = CommandHandler::new(store, sessions, clock, sounds, audio.clone(), events);

        // 1. nap.start
        let env_start = CommandEnvelope {
            v: 1,
            id: "cmd-nap-start".into(),
            op: "nap.start".into(),
            body: json!({ "duration_minutes": 25 }),
        };
        let resp_start = handler.handle(env_start).await;
        assert_eq!(resp_start.status, "ok");
        let alarm = resp_start.body.unwrap()["alarm"].clone();
        assert_eq!(alarm["id"], "nap");
        assert_eq!(alarm["prewake_seconds"], 120);

        // 2. nap.cancel
        let env_cancel = CommandEnvelope {
            v: 1,
            id: "cmd-nap-cancel".into(),
            op: "nap.cancel".into(),
            body: json!({}),
        };
        let resp_cancel = handler.handle(env_cancel).await;
        assert_eq!(resp_cancel.status, "ok");
        assert_eq!(resp_cancel.body.unwrap()["cancelled"], json!(true));
    }

    #[tokio::test]
    async fn handles_device_factory_reset_command() {
        let scratch = std::env::temp_dir().join(format!("cmd-fr-{}", uuid::Uuid::new_v4()));
        let store = Arc::new(Store::open(scratch.join("db.json"), |_| true));
        let audio = Arc::new(AudioSink::new());
        let events = EventStream::new();
        let sessions = Arc::new(SessionManager::new(audio.clone(), store.clone(), events.clone()));
        let clock = Arc::new(Clock::new());
        let sounds = Arc::new(Sounds::open(scratch.join("sounds")));
        let handler = CommandHandler::new(store.clone(), sessions, clock, sounds, audio.clone(), events);

        store
            .create(&json!({ "label": "Morning" }), Utc::now())
            .unwrap();
        assert_eq!(store.list().len(), 1);

        // Rejected without "RESET" confirmation
        let env_bad = CommandEnvelope {
            v: 1,
            id: "fr-bad".into(),
            op: "device.factory_reset".into(),
            body: json!({ "confirmation": "no" }),
        };
        let resp_bad = handler.handle(env_bad).await;
        assert_eq!(resp_bad.status, "error");
        assert_eq!(resp_bad.error.unwrap()["code"], "invalid_confirmation");

        // Accepted with "RESET"
        let env_ok = CommandEnvelope {
            v: 1,
            id: "fr-ok".into(),
            op: "device.factory_reset".into(),
            body: json!({ "confirmation": "RESET" }),
        };
        let resp_ok = handler.handle(env_ok).await;
        assert_eq!(resp_ok.status, "ok");
        assert_eq!(resp_ok.body.unwrap()["factory_reset"], true);
        assert_eq!(store.list().len(), 0);
    }
}
