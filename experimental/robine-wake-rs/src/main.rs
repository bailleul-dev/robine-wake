//! EXPERIMENTAL Rust prototype of the Robine Wake local API.
//!
//! Not the product: the application is the Elixir/Nerves project at the
//! repository root. See `experimental/README.md`.

mod alarm;
mod events;
mod http;
mod sounds;
mod store;

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use events::EventStream;
use http::App;
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

#[tokio::main]
async fn main() {
    let port: u16 = std::env::var("ROBINE_RS_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(4120);
    let data = setting("ROBINE_RS_DATA", "data/robine_wake_rs.json");
    let web_dir = setting("ROBINE_RS_WEB", "../../priv/web");
    let sounds_dir = setting("ROBINE_RS_SOUNDS", "../../priv/sounds");

    let sounds = Sounds::open(&sounds_dir);
    let sounds_for_store = Sounds::open(&sounds_dir);
    let store = Store::open(&data, move |id| sounds_for_store.available(id));

    let app = Arc::new(App {
        store,
        events: EventStream::new(),
        sounds,
        web_dir: web_dir.clone(),
        started: Instant::now(),
    });

    eprintln!("robine-wake-rs EXPERIMENTAL prototype, not the product");
    eprintln!("  data   {}", data.display());
    eprintln!(
        "  web    {}{}",
        web_dir.display(),
        if web_dir.join("index.html").is_file() {
            ""
        } else {
            "  (missing: run `make expo-web` at the repository root)"
        }
    );
    eprintln!("  sounds {}", sounds_dir.display());
    eprintln!("  http   http://127.0.0.1:{port}");

    let listener = tokio::net::TcpListener::bind(("0.0.0.0", port))
        .await
        .unwrap_or_else(|error| panic!("cannot bind port {port}: {error}"));
    axum::serve(listener, http::router(app))
        .await
        .expect("http server");
}
