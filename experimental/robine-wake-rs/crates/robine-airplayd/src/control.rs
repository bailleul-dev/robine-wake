//! Line protocol with the Elixir app (`RobineWake.AirPlay`), which owns the
//! process through an Erlang port: one JSON event per line on stdout, one
//! JSON command per line on stdin. Logs go to stderr.
//!
//! Commands: `{"cmd":"suspend"}` releases the ALSA device and drops the
//! audio (an alarm takes the speaker); `suspended` is emitted once the
//! device is closed. `{"cmd":"resume"}` plays again.
//! The process exits when stdin closes, so it never outlives the port.

use std::io::Write;
use std::sync::atomic::Ordering;
use std::time::Duration;

use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, BufReader};

use crate::speaker::{Speaker, SUSPENDED};

/// Longest wait for `aplay` to close the device.
const RELEASE_TIMEOUT: Duration = Duration::from_secs(1);

pub fn emit(event: &str, fields: Value) {
    let mut line = json!({ "event": event });
    if let (Some(line), Value::Object(fields)) = (line.as_object_mut(), fields) {
        line.extend(fields);
    }
    let mut stdout = std::io::stdout().lock();
    let _ = writeln!(stdout, "{line}");
    let _ = stdout.flush();
}

pub async fn read_commands(speaker: Speaker) {
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        let command = serde_json::from_str::<Value>(&line).ok();
        match command.as_ref().and_then(|command| command["cmd"].as_str()) {
            Some("suspend") => {
                SUSPENDED.store(true, Ordering::Relaxed);
                let speaker = speaker.clone();
                let released = tokio::task::spawn_blocking(move || speaker.release(RELEASE_TIMEOUT)).await;
                if matches!(released, Ok(true)) {
                    emit("suspended", json!({}));
                } else {
                    emit("error", json!({ "reason": "release_timeout" }));
                }
            }
            Some("resume") => {
                SUSPENDED.store(false, Ordering::Relaxed);
                emit("resumed", json!({}));
            }
            _ => emit("error", json!({ "reason": "unknown_command", "line": line })),
        }
    }
    eprintln!("stdin closed, exiting");
    std::process::exit(0);
}
