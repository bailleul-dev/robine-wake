//! Hardware watchdog feeder (PLT-004.4).
//!
//! Opens `/dev/watchdog` if present and pings it every 4 seconds as long as
//! the tokio event loop is responsive. If the daemon freezes for more than
//! 15 seconds, the hardware watchdog reboots the board.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::Path;
use std::time::Duration;

const WATCHDOG_DEV: &str = "/dev/watchdog";
const PING_INTERVAL: Duration = Duration::from_secs(4);

pub struct Watchdog;

impl Watchdog {
    /// Spawn a background task to feed `/dev/watchdog` if the device is present.
    pub fn start() {
        if !Path::new(WATCHDOG_DEV).exists() {
            return;
        }

        tokio::spawn(async move {
            let mut file = match OpenOptions::new().write(true).open(WATCHDOG_DEV) {
                Ok(f) => f,
                Err(e) => {
                    eprintln!("  watchdog disabled: cannot open {WATCHDOG_DEV}: {e}");
                    return;
                }
            };

            eprintln!(
                "  watchdog active on {WATCHDOG_DEV} (pinging every {}s)",
                PING_INTERVAL.as_secs()
            );
            let mut interval = tokio::time::interval(PING_INTERVAL);

            loop {
                interval.tick().await;
                if let Err(e) = feed(&mut file) {
                    eprintln!("  watchdog ping failed: {e}");
                    break;
                }
            }
        });
    }
}

fn feed(file: &mut File) -> std::io::Result<()> {
    file.write_all(b"\0")?;
    file.flush()
}
