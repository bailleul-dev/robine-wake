//! Local maintenance CLI (OPS-001.2, OPS-002).
//!
//! Provides `robine-wake status`, `robine-wake can-update`, and `robine-wake logs`
//! commands invoked from the shell or by update scripts (`robine-update`).

use chrono::{DateTime, Utc};
use serde_json::Value;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;

pub fn run(args: &[String], port: u16) -> Result<(), i32> {
    let command = args.get(1).map(String::as_str).unwrap_or("");

    match command {
        "status" => {
            cmd_status(port);
            Ok(())
        }
        "can-update" => {
            cmd_can_update(port);
            Ok(())
        }
        "logs" => {
            let follow = args.iter().any(|a| a == "-f");
            cmd_logs(follow);
            Ok(())
        }
        "help" | "--help" | "-h" => {
            print_usage();
            Ok(())
        }
        unknown => {
            eprintln!("Unknown command: '{unknown}'");
            print_usage();
            Err(2)
        }
    }
}

fn print_usage() {
    eprintln!(
        "Usage: robine-wake <command>\n\n\
         Commands:\n  \
           status       Show daemon health, clock quality, and next alarm\n  \
           can-update   Verify A/B update policy rules (OPS-001.2)\n  \
           logs [-f]    Display recent system/daemon logs\n  \
           help         Show this help message\n\n\
         Running without arguments starts the device daemon."
    );
}

fn fetch_health(port: u16) -> Result<Value, String> {
    let mut stream =
        TcpStream::connect_timeout(&([127, 0, 0, 1], port).into(), Duration::from_millis(1500))
            .map_err(|e| format!("cannot connect to daemon at http://127.0.0.1:{port}: {e}"))?;

    stream
        .set_read_timeout(Some(Duration::from_millis(2000)))
        .ok();
    stream
        .set_write_timeout(Some(Duration::from_millis(1000)))
        .ok();

    let request =
        format!("GET /health HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\n\r\n");
    stream
        .write_all(request.as_bytes())
        .map_err(|e| format!("failed to send request: {e}"))?;

    let mut response = String::new();
    stream
        .read_to_string(&mut response)
        .map_err(|e| format!("failed to read response: {e}"))?;

    let body = response
        .split("\r\n\r\n")
        .nth(1)
        .ok_or_else(|| "invalid HTTP response from daemon".to_string())?;

    serde_json::from_str::<Value>(body)
        .map_err(|e| format!("invalid JSON in /health response: {e}"))
}

fn cmd_status(port: u16) {
    let health = match fetch_health(port) {
        Ok(h) => h,
        Err(err) => {
            eprintln!("robine-wake: daemon is stopped or unreachable ({err})");
            std::process::exit(1);
        }
    };

    let state = health
        .get("state")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let version = health
        .get("version")
        .and_then(Value::as_str)
        .unwrap_or(env!("CARGO_PKG_VERSION"));
    let target = health
        .get("target")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let uptime_ms = health.get("uptime_ms").and_then(Value::as_u64).unwrap_or(0);

    let clock_quality = health
        .pointer("/clock/quality")
        .and_then(Value::as_str)
        .unwrap_or("untrusted");
    let clock_now = health
        .pointer("/clock/now")
        .or_else(|| health.get("now"))
        .and_then(Value::as_str)
        .unwrap_or("unknown");

    let storage_state = health
        .pointer("/storage/state")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let storage_reason = health.pointer("/storage/reason").and_then(Value::as_str);

    let next_alarm = health
        .pointer("/scheduler/next/alarm_id")
        .and_then(Value::as_str);
    let next_at = health.pointer("/scheduler/next/at").and_then(Value::as_str);
    let armed = health
        .pointer("/scheduler/armed")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    let active_session = health.get("active_session").and_then(|v| {
        if v.is_null() {
            None
        } else if let Some(s) = v.as_str() {
            Some(s.to_string())
        } else {
            let id = v.get("id").and_then(Value::as_str).unwrap_or("active");
            let status = v.get("status").and_then(Value::as_str).unwrap_or("ringing");
            let phase = v.get("phase").and_then(Value::as_str).unwrap_or("gentle");
            let gain = v.get("current_gain").and_then(Value::as_i64).unwrap_or(0);
            Some(format!("{id} ({status}, {phase}, gain {gain}%)"))
        }
    });

    let uptime_secs = uptime_ms / 1000;
    let mins = uptime_secs / 60;
    let secs = uptime_secs % 60;

    println!("Robine Wake v{version} ({target})");
    println!("  Status:    {state}");
    println!("  Clock:     {clock_now} ({clock_quality})");
    println!("  Uptime:    {mins}m {secs}s");
    println!(
        "  Storage:   {storage_state}{}",
        storage_reason
            .map(|r| format!(" ({r})"))
            .unwrap_or_default()
    );
    match (next_alarm, next_at) {
        (Some(id), Some(at)) => {
            println!(
                "  Scheduler: next alarm '{id}' at {at} ({})",
                if armed { "armed" } else { "unarmed" }
            );
        }
        _ => println!("  Scheduler: no upcoming alarms"),
    }
    println!(
        "  Session:   {}",
        active_session.as_deref().unwrap_or("none")
    );
}

fn cmd_can_update(port: u16) {
    let health = match fetch_health(port) {
        Ok(h) => h,
        Err(err) => {
            eprintln!("robine-wake: update refused, daemon does not answer ({err})");
            std::process::exit(1);
        }
    };

    // 1. Refuse during an active wake session (OPS-001.2)
    if let Some(session) = health.get("active_session") {
        if !session.is_null() {
            eprintln!("robine-wake: update refused, a wake session is active");
            std::process::exit(1);
        }
    }

    // 2. Refuse if clock quality is untrusted (OPS-001.2, PLT-003.4)
    let clock_quality = health
        .pointer("/clock/quality")
        .and_then(Value::as_str)
        .unwrap_or("untrusted");
    if clock_quality == "untrusted" {
        eprintln!("robine-wake: update refused, system clock is untrusted");
        std::process::exit(1);
    }

    // 3. Refuse within 15 minutes of the next scheduled alarm (OPS-001.2)
    if let Some(at_str) = health.pointer("/scheduler/next/at").and_then(Value::as_str) {
        if let Ok(next_at) = DateTime::parse_from_rfc3339(at_str) {
            let next_at_utc = next_at.with_timezone(&Utc);
            let now = Utc::now();
            let duration = next_at_utc.signed_duration_since(now);
            if duration.num_seconds() > 0 && duration.num_minutes() < 15 {
                eprintln!(
                    "robine-wake: update refused, upcoming alarm at {at_str} is in {}m {}s (< 15 min)",
                    duration.num_minutes(),
                    duration.num_seconds() % 60
                );
                std::process::exit(1);
            }
        }
    }

    println!("robine-wake: update permitted by policy");
}

fn cmd_logs(follow: bool) {
    let log_files = [
        "/var/log/messages",
        "/run/log/daemon.log",
        "/data/log/critical.jsonl",
    ];
    let existing = log_files
        .iter()
        .find(|path| std::path::Path::new(path).exists());

    let file = match existing {
        Some(f) => *f,
        None => {
            eprintln!("robine-wake: no log file found in /var/log or /run/log");
            return;
        }
    };

    let mut cmd = std::process::Command::new("tail");
    if follow {
        cmd.arg("-f");
    } else {
        cmd.args(["-n", "100"]);
    }
    cmd.arg(file);

    match cmd.status() {
        Ok(status) => {
            if let Some(code) = status.code() {
                if code != 0 {
                    std::process::exit(code);
                }
            }
        }
        Err(e) => {
            eprintln!("robine-wake: cannot execute tail on {file}: {e}");
            std::process::exit(1);
        }
    }
}
