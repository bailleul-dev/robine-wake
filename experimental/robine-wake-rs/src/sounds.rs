//! Read-only view of the bundled sound library (`priv/sounds/manifest.json`).
//!
//! Only the subset of `RobineWake.SoundLibrary` the alarm API needs: listing
//! and availability. Custom uploads and WAV validation are out of scope.

use std::path::{Path, PathBuf};

use serde_json::{json, Value};

pub struct Sounds {
    directory: PathBuf,
    manifest: Vec<Value>,
}

impl Sounds {
    pub fn open(directory: impl Into<PathBuf>) -> Sounds {
        let directory = directory.into();
        let manifest = std::fs::read(directory.join("manifest.json"))
            .ok()
            .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
            .and_then(|value| value.as_array().cloned())
            .unwrap_or_default();
        Sounds {
            directory,
            manifest,
        }
    }

    /// `"default"` is always accepted; bundled ids must have their file on disk.
    pub fn available(&self, id: &str) -> bool {
        id == "default" || self.file_for(id).is_some_and(|path| path.is_file())
    }

    pub fn list(&self) -> Vec<Value> {
        let mut sounds: Vec<Value> = self
            .manifest
            .iter()
            .filter_map(|entry| {
                let id = entry.get("id")?.as_str()?;
                let mut item = entry.clone();
                item["source"] = json!("bundled");
                item["available"] = json!(self.available(id));
                Some(item)
            })
            .collect();
        sounds.sort_by_key(|item| item["title"].as_str().unwrap_or("").to_lowercase());
        sounds
    }

    fn file_for(&self, id: &str) -> Option<PathBuf> {
        let filename = self
            .manifest
            .iter()
            .find(|entry| entry.get("id").and_then(Value::as_str) == Some(id))
            .and_then(|entry| entry.get("filename"))
            .and_then(Value::as_str)?;
        // Never let an id escape the library directory.
        if Path::new(filename).components().count() != 1 {
            return None;
        }
        Some(self.directory.join(filename))
    }
}
