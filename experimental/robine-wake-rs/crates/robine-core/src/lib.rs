//! Robine Wake 2 pure core domain library (PRD-002).
//!
//! Contains pure domain rules, models, validations, and state machines with zero I/O
//! and no async runtime dependencies. `no_std + alloc` without the `std` feature
//! (PLT-005.1), so the same rules run on the ESP32 firmware.

#![no_std]

extern crate alloc;
#[cfg(any(feature = "std", test))]
extern crate std;

pub mod alarm;
pub mod nap;
pub mod random;
pub mod remote_button;
pub mod session;

pub use alarm::{Alarm, DismissPolicy, EndBehavior, Errors, LightProfile, Snooze, VolumeProfile};
pub use nap::{build_nap_payload, ramp_seconds_for_duration, select_template_alarm, NAP_ALARM_ID};
pub use remote_button::{ButtonError, ButtonResult, PairedButton};
pub use session::{
    DismissSource, RingingPhase, SessionConfig, SessionEffect, SessionError, SessionEvent,
    SessionStatus, WakeSession,
};
