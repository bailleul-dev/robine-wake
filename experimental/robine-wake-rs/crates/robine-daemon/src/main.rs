//! Robine Wake 2 device daemon.
//!
//! Phase 1: the alarm API prototype ported from the v1 repository
//! (`experimental/robine-wake-rs`). See `doc/specs`.

mod alarm;
mod audio;
mod cli;
mod clock;
mod command;
mod events;
mod http;
mod lora;
mod mcp;
mod mdns;
mod scheduler;
mod session_manager;
mod sounds;
mod store;
mod watchdog;

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use audio::AudioSink;
use clock::Clock;
use command::CommandHandler;
use events::EventStream;
use http::App;
use mdns::MdnsResponder;
use scheduler::Scheduler;
use session_manager::SessionManager;
use sounds::Sounds;
use store::Store;

/// Defaults resolve against the crate directory, never against the Elixir
/// application's data file, so running the prototype cannot clobber it.
fn setting(name: &str, default: &str) -> PathBuf {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => PathBuf::from(value),
        _ => PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(default),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let port: u16 = std::env::var("ROBINE_RS_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(4000);

    // If invoked with a CLI subcommand (OPS-001.2, OPS-002), run it synchronously.
    if args.len() > 1 && args[1] != "daemon" && args[1] != "run" {
        if let Err(code) = cli::run(&args, port) {
            std::process::exit(code);
        }
        return;
    }

    run_daemon(port);
}

#[tokio::main]
async fn run_daemon(port: u16) {
    let data = setting("ROBINE_RS_DATA", "data/robine_wake_rs.json");
    let web_dir = setting("ROBINE_RS_WEB", "../../../../priv/web");
    let sounds_dir = setting("ROBINE_RS_SOUNDS", "../../../../priv/sounds");
    let custom_sounds_dir = setting("ROBINE_RS_CUSTOM_SOUNDS", "/data/sounds");

    let sounds = Arc::new(Sounds::with_custom(&sounds_dir, &custom_sounds_dir));
    let sounds_for_store = Sounds::with_custom(&sounds_dir, &custom_sounds_dir);
    let store = Arc::new(Store::open(&data, move |id| sounds_for_store.available(id)));
    let clock = Arc::new(Clock::new());
    let audio = Arc::new(AudioSink::new());
    let events = EventStream::new();
    let sessions = Arc::new(SessionManager::new(
        audio.clone(),
        store.clone(),
        events.clone(),
    ));
    let lora = Arc::new(lora::LoraService::new(
        store.clone(),
        sessions.clone(),
        events.clone(),
    ));
    let _lora_handle = lora.clone().start();

    // Generate AirPlay configuration if /run is writable (AUD-002)
    let _ = audio::generate_shairport_config(std::path::Path::new("/run/shairport-sync.conf"));

    let commands = Arc::new(CommandHandler::with_lora(
        store.clone(),
        sessions.clone(),
        clock.clone(),
        sounds.clone(),
        audio.clone(),
        events.clone(),
        Some(lora.clone()),
    ));
    let scheduler = Arc::new(Scheduler::new(
        store.clone(),
        clock.clone(),
        sessions.clone(),
        events.clone(),
    ));
    let _scheduler_handle = scheduler.clone().start();

    let mcp = Arc::new(mcp::McpHandler::new(
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
        web_dir: web_dir.clone(),
        started: Instant::now(),
    });

    eprintln!("robine-wake {}", env!("CARGO_PKG_VERSION"));
    eprintln!("  data   {}", data.display());
    eprintln!(
        "  web    {}{}",
        web_dir.display(),
        if web_dir.join("index.html").is_file() {
            ""
        } else {
            "  (missing web bundle)"
        }
    );
    eprintln!("  sounds {}", sounds_dir.display());
    eprintln!("  http   http://127.0.0.1:{port}");

    // Announce robine-wake.local via mDNS (PLT-003.1).
    let ssh_port: u16 = std::env::var("SSH_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(22);
    let _mdns = MdnsResponder::start(port, ssh_port).ok();

    // Feed /dev/watchdog if present (PLT-004.4).
    watchdog::Watchdog::start();

    let listener = tokio::net::TcpListener::bind(("0.0.0.0", port))
        .await
        .unwrap_or_else(|error| panic!("cannot bind port {port}: {error}"));
    axum::serve(listener, http::router(app))
        .await
        .expect("http server");
}
