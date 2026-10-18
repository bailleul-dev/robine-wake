//! Robine Wake 2 port traits (PRD-002).
//!
//! Defines the abstract boundaries between domain logic and external systems:
//! Clock, Audio output, Storage, and Remote Button verification.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::future::Future;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClockQuality {
    Trusted,
    Untrusted,
}

pub trait ClockPort: Send + Sync {
    fn now(&self) -> DateTime<Utc>;
    fn quality(&self) -> ClockQuality;
    fn confirm(&self);
}

pub trait AudioPort: Send + Sync {
    fn play(
        &self,
        session_id: &str,
        sound_id: &str,
        gain: i64,
    ) -> impl Future<Output = Result<(), String>> + Send;

    fn set_gain(
        &self,
        session_id: &str,
        gain: i64,
    ) -> impl Future<Output = Result<(), String>> + Send;

    fn stop(&self, session_id: &str) -> impl Future<Output = Result<(), String>> + Send;
}

pub trait RemoteButtonPort: Send + Sync {
    /// Verify HMAC signature and monotonic counter anti-replay (ACC-002).
    fn verify_dismiss(
        &self,
        button_id: &str,
        counter: u64,
        signature_hex: &str,
    ) -> Result<bool, String>;
}
