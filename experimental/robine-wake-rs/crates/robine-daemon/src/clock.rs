//! Clock quality monitoring and NTP synchronization check (PLT-003).
//!
//! Without a hardware RTC, the board restores a floor time from `/data/clock`.
//! Until NTP synchronizes the system clock (or the user explicitly confirms it),
//! the clock remains "untrusted" and silent alarm arming or updates are gated.

use chrono::{Datelike, Utc};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClockQuality {
    Trusted,
    Untrusted,
}

pub struct Clock {
    confirmed: AtomicBool,
}

impl Clock {
    pub fn new() -> Self {
        Self {
            confirmed: AtomicBool::new(false),
        }
    }

    /// Explicitly mark the clock as trusted (API: clock.confirm).
    pub fn confirm(&self) {
        self.confirmed.store(true, Ordering::SeqCst);
    }

    /// Current clock quality based on kernel NTP sync and safety checks.
    pub fn quality(&self) -> ClockQuality {
        if self.confirmed.load(Ordering::SeqCst) {
            return ClockQuality::Trusted;
        }

        let now = Utc::now();
        // Clocks prior to year 2026 are definitely uninitialized/restored from ancient epoch.
        if now.year() < 2026 {
            return ClockQuality::Untrusted;
        }

        if is_kernel_clock_synchronized() {
            ClockQuality::Trusted
        } else {
            ClockQuality::Untrusted
        }
    }
}

impl Default for Clock {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(target_os = "linux")]
fn is_kernel_clock_synchronized() -> bool {
    unsafe {
        let mut t: libc::timex = std::mem::zeroed();
        let status = libc::adjtimex(&mut t);
        // adjtimex returns clock state:
        // TIME_OK = 0, TIME_INS = 1, TIME_DEL = 2, TIME_OOP = 3, TIME_WAIT = 4, TIME_BAD = 5
        // STA_UNSYNC is 0x0040.
        !(status < 0 || status == 5 || (t.status & 0x0040) != 0)
    }
}

#[cfg(not(target_os = "linux"))]
fn is_kernel_clock_synchronized() -> bool {
    // On non-Linux host development, assume synchronized for developer convenience
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clock_quality_transitions_on_confirmation() {
        let clock = Clock::new();
        clock.confirm();
        assert_eq!(clock.quality(), ClockQuality::Trusted);
    }
}
