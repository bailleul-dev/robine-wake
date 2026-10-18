//! Wall clock: the monotonic timer plus an offset learnt from NTP.
//!
//! Before the first synchronization the clock counts from the Unix epoch and
//! is untrusted, so the scheduler never fires an alarm on a wrong time.

use core::cell::Cell;

use chrono::{DateTime, Utc};
use critical_section::Mutex;
use embassy_time::Instant;

#[derive(Clone, Copy)]
struct State {
    /// Unix milliseconds minus monotonic milliseconds.
    offset_ms: i64,
    trusted: bool,
}

static STATE: Mutex<Cell<State>> = Mutex::new(Cell::new(State {
    offset_ms: 0,
    trusted: false,
}));

fn state() -> State {
    critical_section::with(|cs| STATE.borrow(cs).get())
}

pub fn monotonic_ms() -> u64 {
    Instant::now().as_millis()
}

pub fn now() -> DateTime<Utc> {
    let unix_ms = monotonic_ms() as i64 + state().offset_ms;
    DateTime::from_timestamp_millis(unix_ms).unwrap_or_default()
}

pub fn trusted() -> bool {
    state().trusted
}

/// Sets the wall clock from an NTP answer and trusts it.
pub fn set_unix_ms(unix_ms: i64) {
    let offset_ms = unix_ms - monotonic_ms() as i64;
    critical_section::with(|cs| {
        STATE.borrow(cs).set(State {
            offset_ms,
            trusted: true,
        })
    });
}

/// `clock.confirm`: the user vouches for the current time.
pub fn trust() {
    critical_section::with(|cs| {
        let cell = STATE.borrow(cs);
        cell.set(State {
            trusted: true,
            ..cell.get()
        })
    });
}
