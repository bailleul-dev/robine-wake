//! Versioned command envelopes (`RobineWake.Bluetooth.Command`).

use alloc::collections::VecDeque;
use alloc::string::String;
use alloc::vec::Vec;

use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};

use crate::device::{DismissOrigin, Error, Result};
use crate::dto::{self, iso8601};
use crate::{Context, Device, Outcome};

const VERSION: u64 = 1;
/// Idempotency entries kept; fewer than the 256 of the Pi to fit in RAM.
const CACHE_ENTRIES: usize = 32;

/// Operations supported by this build, in the order of the Elixir list.
const OPERATIONS: &[&str] = &[
    "capabilities.get",
    "state.get",
    "alarm.create",
    "alarm.update",
    "alarm.delete",
    "alarm.preview",
    "alarm.trigger",
    "alarm.trigger_strong",
    "nap.start",
    "nap.cancel",
    "session.get",
    "session.snooze",
    "session.dismiss",
    "settings.smartphone_dismiss.set",
    "clock.confirm",
    "history.erase",
    "remote_button.status",
    "remote_button.pairing.begin",
    "remote_button.pair",
    "remote_button.remove",
    "remote_button.dismiss",
    "device.factory_reset",
];

/// Operations of a device with a light wired to it.
const LIGHT_OPERATIONS: &[&str] = &["light.set", "light.program", "light.get"];

/// Read-only operations: replays are answered by executing them again, so
/// only their fingerprint is kept.
const READ_ONLY: &[&str] = &[
    "capabilities.get",
    "state.get",
    "alarm.preview",
    "session.get",
    "remote_button.status",
    "light.get",
];

struct CacheEntry {
    id: String,
    fingerprint: [u8; 32],
    response: Option<Vec<u8>>,
}

/// Bounded idempotency cache (`RobineWake.CommandCache`).
#[derive(Default)]
pub(crate) struct CommandCache {
    entries: VecDeque<CacheEntry>,
}

impl CommandCache {
    fn get(&self, id: &str) -> Option<&CacheEntry> {
        self.entries.iter().find(|entry| entry.id == id)
    }

    fn put(&mut self, entry: CacheEntry) {
        if self.entries.len() >= CACHE_ENTRIES {
            self.entries.pop_front();
        }
        self.entries.push_back(entry);
    }
}

impl Device {
    /// Executes one `POST /api/v1/command` body and returns the JSON response.
    pub fn handle(&mut self, request: &[u8], ctx: &Context) -> (Vec<u8>, Outcome) {
        let mut out = Outcome::default();
        let response = match serde_json::from_slice::<Value>(request) {
            Ok(Value::Object(envelope)) => self.handle_envelope(&envelope, ctx, &mut out),
            _ => serialize(&dto::failure(&Value::Null, "invalid_envelope", None)),
        };
        (response, out)
    }

    fn handle_envelope(&mut self, envelope: &Map<String, Value>, ctx: &Context, out: &mut Outcome) -> Vec<u8> {
        let id = envelope.get("id").cloned().unwrap_or(Value::Null);
        let operation = envelope.get("op").and_then(Value::as_str);
        match (envelope.get("v"), operation) {
            (Some(version), Some(operation)) if version.as_u64() == Some(VERSION) => {
                match id.as_str() {
                    Some(request_id) => self.execute_cached(request_id, operation, envelope, ctx, out),
                    None => self.execute(operation, envelope, ctx, out),
                }
            }
            (Some(version), _) if version.as_u64() != Some(VERSION) => {
                serialize(&dto::failure(&id, "unsupported_version", None))
            }
            _ => serialize(&dto::failure(&id, "invalid_envelope", None)),
        }
    }

    fn execute_cached(
        &mut self,
        request_id: &str,
        operation: &str,
        envelope: &Map<String, Value>,
        ctx: &Context,
        out: &mut Outcome,
    ) -> Vec<u8> {
        let fingerprint: [u8; 32] = Sha256::digest(serialize(&Value::Object(envelope.clone()))).into();
        if let Some(entry) = self.cache.get(request_id) {
            if entry.fingerprint != fingerprint {
                return serialize(&dto::failure(&json!(request_id), "request_id_reused", None));
            }
            if let Some(response) = &entry.response {
                return response.clone();
            }
            return self.execute(operation, envelope, ctx, out);
        }

        let response = self.execute(operation, envelope, ctx, out);
        let stored = (!READ_ONLY.contains(&operation)).then(|| response.clone());
        self.cache.put(CacheEntry {
            id: request_id.into(),
            fingerprint,
            response: stored,
        });
        response
    }

    fn execute(&mut self, operation: &str, envelope: &Map<String, Value>, ctx: &Context, out: &mut Outcome) -> Vec<u8> {
        let id = envelope.get("id").cloned().unwrap_or(Value::Null);
        let empty = Map::new();
        let body = match envelope.get("body") {
            None | Some(Value::Null) => &empty,
            Some(Value::Object(body)) => body,
            Some(_) => return serialize(&dto::failure(&id, "invalid_body", None)),
        };

        let mut local = Outcome::default();
        let response = match self.dispatch(operation, body, ctx, &mut local) {
            Ok(result) => {
                out.merge(local);
                dto::success(&id, result)
            }
            // A failed operation leaves no side effect to apply.
            Err(Error::Code(code)) => dto::failure(&id, code, None),
            Err(Error::Validation(errors)) => {
                dto::failure(&id, "validation_failed", Some(json!(errors)))
            }
        };
        serialize(&response)
    }

    fn dispatch(&mut self, operation: &str, body: &Map<String, Value>, ctx: &Context, out: &mut Outcome) -> Result<Value> {
        let text = |key: &str| body.get(key).and_then(Value::as_str);
        let body_value = || Value::Object(body.clone());

        if self.platform.light.is_none() && LIGHT_OPERATIONS.contains(&operation) {
            return Err(Error::Code("unsupported_operation"));
        }

        match operation {
            "capabilities.get" => Ok(json!({
                "contract_version": VERSION,
                "security": "remote-button-hmac-sha256-counter",
                "operations": self.operations(),
                "response_transport": "http",
            })),
            "state.get" => Ok(self.state_payload(ctx)),

            "alarm.create" => {
                let alarm = self.create_alarm(&body_value(), ctx, out)?;
                Ok(dto::alarm(&alarm, ctx.now))
            }
            "alarm.update" => match (text("alarm_id"), body.get("alarm")) {
                (Some(id), Some(Value::Object(attrs))) => {
                    let alarm = self.update_alarm(id, attrs, ctx, out)?;
                    Ok(dto::alarm(&alarm, ctx.now))
                }
                _ => Err(Error::Code("invalid_body")),
            },
            "alarm.delete" => match (text("alarm_id"), body.get("revision")) {
                (Some(id), Some(revision)) if revision.is_i64() => {
                    self.delete_alarm(id, revision, ctx, out)?;
                    Ok(json!({ "deleted": id }))
                }
                _ => Err(Error::Code("invalid_body")),
            },
            "alarm.preview" => {
                let alarm = robine_core::Alarm::new(&body_value(), ctx.now)?;
                let occurrences: Vec<Value> = alarm
                    .next_occurrences(5, ctx.now)
                    .iter()
                    .map(|at| Value::String(iso8601(at)))
                    .collect();
                Ok(json!({ "next_occurrences": occurrences }))
            }
            "alarm.trigger" => {
                let id = text("alarm_id").ok_or(Error::Code("invalid_body"))?;
                self.trigger_alarm(id, false, ctx, out)?;
                Ok(json!({ "state": "starting" }))
            }
            "alarm.trigger_strong" => {
                let id = text("alarm_id").ok_or(Error::Code("invalid_body"))?;
                self.trigger_alarm(id, true, ctx, out)?;
                Ok(json!({ "state": "starting", "phase": "strong" }))
            }

            "nap.start" => {
                let minutes = body.get("duration_minutes").ok_or(Error::Code("invalid_body"))?;
                let alarm = self.start_nap(minutes, ctx, out)?;
                Ok(dto::alarm(&alarm, ctx.now))
            }
            "nap.cancel" => {
                self.cancel_nap(ctx, out)?;
                Ok(json!({ "cancelled": true }))
            }

            "session.get" => Ok(json!({ "active_session": self.active_session() })),
            "session.snooze" => self.snooze(ctx, out),
            "session.dismiss" => self.dismiss(DismissOrigin::Smartphone, ctx, out),

            "settings.smartphone_dismiss.set" => match body.get("enabled") {
                Some(Value::Bool(enabled)) => self.set_smartphone_dismiss(*enabled, out),
                _ => Err(Error::Code("invalid_body")),
            },
            "clock.confirm" => {
                out.clock_confirmed = true;
                out.publish(crate::STATE_CHANGED);
                Ok(json!({ "trusted": true, "source": "manual", "now": iso8601(&ctx.now) }))
            }
            "history.erase" => {
                self.erase_history(out);
                Ok(json!({ "erased": true }))
            }

            "remote_button.status" => Ok(self.remote_button_status(ctx)),
            "remote_button.pairing.begin" => self.begin_pairing(body.get("duration_seconds"), ctx, out),
            "remote_button.pair" => match (text("button_id"), text("name")) {
                (Some(id), Some(name)) => self.pair_button(id, name, ctx, out),
                _ => Err(Error::Code("invalid_body")),
            },
            "remote_button.remove" => {
                let id = text("button_id").ok_or(Error::Code("invalid_body"))?;
                self.remove_button(id, out)?;
                Ok(json!({ "removed": id }))
            }
            "remote_button.dismiss" => self.remote_dismiss(body, ctx, out),

            "light.set" => self.set_light(body, ctx),
            "light.program" => self.start_light_program(body, ctx),
            "light.get" => Ok(self.light_status(ctx)),

            "device.factory_reset" => match text("confirmation") {
                Some("RESET") => {
                    self.factory_reset(out);
                    Ok(json!({ "factory_reset": true }))
                }
                _ => Err(Error::Code("invalid_body")),
            },

            _ => Err(Error::Code("unsupported_operation")),
        }
    }

    fn operations(&self) -> Vec<&'static str> {
        let mut operations = OPERATIONS.to_vec();
        if self.platform.light.is_some() {
            operations.extend_from_slice(LIGHT_OPERATIONS);
        }
        operations
    }

    fn state_payload(&self, ctx: &Context) -> Value {
        let alarms: Vec<Value> = self.alarms().iter().map(|alarm| dto::alarm(alarm, ctx.now)).collect();
        let endpoints: Vec<Value> = ctx
            .ipv4
            .iter()
            .map(|[a, b, c, d]| {
                Value::String(alloc::format!(
                    "http://{a}.{b}.{c}.{d}:{}/api/v1/command",
                    self.platform.http_port
                ))
            })
            .collect();
        let state = if ctx.clock_trusted { "healthy" } else { "degraded" };
        let audio = if self.platform.audio_available { "available" } else { "unavailable" };

        json!({
            "device": {
                "state": state,
                "now": iso8601(&ctx.now),
                "target": self.platform.target,
                "version": self.platform.firmware_version,
                "clock_trusted": ctx.clock_trusted,
                "camera": { "enabled": false, "state": "unavailable", "calibrated": false, "frames": 0 },
                "audio": { "state": audio },
                "network": { "state": if ctx.ipv4.is_some() { "connected" } else { "unavailable" } },
                "firmware": { "version": self.platform.firmware_version, "validation": "unknown" },
                "updates": { "state": "unavailable", "reason": null },
            },
            "alarms": alarms,
            "sounds": self.platform.sounds,
            "recent_sessions": self.recent_sessions(8),
            "active_session": self.active_session(),
            "smartphone_dismiss": self.smartphone_dismiss(),
            "hue": null,
            "hue_targets": [],
            "remote_button": self.remote_button_status(ctx),
            "transport": {
                "preferred": "http",
                "http_endpoints": endpoints,
                "fallback": "none",
            },
        })
    }
}

fn serialize(value: &Value) -> Vec<u8> {
    serde_json::to_vec(value).expect("JSON values always serialize")
}
