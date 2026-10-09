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
use tokio_stream::wrappers::BroadcastStream;
use tower_http::services::{ServeDir, ServeFile};

use crate::alarm::Alarm;
use crate::events::EventStream;
use crate::sounds::Sounds;
use crate::store::{Store, StoreError};

pub const VERSION: &str = env!("CARGO_PKG_VERSION");
pub const TARGET: &str = "host-rs-experimental";

pub struct App {
    pub store: Store,
    pub events: EventStream,
    pub sounds: Sounds,
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
        .route("/api/alarms", get(list_alarms).post(create_alarm))
        .route("/api/alarms/preview", post(preview_alarm))
        .route(
            "/api/alarms/{id}",
            axum::routing::patch(update_alarm).delete(delete_alarm),
        )
        .route("/api/sounds", get(sounds))
        .route("/api/v1/events", get(events))
        .fallback_service(web)
        .with_state(app)
}

async fn health(State(app): State<Shared>) -> Json<Value> {
    Json(health_snapshot(&app))
}

async fn state(State(app): State<Shared>) -> Json<Value> {
    let now = Utc::now();
    Json(json!({
        "health": health_snapshot(&app),
        "alarms": app.store.list().iter().map(|alarm| alarm_json(alarm, now)).collect::<Vec<_>>(),
        "sessions": app.store.raw("sessions"),
        "active_session": Value::Null,
        "smartphone_dismiss": { "enabled": false, "locked": false },
        "hue": { "state": "not_implemented" },
        "hue_targets": [],
        "remote_button": { "state": "not_implemented" },
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
    let next = app
        .store
        .list()
        .iter()
        .filter(|alarm| alarm.enabled)
        .filter_map(|alarm| alarm.next_occurrence(now).map(|at| (at.with_timezone(&Utc), alarm.id.clone())))
        .min()
        .map(|(at, alarm_id)| json!({ "alarm_id": alarm_id, "at": at.to_rfc3339_opts(chrono::SecondsFormat::Secs, true) }));
    let degraded = app.store.degraded();

    json!({
        "state": if degraded.is_some() { "degraded" } else { "available" },
        "version": VERSION,
        "target": TARGET,
        "now": now.to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
        "uptime_ms": app.started.elapsed().as_millis() as u64,
        "storage": { "state": if degraded.is_some() { "degraded" } else { "available" }, "reason": degraded },
        "scheduler": { "state": "preview_only", "next": next },
        "active_session": Value::Null,
        "experimental": {
            "note": "Rust prototype under experimental/. Not the product.",
            "not_implemented": ["wake_session", "scheduler", "audio", "hue", "airplay", "bluetooth_audio", "lora", "mcp", "auth", "remote_button", "firmware"]
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

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request;
    use http_body_util::BodyExt;
    use tower::ServiceExt;

    fn app() -> Router {
        let scratch = std::env::temp_dir().join("robine-wake-rs-tests");
        let data = scratch.join(format!("{}.json", uuid::Uuid::new_v4()));
        let web = scratch.join("no-web");
        let app = Arc::new(App {
            store: Store::open(data, |id| id == "default" || id == "jungle_sunrise"),
            events: EventStream::new(),
            sounds: Sounds::open(scratch.join("no-sounds")),
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
}
