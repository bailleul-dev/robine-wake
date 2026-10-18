//! HTTP surface: the alarm subset of `RobineWakeWeb.Router`, same paths, same
//! JSON envelopes, same status codes.

use std::convert::Infallible;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::sse::{Event as SseEvent, KeepAlive, Sse};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::Utc;
use futures::stream::{self, Stream, StreamExt};
use serde_json::{json, Map, Value};
use sha2::Digest;
use tokio_stream::wrappers::BroadcastStream;
use tower_http::services::{ServeDir, ServeFile};

use crate::alarm::Alarm;
use crate::audio::AudioSink;
use crate::clock::Clock;
use crate::command::{CommandEnvelope, CommandHandler, CommandResponse};
use crate::events::EventStream;
use crate::scheduler::Scheduler;
use crate::session_manager::SessionManager;
use crate::sounds::Sounds;
use crate::store::{Store, StoreError};

pub const VERSION: &str = env!("CARGO_PKG_VERSION");
pub const TARGET: &str = "host-rs-experimental";

pub struct App {
    pub store: Arc<Store>,
    pub events: EventStream,
    pub sounds: Arc<Sounds>,
    pub clock: Arc<Clock>,
    #[allow(dead_code)]
    pub audio: Arc<AudioSink>,
    pub sessions: Arc<SessionManager>,
    pub commands: Arc<CommandHandler>,
    pub scheduler: Arc<Scheduler>,
    pub mcp: Arc<crate::mcp::McpHandler>,
    pub web_dir: PathBuf,
    pub started: Instant,
}

type Shared = Arc<App>;

pub fn router(app: Shared) -> Router {
    let index = app.web_dir.join("index.html");
    let web = ServeDir::new(&app.web_dir).fallback(ServeFile::new(index));

    Router::new()
        .route("/health", get(health))
        .route("/api/state", get(state))
        .route("/api/time/confirm", post(confirm_time))
        .route("/api/v1/command", post(command))
        .route("/api/alarms", get(list_alarms).post(create_alarm))
        .route("/api/alarms/preview", post(preview_alarm))
        .route(
            "/api/alarms/{id}",
            axum::routing::patch(update_alarm).delete(delete_alarm),
        )
        .route("/api/alarms/{id}/trigger", post(trigger_alarm))
        .route(
            "/api/alarms/{id}/trigger-strong",
            post(trigger_strong_alarm),
        )
        .route("/api/session/snooze", post(snooze_session))
        .route("/api/session/dismiss", post(dismiss_session))
        .route(
            "/api/settings/smartphone-dismiss",
            axum::routing::patch(set_smartphone_dismiss),
        )
        .route("/api/history", axum::routing::delete(clear_history))
        .route("/api/factory-reset", post(factory_reset))
        .route("/api/nap/start", post(start_nap))
        .route("/api/nap/cancel", post(cancel_nap))
        .route("/api/sounds", get(sounds).post(upload_sound))
        .route("/api/export", get(export_configuration))
        .route("/api/diagnostics", get(diagnostics))
        .route("/api/v1/events", get(events))
        .route("/api/breathing/start", post(breathing_unavailable))
        .route("/api/breathing/volume", post(breathing_unavailable))
        .route("/api/breathing/stop", post(breathing_unavailable))
        .route("/mcp", post(mcp_post).get(mcp_get_not_allowed))
        .fallback_service(web)
        .with_state(app)
}

async fn health(State(app): State<Shared>) -> Json<Value> {
    Json(health_snapshot(&app))
}

async fn confirm_time(State(app): State<Shared>) -> Json<Value> {
    app.clock.confirm();
    app.scheduler.notify();
    let now = Utc::now();
    Json(json!({
        "status": "ok",
        "clock": {
            "now": now.to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
            "quality": app.clock.quality(),
        }
    }))
}

async fn command(
    State(app): State<Shared>,
    Json(envelope): Json<CommandEnvelope>,
) -> Json<CommandResponse> {
    Json(app.commands.handle(envelope).await)
}

async fn trigger_alarm(State(app): State<Shared>, Path(id): Path<String>) -> Response {
    let now = Utc::now();
    let alarm = match app.store.list().into_iter().find(|a| a.id == id) {
        Some(a) => a,
        None => return api_error(StoreError::NotFound),
    };

    match app.sessions.trigger_alarm(&alarm, now).await {
        Ok(session) => (
            StatusCode::OK,
            Json(json!({ "status": "ok", "data": session })),
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "error": { "code": "trigger_failed", "details": e } })),
        )
            .into_response(),
    }
}

async fn trigger_strong_alarm(State(app): State<Shared>, Path(id): Path<String>) -> Response {
    let now = Utc::now();
    let alarm = match app.store.list().into_iter().find(|a| a.id == id) {
        Some(a) => a,
        None => return api_error(StoreError::NotFound),
    };

    match app.sessions.trigger_alarm(&alarm, now).await {
        Ok(_) => {
            let escalate_time = now + chrono::Duration::seconds(305);
            app.sessions.tick(escalate_time).await;
            let snapshot = app.sessions.active_snapshot().unwrap_or(Value::Null);
            (
                StatusCode::OK,
                Json(json!({ "status": "ok", "data": snapshot })),
            )
                .into_response()
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "error": { "code": "trigger_failed", "details": e } })),
        )
            .into_response(),
    }
}

async fn snooze_session(State(app): State<Shared>) -> Response {
    let now = Utc::now();
    match app.sessions.snooze(now).await {
        Ok(session) => (StatusCode::OK, Json(json!({ "status": "ok", "data": session }))).into_response(),
        Err(e) if e == "max_snoozes_reached" => (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(json!({ "error": { "code": "max_snoozes_reached", "details": "max_snoozes_reached" } })),
        ).into_response(),
        Err(e) if e == "no_active_session" => (
            StatusCode::NOT_FOUND,
            Json(json!({ "error": { "code": "no_active_session", "details": "no_active_session" } })),
        ).into_response(),
        Err(e) => (
            StatusCode::BAD_REQUEST,
            Json(json!({ "error": { "code": "snooze_failed", "details": e } })),
        ).into_response(),
    }
}

async fn dismiss_session(State(app): State<Shared>) -> Response {
    let now = Utc::now();
    match app.sessions.dismiss(robine_core::session::DismissSource::RemoteApi, now).await {
        Ok(session) => (StatusCode::OK, Json(json!({ "status": "ok", "data": session }))).into_response(),
        Err(e) if e == "smartphone_dismiss_disabled" => (
            StatusCode::FORBIDDEN,
            Json(json!({ "error": { "code": "smartphone_dismiss_disabled", "details": "smartphone_dismiss_disabled" } })),
        ).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "error": { "code": "dismiss_failed", "details": e } })),
        ).into_response(),
    }
}

async fn set_smartphone_dismiss(State(app): State<Shared>, Json(body): Json<Value>) -> Response {
    let enabled = body
        .get("enabled")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    match app.store.set_smartphone_dismiss_enabled(enabled) {
        Ok(()) => {
            app.events.publish("state.changed", None);
            (
                StatusCode::OK,
                Json(json!({ "status": "ok", "enabled": enabled })),
            )
                .into_response()
        }
        Err(e) => api_error(e),
    }
}

async fn clear_history(State(app): State<Shared>) -> Response {
    match app.store.clear_history() {
        Ok(()) => {
            app.events.publish("state.changed", None);
            (
                StatusCode::OK,
                Json(json!({ "status": "ok", "history_erased": true })),
            )
                .into_response()
        }
        Err(e) => api_error(e),
    }
}

async fn start_nap(State(app): State<Shared>, Json(body): Json<Value>) -> Response {
    let now = Utc::now();
    let minutes = body
        .get("duration_minutes")
        .or_else(|| body.get("minutes"))
        .and_then(Value::as_u64)
        .unwrap_or(0) as u32;

    match app.store.start_nap(minutes, now) {
        Ok(alarm) => {
            app.events.publish("state.changed", None);
            app.scheduler.notify();
            (
                StatusCode::OK,
                Json(json!({ "status": "ok", "data": alarm_json(&alarm, now) })),
            )
                .into_response()
        }
        Err(e) => api_error(e),
    }
}

async fn cancel_nap(State(app): State<Shared>) -> Response {
    match app.store.cancel_nap() {
        Ok(()) => {
            app.events.publish("state.changed", None);
            app.scheduler.notify();
            (
                StatusCode::OK,
                Json(json!({ "status": "ok", "cancelled": true })),
            )
                .into_response()
        }
        Err(e) => api_error(e),
    }
}

async fn factory_reset(State(app): State<Shared>, Json(body): Json<Value>) -> Response {
    let confirmation = body
        .get("confirmation")
        .and_then(Value::as_str)
        .unwrap_or("");
    if confirmation != "RESET" {
        return (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(json!({
                "error": {
                    "code": "invalid_confirmation",
                    "details": "confirmation must be RESET"
                }
            })),
        )
            .into_response();
    }

    match app.store.factory_reset() {
        Ok(()) => {
            app.events.publish("state.changed", None);
            app.scheduler.notify();
            (
                StatusCode::OK,
                Json(json!({ "state": "factory_reset", "next": "/" })),
            )
                .into_response()
        }
        Err(e) => api_error(e),
    }
}

async fn upload_sound(State(app): State<Shared>, Json(body): Json<Value>) -> Response {
    let id = body.get("id").and_then(Value::as_str).unwrap_or("");
    let data_base64 = body
        .get("data_base64")
        .and_then(Value::as_str)
        .unwrap_or("");
    let sha256 = body.get("sha256").and_then(Value::as_str).unwrap_or("");

    match app.sounds.import_base64(id, data_base64, sha256) {
        Ok(metadata) => (StatusCode::CREATED, Json(json!({ "data": metadata }))).into_response(),
        Err(e) => (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(json!({ "error": { "code": e.code(), "details": e.code() } })),
        )
            .into_response(),
    }
}

async fn export_configuration(State(app): State<Shared>) -> Response {
    let payload = app.store.export_configuration();
    let json_string = serde_json::to_string_pretty(&payload).unwrap_or_default();
    (
        [
            (header::CONTENT_TYPE, "application/json"),
            (
                header::CONTENT_DISPOSITION,
                "attachment; filename=\"robine-wake-configuration.json\"",
            ),
        ],
        json_string,
    )
        .into_response()
}

async fn diagnostics(State(app): State<Shared>) -> Response {
    let now = Utc::now();
    let config = app.store.export_configuration();
    let health = health_snapshot(&app);
    let recent_sessions = app.store.raw("sessions");

    let files = json!({
        "configuration.json": config,
        "health.json": health,
        "recent_sessions.json": recent_sessions,
    });

    let files_obj = files.as_object().unwrap();
    let mut manifest = Vec::new();
    for (name, val) in files_obj {
        let encoded = serde_json::to_vec(val).unwrap_or_default();
        let mut hasher = sha2::Sha256::new();
        hasher.update(&encoded);
        let digest = hex::encode(hasher.finalize());
        manifest.push(json!({
            "name": name,
            "bytes": encoded.len(),
            "sha256": digest,
        }));
    }
    manifest.sort_by_key(|m| m["name"].as_str().unwrap_or("").to_string());

    let payload = json!({
        "format": "robine-wake-diagnostics",
        "format_version": 1,
        "generated_at": now.to_rfc3339(),
        "manifest": manifest,
        "files": files,
    });

    let json_string = serde_json::to_string_pretty(&payload).unwrap_or_default();
    (
        [
            (header::CONTENT_TYPE, "application/json"),
            (
                header::CONTENT_DISPOSITION,
                "attachment; filename=\"robine-wake-diagnostics.json\"",
            ),
        ],
        json_string,
    )
        .into_response()
}

async fn breathing_unavailable() -> Response {
    (
        StatusCode::SERVICE_UNAVAILABLE,
        Json(json!({
            "error": {
                "code": "capability_unavailable",
                "details": "breathing feature removed from v2 scope"
            }
        })),
    )
        .into_response()
}

async fn state(State(app): State<Shared>) -> Json<Value> {
    let now = Utc::now();
    Json(json!({
        "health": health_snapshot(&app),
        "clock": {
            "now": now.to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
            "quality": app.clock.quality(),
        },
        "alarms": app.store.list().iter().map(|alarm| alarm_json(alarm, now)).collect::<Vec<_>>(),
        "sessions": app.store.raw("sessions"),
        "active_session": app.sessions.active_snapshot(),
        "smartphone_dismiss": {
            "enabled": app.store.get_smartphone_dismiss_enabled(),
            "locked": false,
        },
        "hue": { "state": "unavailable", "breathing": { "active": false } },
        "hue_targets": [],
        "remote_button": { "state": "available" },
        "lora": { "state": "not_implemented" },
    }))
}

async fn list_alarms(State(app): State<Shared>) -> Json<Value> {
    let now = Utc::now();
    let alarms: Vec<Value> = app
        .store
        .list()
        .iter()
        .map(|alarm| alarm_json(alarm, now))
        .collect();
    Json(json!({ "data": alarms }))
}

async fn preview_alarm(Json(body): Json<Value>) -> Response {
    let now = Utc::now();
    match Alarm::new(&body, now) {
        Ok(alarm) => (
            StatusCode::OK,
            Json(json!({ "data": alarm_json(&alarm, now) })),
        )
            .into_response(),
        Err(errors) => api_error(StoreError::Invalid(errors)),
    }
}

async fn create_alarm(State(app): State<Shared>, Json(body): Json<Value>) -> Response {
    let now = Utc::now();
    match app.store.create(&body, now) {
        Ok(alarm) => {
            app.events.publish("state.changed", None);
            app.scheduler.notify();
            (
                StatusCode::CREATED,
                Json(json!({ "data": alarm_json(&alarm, now) })),
            )
                .into_response()
        }
        Err(error) => api_error(error),
    }
}

async fn update_alarm(
    State(app): State<Shared>,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> Response {
    let now = Utc::now();
    match app.store.update(&id, &body, now) {
        Ok(alarm) => {
            app.events.publish("state.changed", None);
            app.scheduler.notify();
            (
                StatusCode::OK,
                Json(json!({ "data": alarm_json(&alarm, now) })),
            )
                .into_response()
        }
        Err(error) => api_error(error),
    }
}

async fn delete_alarm(
    State(app): State<Shared>,
    Path(id): Path<String>,
    body: Option<Json<Value>>,
) -> Response {
    let revision = body
        .as_ref()
        .and_then(|Json(body)| body.get("revision").cloned());
    match app.store.delete(&id, revision.as_ref()) {
        Ok(()) => {
            app.events.publish("state.changed", None);
            app.scheduler.notify();
            StatusCode::NO_CONTENT.into_response()
        }
        Err(error) => api_error(error),
    }
}

async fn sounds(State(app): State<Shared>) -> Json<Value> {
    Json(json!({ "data": app.sounds.list() }))
}

async fn events(State(app): State<Shared>, headers: HeaderMap) -> impl IntoResponse {
    let last_event_id = headers
        .get("last-event-id")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.trim().parse::<u64>().ok());
    let subscription = app.events.subscribe(last_event_id);

    let ready = SseEvent::default().id(subscription.sequence.to_string()).event("ready").data(
        json!({ "v": 1, "id": subscription.sequence, "event": "ready", "at": null, "data": null }).to_string(),
    );
    let replay = subscription.replay.into_iter().map(sse_event);
    let live = BroadcastStream::new(subscription.receiver).filter_map(|received| async move {
        // A lagging client simply loses events; it can replay them with Last-Event-ID.
        received.ok().map(sse_event)
    });

    let body: std::pin::Pin<Box<dyn Stream<Item = Result<SseEvent, Infallible>> + Send>> = Box::pin(
        stream::once(async { ready })
            .chain(stream::iter(replay))
            .chain(live)
            .map(Ok),
    );

    (
        [(header::CACHE_CONTROL, "no-cache, no-transform")],
        Sse::new(body).keep_alive(KeepAlive::default()),
    )
}

fn sse_event(event: crate::events::Event) -> SseEvent {
    let data =
        json!({ "v": 1, "id": event.id, "event": event.event, "at": event.at, "data": event.data });
    SseEvent::default()
        .id(event.id.to_string())
        .event(event.event)
        .data(data.to_string())
}

/// `alarm_json/1`: the persisted map plus the next five occurrences.
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

fn health_snapshot(app: &App) -> Value {
    let now = Utc::now();
    let clock_quality = app.clock.quality();
    let next = app
        .scheduler
        .next_occurrence(now)
        .map(|(at, alarm_id)| json!({ "alarm_id": alarm_id, "at": at.to_rfc3339_opts(chrono::SecondsFormat::Secs, true) }));
    let degraded = app.store.degraded();

    json!({
        "state": if degraded.is_some() { "degraded" } else { "available" },
        "version": VERSION,
        "target": TARGET,
        "now": now.to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
        "clock": {
            "now": now.to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
            "quality": clock_quality,
        },
        "uptime_ms": app.started.elapsed().as_millis() as u64,
        "storage": { "state": if degraded.is_some() { "degraded" } else { "available" }, "reason": degraded },
        "scheduler": {
            "state": "running",
            "next": next,
            "armed": app.scheduler.is_armed(),
        },
        "active_session": app.sessions.active_snapshot(),
        "experimental": {
            "note": "Robine Wake 2 - Phase 2 Autonomous Alarm Clock",
            "not_implemented": ["hue", "airplay", "bluetooth_audio", "lora", "mcp", "auth", "firmware"]
        }
    })
}

/// `api_error/2`: `{error: {code, details}}` with the Elixir status mapping.
fn api_error(error: StoreError) -> Response {
    let (status, code, details) = match error {
        StoreError::NotFound => (StatusCode::NOT_FOUND, "not_found", json!("not_found")),
        StoreError::RevisionConflict => (
            StatusCode::CONFLICT,
            "revision_conflict",
            json!("revision_conflict"),
        ),
        StoreError::AlreadyExists => (
            StatusCode::CONFLICT,
            "already_exists",
            json!("already_exists"),
        ),
        StoreError::Invalid(errors) => {
            let details: Map<String, Value> =
                errors.into_iter().map(|(k, v)| (k, json!(v))).collect();
            (
                StatusCode::UNPROCESSABLE_ENTITY,
                "validation_failed",
                Value::Object(details),
            )
        }
        StoreError::Io(reason) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            "internal_error",
            json!(reason),
        ),
    };
    (
        status,
        Json(json!({ "error": { "code": code, "details": details } })),
    )
        .into_response()
}

async fn mcp_post(
    State(app): State<Shared>,
    headers: HeaderMap,
    body: Result<Json<Value>, axum::extract::rejection::JsonRejection>,
) -> impl IntoResponse {
    if let Some(origin) = headers.get(header::ORIGIN).and_then(|v| v.to_str().ok()) {
        if !crate::mcp::is_origin_allowed(origin) {
            return (
                StatusCode::FORBIDDEN,
                [(header::CONTENT_TYPE, "application/json")],
                Json(json!({
                    "jsonrpc": "2.0",
                    "id": Value::Null,
                    "error": {
                        "code": -32000,
                        "message": "Origin not allowed"
                    }
                })),
            )
                .into_response();
        }
    }

    let client_ip = extract_client_ip(&headers);
    if !app.mcp.check_rate_limit(client_ip) {
        return (
            StatusCode::TOO_MANY_REQUESTS,
            [(header::CONTENT_TYPE, "application/json")],
            Json(json!({
                "jsonrpc": "2.0",
                "id": Value::Null,
                "error": {
                    "code": -32000,
                    "message": "Rate limit exceeded (120 req/min)"
                }
            })),
        )
            .into_response();
    }

    let body = match body {
        Ok(Json(v)) => v,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                [(header::CONTENT_TYPE, "application/json")],
                Json(json!({
                    "jsonrpc": "2.0",
                    "id": Value::Null,
                    "error": {
                        "code": -32700,
                        "message": "Parse error: invalid JSON"
                    }
                })),
            )
                .into_response();
        }
    };

    let protocol_header = headers
        .get("mcp-protocol-version")
        .and_then(|v| v.to_str().ok());

    let (status, resp) = app.mcp.handle(&body, protocol_header).await;
    (status, [(header::CONTENT_TYPE, "application/json")], Json(resp)).into_response()
}

async fn mcp_get_not_allowed() -> impl IntoResponse {
    (
        StatusCode::METHOD_NOT_ALLOWED,
        [
            (header::ALLOW, "POST"),
            (header::CONTENT_TYPE, "application/json"),
        ],
        Json(json!({
            "jsonrpc": "2.0",
            "id": Value::Null,
            "error": {
                "code": -32601,
                "message": "Method Not Allowed. Use POST /mcp"
            }
        })),
    )
}

fn extract_client_ip(headers: &HeaderMap) -> std::net::IpAddr {
    if let Some(forwarded) = headers.get("x-forwarded-for").and_then(|v| v.to_str().ok()) {
        if let Some(first) = forwarded.split(',').next() {
            if let Ok(ip) = first.trim().parse() {
                return ip;
            }
        }
    }
    std::net::IpAddr::V4(std::net::Ipv4Addr::LOCALHOST)
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request;
    use http_body_util::BodyExt;
    use tower::ServiceExt;

    fn app() -> Router {
        let scratch =
            std::env::temp_dir().join(format!("robine-wake-rs-tests-{}", uuid::Uuid::new_v4()));
        let data = scratch.join("db.json");
        let web = scratch.join("no-web");
        let sounds = Arc::new(Sounds::open(scratch.join("no-sounds")));
        let store = Arc::new(Store::open(data, |id| {
            id == "default" || id == "jungle_sunrise"
        }));
        let clock = Arc::new(Clock::new());
        let audio = Arc::new(AudioSink::new());
        let events = EventStream::new();
        let sessions = Arc::new(SessionManager::new(
            audio.clone(),
            store.clone(),
            events.clone(),
        ));
        let commands = Arc::new(CommandHandler::new(
            store.clone(),
            sessions.clone(),
            clock.clone(),
            sounds.clone(),
            audio.clone(),
            events.clone(),
        ));
        let scheduler = Arc::new(Scheduler::new(
            store.clone(),
            clock.clone(),
            sessions.clone(),
            events.clone(),
        ));
        let mcp = Arc::new(crate::mcp::McpHandler::new(
            store.clone(),
            sessions.clone(),
            sounds.clone(),
            clock.clone(),
            events.clone(),
            scheduler.clone(),
        ));

        let app = Arc::new(App {
            store,
            events,
            sounds,
            clock,
            audio,
            sessions,
            commands,
            scheduler,
            mcp,
            web_dir: web,
            started: Instant::now(),
        });
        router(app)
    }

    async fn call(
        router: &Router,
        method: &str,
        path: &str,
        body: Option<Value>,
    ) -> (StatusCode, Value) {
        let request = Request::builder()
            .method(method)
            .uri(path)
            .header(header::CONTENT_TYPE, "application/json")
            .body(body.map_or(Body::empty(), |body| Body::from(body.to_string())))
            .unwrap();
        let response = router.clone().oneshot(request).await.unwrap();
        let status = response.status();
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        let value = if bytes.is_empty() {
            Value::Null
        } else {
            serde_json::from_slice(&bytes).unwrap()
        };
        (status, value)
    }

    #[tokio::test]
    async fn alarm_crud_follows_the_elixir_contract() {
        let router = app();

        let (status, health) = call(&router, "GET", "/health", None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(health["state"], json!("available"));
        assert_eq!(health["target"], json!(TARGET));

        let (status, created) = call(
            &router,
            "POST",
            "/api/alarms",
            Some(json!({ "label": "Semaine", "local_time": "06:50", "days_of_week": ["monday", 3], "sound_id": "jungle_sunrise" })),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{created}");
        let alarm = &created["data"];
        assert_eq!(alarm["days_of_week"], json!([1, 3]));
        assert_eq!(alarm["next_occurrences"].as_array().unwrap().len(), 5);
        let id = alarm["id"].as_str().unwrap().to_string();

        let (status, rejected) = call(
            &router,
            "POST",
            "/api/alarms",
            Some(json!({ "sound_id": "nope" })),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
        assert_eq!(rejected["error"]["code"], json!("validation_failed"));
        assert!(rejected["error"]["details"]["sound_id"].is_string());

        let (status, conflict) = call(
            &router,
            "PATCH",
            &format!("/api/alarms/{id}"),
            Some(json!({ "label": "X", "revision": 9 })),
        )
        .await;
        assert_eq!(status, StatusCode::CONFLICT);
        assert_eq!(conflict["error"]["code"], json!("revision_conflict"));

        let (status, updated) = call(
            &router,
            "PATCH",
            &format!("/api/alarms/{id}"),
            Some(json!({ "enabled": false, "revision": 1 })),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(updated["data"]["revision"], json!(2));
        assert_eq!(updated["data"]["next_occurrences"], json!([]));

        let (status, listed) = call(&router, "GET", "/api/alarms", None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(listed["data"].as_array().unwrap().len(), 1);

        let (status, _) = call(
            &router,
            "DELETE",
            &format!("/api/alarms/{id}"),
            Some(json!({ "revision": 2 })),
        )
        .await;
        assert_eq!(status, StatusCode::NO_CONTENT);

        let (status, missing) = call(
            &router,
            "DELETE",
            &format!("/api/alarms/{id}"),
            Some(json!({ "revision": 2 })),
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND);
        assert_eq!(missing["error"]["code"], json!("not_found"));

        let (status, preview) = call(
            &router,
            "POST",
            "/api/alarms/preview",
            Some(json!({ "local_time": "08:15" })),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(preview["data"]["local_time"], json!("08:15:00"));
        let (status, _) = call(&router, "GET", "/api/alarms", None).await;
        assert_eq!(status, StatusCode::OK);
    }

    #[tokio::test]
    async fn the_event_stream_starts_with_ready_and_replays_history() {
        let router = app();
        call(
            &router,
            "POST",
            "/api/alarms",
            Some(json!({ "label": "A" })),
        )
        .await;
        call(
            &router,
            "POST",
            "/api/alarms",
            Some(json!({ "label": "B" })),
        )
        .await;

        let request = Request::builder()
            .uri("/api/v1/events")
            .header("last-event-id", "1")
            .body(Body::empty())
            .unwrap();
        let response = router.clone().oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(
            response.headers()[header::CONTENT_TYPE],
            "text/event-stream"
        );
        assert_eq!(
            response.headers()[header::CACHE_CONTROL],
            "no-cache, no-transform"
        );

        let mut body = response.into_body().into_data_stream();
        let mut received = String::new();
        while !received.contains("id: 2\nevent: state.changed") {
            let chunk = body.next().await.expect("stream stays open").unwrap();
            received.push_str(std::str::from_utf8(&chunk).unwrap());
        }
        assert!(received.starts_with("id: 2\nevent: ready\ndata: {\"at\":null,\"data\":null,\"event\":\"ready\",\"id\":2,\"v\":1}\n\n"), "{received}");
        assert!(
            !received.contains("id: 1\nevent: state.changed"),
            "event 1 was already seen"
        );
    }

    #[tokio::test]
    async fn clock_confirmation_and_health_exposure() {
        let router = app();

        let (status, health) = call(&router, "GET", "/health", None).await;
        assert_eq!(status, StatusCode::OK);
        assert!(health.get("clock").is_some());

        let (status, confirm) = call(&router, "POST", "/api/time/confirm", None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(confirm["status"], json!("ok"));
        assert_eq!(confirm["clock"]["quality"], json!("trusted"));

        let (status, state) = call(&router, "GET", "/api/state", None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(state["clock"]["quality"], json!("trusted"));
        assert_eq!(state["health"]["clock"]["quality"], json!("trusted"));
    }

    #[tokio::test]
    async fn handles_v1_command_envelopes() {
        let router = app();

        // 1. capabilities.get
        let env = json!({
            "v": 1,
            "id": "cmd-test-1",
            "op": "capabilities.get",
            "body": {}
        });
        let (status, resp) = call(&router, "POST", "/api/v1/command", Some(env.clone())).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(resp["v"], 1);
        assert_eq!(resp["id"], "cmd-test-1");
        assert_eq!(resp["status"], "ok");
        assert_eq!(resp["body"]["remote_button"], true);

        // 2. Replay with same ID -> exact same cached response (API-002.2)
        let (status, replay) = call(&router, "POST", "/api/v1/command", Some(env)).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(replay["id"], "cmd-test-1");
        assert_eq!(replay["status"], "ok");

        // 3. state.get
        let state_env = json!({
            "v": 1,
            "id": "cmd-test-2",
            "op": "state.get",
            "body": {}
        });
        let (status, state_resp) = call(&router, "POST", "/api/v1/command", Some(state_env)).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(state_resp["status"], "ok");
        assert!(state_resp["body"]["alarms"].is_array());
    }

    #[tokio::test]
    async fn triggers_snoozes_and_enforces_remote_dismiss_gate() {
        let router = app();

        // 1. Create alarm
        let (status, created) = call(
            &router,
            "POST",
            "/api/alarms",
            Some(json!({
                "label": "Matin",
                "local_time": "07:30",
                "days_of_week": [1, 2, 3, 4, 5],
                "sound_id": "jungle_sunrise"
            })),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED);
        let id = created["data"]["id"].as_str().unwrap();

        // 2. Trigger alarm session
        let (status, triggered) =
            call(&router, "POST", &format!("/api/alarms/{id}/trigger"), None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(triggered["status"], json!("ok"));
        assert_eq!(triggered["data"]["status"], json!("ringing"));

        // 3. Verify health and state reflect active session
        let (status, health) = call(&router, "GET", "/health", None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(health["active_session"]["status"], json!("ringing"));

        // 4. Try remote dismiss while smartphone_dismiss is disabled (ALM-002.7)
        let (status, dismiss_err) = call(&router, "POST", "/api/session/dismiss", None).await;
        assert_eq!(status, StatusCode::FORBIDDEN);
        assert_eq!(
            dismiss_err["error"]["code"],
            json!("smartphone_dismiss_disabled")
        );

        // 5. Snooze session
        let (status, snoozed) = call(&router, "POST", "/api/session/snooze", None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(snoozed["data"]["status"], json!("snoozed"));
        assert_eq!(snoozed["data"]["snooze_count"], 1);

        // 6. Enable smartphone dismiss for future sessions
        let (status, setting_resp) = call(
            &router,
            "PATCH",
            "/api/settings/smartphone-dismiss",
            Some(json!({ "enabled": true })),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(setting_resp["enabled"], true);
    }

    #[tokio::test]
    async fn breathing_endpoints_return_capability_unavailable() {
        let router = app();

        for path in [
            "/api/breathing/start",
            "/api/breathing/volume",
            "/api/breathing/stop",
        ] {
            let (status, body) = call(&router, "POST", path, Some(json!({}))).await;
            assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
            assert_eq!(body["error"]["code"], json!("capability_unavailable"));
        }
    }

    #[tokio::test]
    async fn nap_endpoints_start_and_cancel_nap() {
        let router = app();

        // 1. Start nap
        let (status, resp) = call(
            &router,
            "POST",
            "/api/nap/start",
            Some(json!({ "duration_minutes": 15 })),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(resp["data"]["id"], json!("nap"));
        assert_eq!(resp["data"]["label"], json!("Sieste"));
        assert_eq!(resp["data"]["prewake_seconds"], json!(120));

        // 2. Check state includes nap
        let (status, state) = call(&router, "GET", "/api/state", None).await;
        assert_eq!(status, StatusCode::OK);
        let alarms = state["alarms"].as_array().unwrap();
        assert!(alarms.iter().any(|a| a["id"] == "nap"));

        // 3. Cancel nap
        let (status, cancel_resp) = call(&router, "POST", "/api/nap/cancel", None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(cancel_resp["cancelled"], true);

        // 4. Verify nap is gone
        let (status, state2) = call(&router, "GET", "/api/state", None).await;
        assert_eq!(status, StatusCode::OK);
        let alarms2 = state2["alarms"].as_array().unwrap();
        assert!(!alarms2.iter().any(|a| a["id"] == "nap"));
    }

    #[tokio::test]
    async fn factory_reset_endpoint_wipes_device_state() {
        let router = app();

        // Create an alarm first
        let (status, _) = call(
            &router,
            "POST",
            "/api/alarms",
            Some(json!({ "label": "Morning", "local_time": "07:00", "days_of_week": [1, 2, 3] })),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED);

        // Confirmation required
        let (status, err) = call(
            &router,
            "POST",
            "/api/factory-reset",
            Some(json!({ "confirmation": "wrong" })),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
        assert_eq!(err["error"]["code"], json!("invalid_confirmation"));

        // Valid confirmation resets
        let (status, ok_resp) = call(
            &router,
            "POST",
            "/api/factory-reset",
            Some(json!({ "confirmation": "RESET" })),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(ok_resp["state"], json!("factory_reset"));

        let (status, state) = call(&router, "GET", "/api/state", None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(state["alarms"], json!([]));
    }

    #[tokio::test]
    async fn sound_upload_validates_and_registers_sound() {
        use base64::prelude::*;
        use sha2::{Digest, Sha256};

        let router = app();
        let wav = crate::sounds::create_test_wav(44100, 1, 0.5, 440.0);
        let b64 = BASE64_STANDARD.encode(&wav);

        let mut hasher = Sha256::new();
        hasher.update(&wav);
        let digest = hex::encode(hasher.finalize());

        // 1. Upload valid sound
        let (status, resp) = call(
            &router,
            "POST",
            "/api/sounds",
            Some(json!({
                "id": "my_chime",
                "data_base64": b64,
                "sha256": digest,
            })),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{resp}");
        assert_eq!(resp["data"]["id"], json!("my_chime"));

        // 2. Listed in sounds endpoint
        let (status, list_resp) = call(&router, "GET", "/api/sounds", None).await;
        assert_eq!(status, StatusCode::OK);
        let sounds = list_resp["data"].as_array().unwrap();
        assert!(sounds.iter().any(|s| s["id"] == "my_chime"));

        // 3. Reject invalid digest
        let (status, err) = call(
            &router,
            "POST",
            "/api/sounds",
            Some(json!({
                "id": "bad_digest",
                "data_base64": b64,
                "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
            })),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
        assert_eq!(err["error"]["code"], json!("invalid_size_or_digest"));
    }

    #[tokio::test]
    async fn export_and_diagnostics_endpoints_return_sanitized_json() {
        let router = app();

        // 1. GET /api/export
        let (status, export) = call(&router, "GET", "/api/export", None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(export["format"], json!("robine-wake-configuration"));
        assert!(export["alarms"].is_array());
        assert_eq!(export["smartphone_dismiss_enabled"], json!(false));
        // Must contain NO secret fields (DAT-002.1)
        assert!(export.get("secret").is_none());
        assert!(export.get("buttons").is_none());

        // 2. GET /api/diagnostics
        let (status, diag) = call(&router, "GET", "/api/diagnostics", None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(diag["format"], json!("robine-wake-diagnostics"));
        assert!(diag["manifest"].is_array());
        assert!(diag["files"]["health.json"].is_object());
        assert!(diag["files"]["configuration.json"].is_object());
        assert!(diag["files"]["recent_sessions.json"].is_array());
    }

    #[tokio::test]
    async fn mcp_http_endpoint_conforms_to_api_003() {
        let router = app();

        // 1. GET /mcp -> 405 Method Not Allowed with Allow: POST (API-003)
        let req_get = Request::builder()
            .method("GET")
            .uri("/mcp")
            .body(Body::empty())
            .unwrap();
        let resp_get = router.clone().oneshot(req_get).await.unwrap();
        assert_eq!(resp_get.status(), StatusCode::METHOD_NOT_ALLOWED);
        assert_eq!(resp_get.headers().get(header::ALLOW).unwrap(), "POST");

        // 2. POST /mcp with unauthorized Origin -> 403 Forbidden (API-003.3)
        let evil_req = Request::builder()
            .method("POST")
            .uri("/mcp")
            .header(header::ORIGIN, "https://malicious-website.com")
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "ping"
            }).to_string()))
            .unwrap();
        let evil_resp = router.clone().oneshot(evil_req).await.unwrap();
        assert_eq!(evil_resp.status(), StatusCode::FORBIDDEN);

        // 3. POST /mcp initialize with allowed Origin (http://localhost:4000)
        let init_req = Request::builder()
            .method("POST")
            .uri("/mcp")
            .header(header::ORIGIN, "http://localhost:4000")
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(json!({
                "jsonrpc": "2.0",
                "id": "init-1",
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-06-18"
                }
            }).to_string()))
            .unwrap();
        let init_resp = router.clone().oneshot(init_req).await.unwrap();
        assert_eq!(init_resp.status(), StatusCode::OK);
        let bytes = init_resp.into_body().collect().await.unwrap().to_bytes();
        let init_json: Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(init_json["result"]["protocolVersion"], "2025-06-18");
        assert_eq!(init_json["result"]["serverInfo"]["name"], "robine-wake");

        // 4. POST /mcp tools/list
        let list_req = Request::builder()
            .method("POST")
            .uri("/mcp")
            .header(header::ORIGIN, "http://robine-wake.local")
            .header("mcp-protocol-version", "2025-06-18")
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/list"
            }).to_string()))
            .unwrap();
        let list_resp = router.clone().oneshot(list_req).await.unwrap();
        assert_eq!(list_resp.status(), StatusCode::OK);
        let bytes = list_resp.into_body().collect().await.unwrap().to_bytes();
        let list_json: Value = serde_json::from_slice(&bytes).unwrap();
        let tools = list_json["result"]["tools"].as_array().unwrap();
        assert_eq!(tools.len(), 10);

        // 5. POST /mcp tools/call get_state
        let call_req = Request::builder()
            .method("POST")
            .uri("/mcp")
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(json!({
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "get_state"
                }
            }).to_string()))
            .unwrap();
        let call_resp = router.clone().oneshot(call_req).await.unwrap();
        assert_eq!(call_resp.status(), StatusCode::OK);
        let bytes = call_resp.into_body().collect().await.unwrap().to_bytes();
        let call_json: Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(call_json["result"]["isError"], false);
        assert!(call_json["result"]["structuredContent"]["alarms"].is_array());
    }
}
