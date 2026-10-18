//! JSON shapes of the Elixir command boundary.

use alloc::string::String;
use alloc::vec::Vec;
use chrono::{DateTime, SecondsFormat, TimeZone, Utc};
use robine_core::Alarm;
use serde_json::{json, Map, Value};

/// `DateTime.to_iso8601/1` for second-precision datetimes.
pub fn iso8601<Tz: TimeZone>(datetime: &DateTime<Tz>) -> String
where
    Tz::Offset: core::fmt::Display,
{
    datetime.to_rfc3339_opts(SecondsFormat::Secs, true)
}

/// `alarm_dto/1`: the alarm map plus its next five occurrences when enabled.
pub fn alarm(alarm: &Alarm, now: DateTime<Utc>) -> Value {
    let occurrences: Vec<Value> = if alarm.enabled {
        alarm
            .next_occurrences(5, now)
            .iter()
            .map(|at| Value::String(iso8601(at)))
            .collect()
    } else {
        Vec::new()
    };
    let mut map = alarm.to_map();
    map.insert("next_occurrences".into(), Value::Array(occurrences));
    Value::Object(map)
}

/// `select/2`: keeps the listed keys, dropping absent and `null` values.
pub fn select(source: &Map<String, Value>, keys: &[&str]) -> Value {
    let mut selected = Map::new();
    for key in keys {
        if let Some(value) = source.get(*key).filter(|value| !value.is_null()) {
            selected.insert((*key).into(), value.clone());
        }
    }
    Value::Object(selected)
}

/// Keys of `session_dto/1`.
pub const SESSION_KEYS: &[&str] = &[
    "id",
    "alarm_id",
    "state",
    "terminal_reason",
    "created_at",
    "ended_at",
    "audio_phase",
    "current_gain",
    "snooze_count",
    "smartphone_dismiss_allowed",
    "test_mode",
];

pub fn success(id: &Value, body: Value) -> Value {
    json!({ "v": 1, "id": id, "status": "ok", "body": body })
}

pub fn failure(id: &Value, code: &str, details: Option<Value>) -> Value {
    let mut error = Map::new();
    error.insert("code".into(), Value::String(code.into()));
    if let Some(details) = details {
        error.insert("details".into(), details);
    }
    json!({ "v": 1, "id": id, "status": "error", "error": error })
}
