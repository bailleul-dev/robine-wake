//! Alarm storage on the `schema_version: 1` JSON file of the Elixir app.
//!
//! Port of the alarm half of `RobineWake.Settings` plus `Persistence`.
//! Keys this prototype does not understand (`sessions`, `settings`,
//! `created_at`, ...) are preserved verbatim so the file stays usable by the
//! Elixir application.

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use chrono::{DateTime, Utc};
use serde_json::{json, Map, Value};

use crate::alarm::{Alarm, Errors};

const SCHEMA_VERSION: u64 = 1;

#[derive(Debug)]
pub enum StoreError {
    NotFound,
    AlreadyExists,
    RevisionConflict,
    Invalid(Errors),
    Io(String),
}

impl From<io::Error> for StoreError {
    fn from(error: io::Error) -> Self {
        StoreError::Io(error.to_string())
    }
}

impl From<Errors> for StoreError {
    fn from(errors: Errors) -> Self {
        StoreError::Invalid(errors)
    }
}

struct Inner {
    raw: Map<String, Value>,
    alarms: BTreeMap<String, Alarm>,
    degraded: Option<String>,
}

pub struct Store {
    path: PathBuf,
    sound_available: Box<dyn Fn(&str) -> bool + Send + Sync>,
    inner: Mutex<Inner>,
}

impl Store {
    /// Load the file, or start empty when it does not exist. A corrupt or
    /// unreadable file leaves the store degraded rather than failing startup,
    /// like the Elixir `Settings.init/1`.
    pub fn open(
        path: impl Into<PathBuf>,
        sound_available: impl Fn(&str) -> bool + Send + Sync + 'static,
    ) -> Store {
        let path = path.into();
        let (raw, degraded) = match load(&path) {
            Ok(raw) => (raw, None),
            Err(reason) => {
                eprintln!("settings storage could not be read: {reason}");
                (empty(), Some(reason))
            }
        };
        let now = Utc::now();
        let alarms = raw
            .get("alarms")
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(|item| match Alarm::new(item, now) {
                        Ok(alarm) => Some((alarm.id.clone(), alarm)),
                        Err(errors) => {
                            eprintln!("skipping invalid persisted alarm: {errors:?}");
                            None
                        }
                    })
                    .collect()
            })
            .unwrap_or_default();

        Store {
            path,
            sound_available: Box::new(sound_available),
            inner: Mutex::new(Inner {
                raw,
                alarms,
                degraded,
            }),
        }
    }

    pub fn degraded(&self) -> Option<String> {
        self.lock().degraded.clone()
    }

    /// Alarms sorted by local time then id, like `sorted_alarms/1`.
    pub fn list(&self) -> Vec<Alarm> {
        let mut alarms: Vec<Alarm> = self.lock().alarms.values().cloned().collect();
        alarms.sort_by(|a, b| (a.local_time, &a.id).cmp(&(b.local_time, &b.id)));
        alarms
    }

    /// Raw passthrough of a top-level key (`sessions`, `settings`).
    pub fn raw(&self, key: &str) -> Value {
        self.lock().raw.get(key).cloned().unwrap_or(Value::Null)
    }

    pub fn create(&self, input: &Value, now: DateTime<Utc>) -> Result<Alarm, StoreError> {
        let alarm = Alarm::new(input, now)?;
        self.validate_sound(&alarm)?;
        let mut inner = self.lock();
        if inner.alarms.contains_key(&alarm.id) {
            return Err(StoreError::AlreadyExists);
        }
        let mut next = inner.alarms.clone();
        next.insert(alarm.id.clone(), alarm.clone());
        self.persist(&mut inner, next)?;
        Ok(alarm)
    }

    pub fn update(&self, id: &str, input: &Value, now: DateTime<Utc>) -> Result<Alarm, StoreError> {
        let mut inner = self.lock();
        let current = inner.alarms.get(id).ok_or(StoreError::NotFound)?.clone();
        let attrs = input.as_object().cloned().unwrap_or_default();
        check_revision(&current, attrs.get("revision"))?;

        let mut merged = current.to_map();
        merged.extend(attrs);
        merged.insert("revision".into(), json!(current.revision + 1));
        let alarm = Alarm::new(&Value::Object(merged), now)?;
        self.validate_sound(&alarm)?;

        let mut next = inner.alarms.clone();
        next.insert(id.to_string(), alarm.clone());
        self.persist(&mut inner, next)?;
        Ok(alarm)
    }

    pub fn delete(&self, id: &str, revision: Option<&Value>) -> Result<(), StoreError> {
        let mut inner = self.lock();
        let current = inner.alarms.get(id).ok_or(StoreError::NotFound)?.clone();
        check_revision(&current, revision)?;
        let mut next = inner.alarms.clone();
        next.remove(id);
        self.persist(&mut inner, next)
    }

    fn validate_sound(&self, alarm: &Alarm) -> Result<(), StoreError> {
        for (field, id) in [
            ("sound_id", &alarm.sound_id),
            ("strong_sound_id", &alarm.strong_sound_id),
        ] {
            if !(self.sound_available)(id) {
                return Err(StoreError::Invalid(BTreeMap::from([(
                    field.to_string(),
                    "does not reference an available validated sound".to_string(),
                )])));
            }
        }
        Ok(())
    }

    /// Write the new alarm set atomically; the in-memory state only changes
    /// once the file is safely on disk.
    fn persist(
        &self,
        inner: &mut Inner,
        alarms: BTreeMap<String, Alarm>,
    ) -> Result<(), StoreError> {
        let mut raw = inner.raw.clone();
        raw.insert("schema_version".into(), json!(SCHEMA_VERSION));
        raw.insert(
            "alarms".into(),
            Value::Array(
                alarms
                    .values()
                    .map(|alarm| Value::Object(alarm.to_map()))
                    .collect(),
            ),
        );
        save(&self.path, &raw)?;
        inner.raw = raw;
        inner.alarms = alarms;
        inner.degraded = None;
        Ok(())
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

fn check_revision(current: &Alarm, requested: Option<&Value>) -> Result<(), StoreError> {
    match requested.and_then(Value::as_i64) {
        Some(revision) if revision == current.revision => Ok(()),
        _ => Err(StoreError::RevisionConflict),
    }
}

fn empty() -> Map<String, Value> {
    let mut map = Map::new();
    map.insert("schema_version".into(), json!(SCHEMA_VERSION));
    map.insert("alarms".into(), json!([]));
    map.insert("sessions".into(), json!([]));
    map.insert("settings".into(), json!({}));
    map
}

fn load(path: &Path) -> Result<Map<String, Value>, String> {
    let contents = match fs::read(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(empty()),
        Err(error) => return Err(error.to_string()),
    };
    let data: Value = serde_json::from_slice(&contents).map_err(|error| error.to_string())?;
    let map = data
        .as_object()
        .ok_or("storage root must be an object")?
        .clone();
    match map.get("schema_version").and_then(Value::as_u64) {
        Some(SCHEMA_VERSION) => Ok(map),
        Some(version) => Err(format!("unsupported schema version {version}")),
        None => Err("missing schema version".to_string()),
    }
}

/// `Persistence.save/2`: temporary file, fsync, 0600, rename.
fn save(path: &Path, data: &Map<String, Value>) -> io::Result<()> {
    if let Some(directory) = path.parent() {
        fs::create_dir_all(directory)?;
    }
    let temporary = path.with_extension("json.tmp");
    let mut encoded = serde_json::to_string_pretty(data)?;
    encoded.push('\n');
    {
        use std::io::Write;
        let mut file = fs::File::create(&temporary)?;
        file.write_all(encoded.as_bytes())?;
        file.sync_all()?;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&temporary, fs::Permissions::from_mode(0o600))?;
    }
    fs::rename(&temporary, path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch_path() -> PathBuf {
        std::env::temp_dir()
            .join("robine-wake-rs-tests")
            .join(format!("{}.json", uuid::Uuid::new_v4()))
    }

    fn open(path: &Path) -> Store {
        Store::open(path, |id| id != "missing")
    }

    #[test]
    fn creates_updates_and_deletes_with_optimistic_revisions() {
        let path = scratch_path();
        let store = open(&path);
        let now = Utc::now();

        let alarm = store
            .create(&json!({ "label": "Test", "local_time": "06:45" }), now)
            .unwrap();
        assert_eq!(alarm.revision, 1);
        assert_eq!(store.list().len(), 1);

        let stale = store.update(&alarm.id, &json!({ "label": "Stale", "revision": 7 }), now);
        assert!(matches!(stale, Err(StoreError::RevisionConflict)));

        let updated = store
            .update(&alarm.id, &json!({ "label": "Fresh", "revision": 1 }), now)
            .unwrap();
        assert_eq!((updated.label.as_str(), updated.revision), ("Fresh", 2));
        assert_eq!(
            updated.local_time, alarm.local_time,
            "untouched fields survive a partial update"
        );

        assert!(matches!(
            store.delete(&alarm.id, Some(&json!(1))),
            Err(StoreError::RevisionConflict)
        ));
        store.delete(&alarm.id, Some(&json!(2))).unwrap();
        assert!(matches!(
            store.delete(&alarm.id, Some(&json!(2))),
            Err(StoreError::NotFound)
        ));

        let reloaded = open(&path);
        assert!(reloaded.list().is_empty());
        assert_eq!(reloaded.raw("schema_version"), json!(1));
    }

    #[test]
    fn rejects_unknown_sounds_and_preserves_foreign_keys() {
        let path = scratch_path();
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(
            &path,
            r#"{"schema_version":1,"alarms":[],"sessions":[{"id":"S1"}],"settings":{"smartphone_dismiss_enabled":false},"created_at":"2026-08-19T15:18:00Z"}"#,
        )
        .unwrap();
        let store = open(&path);

        let rejected = store.create(&json!({ "sound_id": "missing" }), Utc::now());
        assert!(
            matches!(rejected, Err(StoreError::Invalid(ref errors)) if errors.contains_key("sound_id"))
        );

        store
            .create(&json!({ "label": "Kept" }), Utc::now())
            .unwrap();
        let written: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        assert_eq!(written["sessions"], json!([{ "id": "S1" }]));
        assert_eq!(
            written["settings"]["smartphone_dismiss_enabled"],
            json!(false)
        );
        assert_eq!(written["created_at"], json!("2026-08-19T15:18:00Z"));
        assert_eq!(written["alarms"][0]["label"], json!("Kept"));
    }

    #[test]
    fn a_corrupt_file_degrades_instead_of_failing() {
        let path = scratch_path();
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, "{not json").unwrap();
        let store = open(&path);
        assert!(store.degraded().is_some());
        assert!(store.list().is_empty());
    }
}
