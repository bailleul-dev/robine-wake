//! Model Context Protocol (MCP) Streamable HTTP server (API-003).
//!
//! Provides JSON-RPC 2.0 tool discovery and execution for local AI agents.
//! Supported protocol versions: "2025-06-18", "2025-03-26".

use std::sync::Arc;

use axum::http::StatusCode;
use chrono::Utc;
use serde_json::{json, Value};

use crate::alarm::Alarm;
use crate::clock::Clock;
use crate::events::EventStream;
use crate::scheduler::Scheduler;
use crate::session_manager::SessionManager;
use crate::sounds::Sounds;
use crate::store::{Store, StoreError};

use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

pub const PROTOCOL_VERSION: &str = "2025-06-18";
pub const SUPPORTED_VERSIONS: &[&str] = &["2025-06-18", "2025-03-26"];

#[derive(Debug)]
pub struct RateLimiter {
    requests: Mutex<HashMap<IpAddr, Vec<Instant>>>,
    limit_per_minute: usize,
}

impl RateLimiter {
    pub fn new(limit_per_minute: usize) -> Self {
        Self {
            requests: Mutex::new(HashMap::new()),
            limit_per_minute,
        }
    }

    pub fn check_and_record(&self, ip: IpAddr) -> bool {
        let now = Instant::now();
        let window = Duration::from_secs(60);
        let mut map = self.requests.lock().unwrap();

        let timestamps = map.entry(ip).or_default();
        timestamps.retain(|&t| now.duration_since(t) < window);

        if timestamps.len() >= self.limit_per_minute {
            false
        } else {
            timestamps.push(now);
            true
        }
    }
}

pub struct McpHandler {
    store: Arc<Store>,
    sessions: Arc<SessionManager>,
    sounds: Arc<Sounds>,
    clock: Arc<Clock>,
    events: EventStream,
    scheduler: Arc<Scheduler>,
    rate_limiter: RateLimiter,
}

impl McpHandler {
    pub fn new(
        store: Arc<Store>,
        sessions: Arc<SessionManager>,
        sounds: Arc<Sounds>,
        clock: Arc<Clock>,
        events: EventStream,
        scheduler: Arc<Scheduler>,
    ) -> Self {
        Self {
            store,
            sessions,
            sounds,
            clock,
            events,
            scheduler,
            rate_limiter: RateLimiter::new(120),
        }
    }

    pub fn check_rate_limit(&self, ip: IpAddr) -> bool {
        self.rate_limiter.check_and_record(ip)
    }

    /// Process an MCP JSON-RPC message.
    pub async fn handle(
        &self,
        message: &Value,
        protocol_header: Option<&str>,
    ) -> (StatusCode, Value) {
        let msg_obj = match message.as_object() {
            Some(obj) => obj,
            None => {
                return (
                    StatusCode::BAD_REQUEST,
                    error_response(&Value::Null, -32600, "Invalid Request", None),
                );
            }
        };

        if msg_obj.get("jsonrpc").and_then(Value::as_str) != Some("2.0") {
            return (
                StatusCode::BAD_REQUEST,
                error_response(&Value::Null, -32600, "Invalid Request", None),
            );
        }

        let method = match msg_obj.get("method").and_then(Value::as_str) {
            Some(m) => m,
            None => {
                return (
                    StatusCode::BAD_REQUEST,
                    error_response(&Value::Null, -32600, "Invalid Request", None),
                );
            }
        };

        let id = match msg_obj.get("id") {
            Some(id) if id.is_string() || id.is_number() => id.clone(),
            Some(_) => {
                return (
                    StatusCode::BAD_REQUEST,
                    error_response(&Value::Null, -32600, "Invalid Request", None),
                );
            }
            None => {
                // Notification: must have valid protocol header if supplied
                if let Some(proto) = protocol_header {
                    if !SUPPORTED_VERSIONS.contains(&proto) {
                        return (
                            StatusCode::BAD_REQUEST,
                            error_response(
                                &Value::Null,
                                -32602,
                                "Unsupported protocol version",
                                Some(json!({ "supported": SUPPORTED_VERSIONS, "requested": proto })),
                            ),
                        );
                    }
                }
                return (StatusCode::ACCEPTED, json!({ "accepted": true }));
            }
        };

        if method == "initialize" {
            let requested = msg_obj
                .get("params")
                .and_then(|p| p.get("protocolVersion"))
                .and_then(Value::as_str);

            let negotiated = match requested {
                Some(ver) if SUPPORTED_VERSIONS.contains(&ver) => ver,
                Some(_) | None => PROTOCOL_VERSION,
            };

            let result = json!({
                "protocolVersion": negotiated,
                "capabilities": {
                    "tools": { "listChanged": false }
                },
                "serverInfo": {
                    "name": "robine-wake",
                    "title": "Robine Wake",
                    "version": env!("CARGO_PKG_VERSION")
                },
                "instructions": "Control the local Robine Wake alarm clock. Read current state before writes and preserve alarm revisions when updating or deleting."
            });

            return (StatusCode::OK, success_response(&id, result));
        }

        // Validate protocol header on non-initialize requests
        if let Some(proto) = protocol_header {
            if !SUPPORTED_VERSIONS.contains(&proto) {
                return (
                    StatusCode::BAD_REQUEST,
                    error_response(
                        &id,
                        -32602,
                        "Unsupported protocol version",
                        Some(json!({ "supported": SUPPORTED_VERSIONS, "requested": proto })),
                    ),
                );
            }
        }

        match method {
            "ping" => (StatusCode::OK, success_response(&id, json!({}))),

            "tools/list" => (
                StatusCode::OK,
                success_response(&id, json!({ "tools": tools() })),
            ),

            "tools/call" => {
                let params = msg_obj.get("params");
                let tool_name = params.and_then(|p| p.get("name")).and_then(Value::as_str);
                let arguments = params
                    .and_then(|p| p.get("arguments"))
                    .cloned()
                    .unwrap_or_else(|| json!({}));

                match tool_name {
                    Some(name) => {
                        let res = self.call_tool(name, &arguments).await;
                        (StatusCode::OK, success_response(&id, res))
                    }
                    None => (
                        StatusCode::OK,
                        error_response(&id, -32602, "Invalid tool call parameters", None),
                    ),
                }
            }

            _ => (
                StatusCode::OK,
                error_response(&id, -32601, "Method not found", None),
            ),
        }
    }

    async fn call_tool(&self, name: &str, args: &Value) -> Value {
        let now = Utc::now();

        match name {
            "get_state" => {
                let alarms: Vec<Value> = self
                    .store
                    .list()
                    .iter()
                    .map(|a| alarm_json(a, now))
                    .collect();
                tool_success(json!({
                    "clock": {
                        "now": now.to_rfc3339(),
                        "quality": self.clock.quality(),
                    },
                    "alarms": alarms,
                    "recent_sessions": self.store.raw("sessions"),
                    "active_session": self.sessions.active_snapshot(),
                    "smartphone_dismiss": {
                        "enabled": self.store.get_smartphone_dismiss_enabled(),
                    }
                }))
            }

            "list_alarms" => {
                let alarms: Vec<Value> = self
                    .store
                    .list()
                    .iter()
                    .map(|a| alarm_json(a, now))
                    .collect();
                tool_success(json!({ "alarms": alarms }))
            }

            "list_sounds" => tool_success(json!({ "sounds": self.sounds.list() })),

            "preview_alarm" => match Alarm::new(args, now) {
                Ok(alarm) => tool_success(json!({ "alarm": alarm_json(&alarm, now) })),
                Err(errors) => tool_error(json!({ "validation_failed": errors })),
            },

            "create_alarm" => match self.store.create(args, now) {
                Ok(alarm) => {
                    self.events.publish("state.changed", None);
                    self.scheduler.notify();
                    tool_success(json!({ "alarm": alarm_json(&alarm, now) }))
                }
                Err(e) => tool_store_error(e),
            },

            "update_alarm" => {
                let id = args.get("id").and_then(Value::as_str).unwrap_or("");
                if id.is_empty() {
                    return tool_error(json!("id and revision required"));
                }
                match self.store.update(id, args, now) {
                    Ok(alarm) => {
                        self.events.publish("state.changed", None);
                        self.scheduler.notify();
                        tool_success(json!({ "alarm": alarm_json(&alarm, now) }))
                    }
                    Err(e) => tool_store_error(e),
                }
            }

            "delete_alarm" => {
                let id = args.get("id").and_then(Value::as_str).unwrap_or("");
                let revision = args.get("revision");
                match self.store.delete(id, revision) {
                    Ok(()) => {
                        self.events.publish("state.changed", None);
                        self.scheduler.notify();
                        tool_success(json!({ "deleted": true, "id": id }))
                    }
                    Err(e) => tool_store_error(e),
                }
            }

            "trigger_alarm" => {
                let id = args.get("id").and_then(Value::as_str).unwrap_or("");
                let alarm = match self.store.list().into_iter().find(|a| a.id == id) {
                    Some(a) => a,
                    None => return tool_error(json!("alarm not found")),
                };

                match self.sessions.trigger_alarm(&alarm, now).await {
                    Ok(session) => tool_success(json!({ "session": session })),
                    Err(e) => tool_error(json!(e)),
                }
            }

            "snooze_session" => match self.sessions.snooze(now).await {
                Ok(session) => tool_success(json!({ "session": session })),
                Err(e) => tool_error(json!(e)),
            },

            "dismiss_session" => {
                match self
                    .sessions
                    .dismiss(robine_core::session::DismissSource::RemoteApi, now)
                    .await
                {
                    Ok(session) => tool_success(json!({ "session": session })),
                    Err(e) => tool_error(json!(e)),
                }
            }

            unknown => tool_error(json!(format!("unknown tool: {unknown}"))),
        }
    }
}

fn tool_success(data: Value) -> Value {
    let text = serde_json::to_string_pretty(&data).unwrap_or_default();
    json!({
        "content": [{ "type": "text", "text": text }],
        "structuredContent": data,
        "isError": false,
    })
}

fn tool_error(data: Value) -> Value {
    let text = serde_json::to_string_pretty(&data).unwrap_or_default();
    json!({
        "content": [{ "type": "text", "text": text }],
        "structuredContent": data,
        "isError": true,
    })
}

fn tool_store_error(error: StoreError) -> Value {
    match error {
        StoreError::NotFound => tool_error(json!({ "code": "not_found" })),
        StoreError::RevisionConflict => tool_error(json!({ "code": "revision_conflict" })),
        StoreError::AlreadyExists => tool_error(json!({ "code": "already_exists" })),
        StoreError::Invalid(errors) => tool_error(json!({ "code": "validation_failed", "details": errors })),
        StoreError::Io(reason) => tool_error(json!({ "code": "io_error", "details": reason })),
    }
}

fn success_response(id: &Value, result: Value) -> Value {
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "result": result
    })
}

fn error_response(id: &Value, code: i32, message: &str, data: Option<Value>) -> Value {
    let mut err = json!({
        "code": code,
        "message": message
    });
    if let Some(d) = data {
        err["data"] = d;
    }
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": err
    })
}

fn alarm_json(alarm: &Alarm, now: chrono::DateTime<Utc>) -> Value {
    let occurrences: Vec<Value> = if alarm.enabled {
        alarm
            .next_occurrences(5, now)
            .into_iter()
            .map(|dt| json!(dt.to_rfc3339()))
            .collect()
    } else {
        Vec::new()
    };
    let mut map = alarm.to_map();
    map.insert("next_occurrences".into(), Value::Array(occurrences));
    Value::Object(map)
}

/// Check if Origin header is allowed (API-003.3).
pub fn is_origin_allowed(origin: &str) -> bool {
    let origin = origin.trim();
    if origin.is_empty() || origin == "null" {
        return true;
    }

    let without_scheme = if let Some(rest) = origin.strip_prefix("http://") {
        rest
    } else if let Some(rest) = origin.strip_prefix("https://") {
        rest
    } else {
        return false;
    };

    let host_port = without_scheme.split('/').next().unwrap_or("");
    let host = if host_port.starts_with('[') {
        if let Some(end) = host_port.find(']') {
            &host_port[1..end]
        } else {
            return false;
        }
    } else {
        host_port.split(':').next().unwrap_or("")
    };

    host == "localhost"
        || host == "127.0.0.1"
        || host == "::1"
        || host == "robine-wake.local"
        || host.ends_with(".local")
}

pub fn tools() -> Vec<Value> {
    let alarm_properties = json!({
        "label": { "type": "string", "maxLength": 80 },
        "enabled": { "type": "boolean" },
        "local_time": { "type": "string", "description": "Local time as HH:MM" },
        "days_of_week": {
            "type": "array",
            "items": { "type": "integer", "minimum": 1, "maximum": 7 },
            "uniqueItems": true
        },
        "one_shot_date": {
            "type": ["string", "null"],
            "description": "Optional ISO 8601 date (YYYY-MM-DD)"
        },
        "timezone": { "type": "string", "description": "IANA time zone" },
        "sound_id": { "type": "string" },
        "strong_sound_id": { "type": "string" },
        "prewake_seconds": { "type": "integer", "minimum": 0, "maximum": 3600 },
        "volume_profile": {
            "type": "object",
            "properties": {
                "start": { "type": "integer", "minimum": 0 },
                "ceiling": { "type": "integer", "minimum": 0 },
                "strong": { "type": "integer", "minimum": 0 },
                "ramp_seconds": { "type": "integer", "minimum": 0, "maximum": 3600 }
            }
        },
        "snooze": {
            "type": "object",
            "properties": {
                "enabled": { "type": "boolean" },
                "duration_seconds": { "type": "integer", "minimum": 60, "maximum": 1800 },
                "maximum": { "type": "integer", "minimum": 0, "maximum": 10 }
            }
        }
    });

    let read_only_hint = json!({
        "readOnlyHint": true,
        "destructiveHint": false,
        "idempotentHint": true,
        "openWorldHint": false
    });

    let write_hint = json!({
        "readOnlyHint": false,
        "destructiveHint": false,
        "idempotentHint": false,
        "openWorldHint": false
    });

    let delete_hint = json!({
        "readOnlyHint": false,
        "destructiveHint": true,
        "idempotentHint": false,
        "openWorldHint": false
    });

    vec![
        json!({
            "name": "get_state",
            "title": "Get Device State",
            "description": "Read device health, alarms, recent sessions, and active wake session.",
            "inputSchema": { "type": "object", "properties": {}, "additionalProperties": false },
            "annotations": read_only_hint
        }),
        json!({
            "name": "list_alarms",
            "title": "List Alarms",
            "description": "List configured alarms and their next occurrences.",
            "inputSchema": { "type": "object", "properties": {}, "additionalProperties": false },
            "annotations": read_only_hint
        }),
        json!({
            "name": "list_sounds",
            "title": "List Sounds",
            "description": "List validated sounds available on this device.",
            "inputSchema": { "type": "object", "properties": {}, "additionalProperties": false },
            "annotations": read_only_hint
        }),
        json!({
            "name": "preview_alarm",
            "title": "Preview Alarm",
            "description": "Validate an alarm without saving it and compute its next occurrences.",
            "inputSchema": {
                "type": "object",
                "properties": alarm_properties,
                "required": ["local_time"]
            },
            "annotations": read_only_hint
        }),
        json!({
            "name": "create_alarm",
            "title": "Create Alarm",
            "description": "Create and persist an alarm.",
            "inputSchema": {
                "type": "object",
                "properties": alarm_properties,
                "required": ["local_time"]
            },
            "annotations": write_hint
        }),
        json!({
            "name": "update_alarm",
            "title": "Update Alarm",
            "description": "Update an alarm using its current revision for conflict protection.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "id": { "type": "string" },
                    "revision": { "type": "integer", "minimum": 1 }
                },
                "required": ["id", "revision"]
            },
            "annotations": write_hint
        }),
        json!({
            "name": "delete_alarm",
            "title": "Delete Alarm",
            "description": "Permanently delete an alarm using its current revision.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "id": { "type": "string" },
                    "revision": { "type": "integer", "minimum": 1 }
                },
                "required": ["id", "revision"]
            },
            "annotations": delete_hint
        }),
        json!({
            "name": "trigger_alarm",
            "title": "Trigger Alarm",
            "description": "Start a configured alarm immediately.",
            "inputSchema": {
                "type": "object",
                "properties": { "id": { "type": "string" } },
                "required": ["id"]
            },
            "annotations": write_hint
        }),
        json!({
            "name": "snooze_session",
            "title": "Snooze Session",
            "description": "Snooze the active wake session.",
            "inputSchema": { "type": "object", "properties": {}, "additionalProperties": false },
            "annotations": write_hint
        }),
        json!({
            "name": "dismiss_session",
            "title": "Dismiss Session",
            "description": "Stop and dismiss the active wake session.",
            "inputSchema": { "type": "object", "properties": {}, "additionalProperties": false },
            "annotations": write_hint
        }),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audio::AudioSink;

    fn setup() -> McpHandler {
        let temp = std::env::temp_dir().join(format!("mcp-test-{}", uuid::Uuid::new_v4()));
        let store = Arc::new(Store::open(temp.join("db.json"), |_| true));
        let audio = Arc::new(AudioSink::new());
        let events = EventStream::new();
        let sessions = Arc::new(SessionManager::new(audio, store.clone(), events.clone()));
        let sounds = Arc::new(Sounds::open(temp.join("sounds")));
        let clock = Arc::new(Clock::new());
        let scheduler = Arc::new(Scheduler::new(
            store.clone(),
            clock.clone(),
            sessions.clone(),
            events.clone(),
        ));

        McpHandler::new(store, sessions, sounds, clock, events, scheduler)
    }

    #[tokio::test]
    async fn handles_initialize_and_negotiates_protocol() {
        let handler = setup();

        let req = json!({
            "jsonrpc": "2.0",
            "id": "req-1",
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18"
            }
        });

        let (status, resp) = handler.handle(&req, None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(resp["result"]["protocolVersion"], "2025-06-18");
        assert_eq!(resp["result"]["serverInfo"]["name"], "robine-wake");
    }

    #[tokio::test]
    async fn tools_list_and_call_crud() {
        let handler = setup();

        // 1. tools/list
        let list_req = json!({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list"
        });
        let (status, list_resp) = handler.handle(&list_req, None).await;
        assert_eq!(status, StatusCode::OK);
        let tools = list_resp["result"]["tools"].as_array().unwrap();
        assert!(tools.iter().any(|t| t["name"] == "create_alarm"));

        // 2. tools/call create_alarm
        let create_req = json!({
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "create_alarm",
                "arguments": {
                    "label": "Work",
                    "local_time": "08:15",
                    "days_of_week": [1, 2, 3, 4, 5]
                }
            }
        });
        let (status, create_resp) = handler.handle(&create_req, None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(create_resp["result"]["isError"], false);
        let created_alarm = &create_resp["result"]["structuredContent"]["alarm"];
        assert_eq!(created_alarm["label"], "Work");
        let alarm_id = created_alarm["id"].as_str().unwrap();

        // 3. tools/call get_state
        let state_req = json!({
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": { "name": "get_state" }
        });
        let (status, state_resp) = handler.handle(&state_req, None).await;
        assert_eq!(status, StatusCode::OK);
        let alarms = state_resp["result"]["structuredContent"]["alarms"]
            .as_array()
            .unwrap();
        assert!(alarms.iter().any(|a| a["id"] == alarm_id));
    }

    #[test]
    fn origin_validation_rules() {
        assert!(is_origin_allowed(""));
        assert!(is_origin_allowed("null"));
        assert!(is_origin_allowed("http://localhost:4000"));
        assert!(is_origin_allowed("http://127.0.0.1:4000"));
        assert!(is_origin_allowed("http://robine-wake.local:4000"));
        assert!(is_origin_allowed("http://bedroom.local"));
        assert!(!is_origin_allowed("https://malicious-website.com"));
    }
}
