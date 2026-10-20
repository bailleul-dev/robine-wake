//! Robine Wake v1 command protocol (API-002), shared by every device build.
//!
//! Port of `RobineWake.Bluetooth.Command` restricted to sleep alarms, naps and
//! the authenticated remote button: the envelopes, operation names, body
//! shapes and error codes are those of the Elixir application, so the mobile
//! app and the remote button firmware talk to it unchanged.
//!
//! The crate is `no_std + alloc` and does no I/O. The caller owns the clock,
//! the network and the storage: it passes a [`Context`] to every call and
//! applies the returned [`Outcome`] (persist the snapshot, publish events).

#![no_std]

extern crate alloc;
#[cfg(test)]
extern crate std;

mod breathing;
mod command;
mod dawn;
mod device;
mod dto;
mod light;
mod sunset;
pub mod sounds;

use alloc::vec::Vec;
use chrono::{DateTime, Utc};

pub use breathing::{Breathing, Cadence};
pub use dawn::Dawn;
pub use device::{AudioOutput, Device, SnapshotError};
pub use light::{
    Easing, LightFade, LightLevel, LightScene, Rgb, MAX_PROGRAM_MS, MAX_TRANSITION_MS, PROGRAM_MAX_BRIGHTNESS,
};
pub use sounds::Sound;
pub use sunset::Sunset;

/// Port of the HTTP command endpoint, shared with the Raspberry Pi build.
pub const DEFAULT_HTTP_PORT: u16 = 4000;

/// Server-sent event names understood by the mobile app.
pub const STATE_CHANGED: &str = "state.changed";
pub const SESSION_CHANGED: &str = "session.changed";

/// Static description of the device running the protocol.
#[derive(Clone, Debug)]
pub struct Platform {
    /// Hardware target reported in `state.get` (`esp32`, `rpi3`, …).
    pub target: &'static str,
    pub firmware_version: &'static str,
    pub http_port: u16,
    /// Sounds an alarm may reference, besides `default`.
    pub sounds: &'static [Sound],
    /// Whether a smartphone may stop a real (non-test) alarm. Off in
    /// production: the sleeper has to get up and press the remote button.
    pub remote_dismiss_enabled: bool,
    /// Whether the device can play sound at all.
    pub audio_available: bool,
    /// Name of a light wired to the device, which enables `light.set` and
    /// `light.get`.
    pub light: Option<&'static str>,
}

/// Per-call view of the outside world.
#[derive(Clone, Copy, Debug)]
pub struct Context {
    pub now: DateTime<Utc>,
    /// Monotonic milliseconds, immune to clock corrections.
    pub monotonic_ms: u64,
    /// Whether `now` comes from NTP or a manual confirmation.
    pub clock_trusted: bool,
    /// Current IPv4 address, advertised as the HTTP endpoint.
    pub ipv4: Option<[u8; 4]>,
}

/// Side effects the caller must apply after a call.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Outcome {
    /// The persistent snapshot changed and must be saved.
    pub persist: bool,
    /// Events to publish to the server-sent event stream, in order.
    pub events: Vec<&'static str>,
    /// `clock.confirm` asked to trust the current time.
    pub clock_confirmed: bool,
}

impl Outcome {
    fn changed(&mut self, event: &'static str) {
        self.persist = true;
        self.publish(event);
    }

    fn publish(&mut self, event: &'static str) {
        if !self.events.contains(&event) {
            self.events.push(event);
        }
    }

    fn merge(&mut self, other: Outcome) {
        self.persist |= other.persist;
        self.clock_confirmed |= other.clock_confirmed;
        for event in other.events {
            self.publish(event);
        }
    }
}
