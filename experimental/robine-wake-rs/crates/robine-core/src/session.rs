//! Pure wake session state machine (ALM-002).
//!
//! Orchestrates an alarm occurrence from trigger to completion:
//! gentle ramp, 5-minute plateau, escalation to strong sound, snooze counting,
//! remote dismiss safety gates, sound failure safe fallback, and safety timeout.
//!
//! Pure functional core: `(state, event, timestamp) -> Result<(new_state, effects), SessionError>`

use alloc::format;
use alloc::string::String;
use alloc::vec::Vec;
use core::fmt;

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use serde_json::json;

pub const SAFETY_TIMEOUT_SECONDS: i64 = 1800; // 30 minutes (ALM-002.10)
pub const PLATEAU_DURATION_SECONDS: i64 = 300; // 5 minutes (ALM-002.5)
pub const DEFAULT_SNOOZE_MAX: i64 = 3;
pub const DEFAULT_SNOOZE_DURATION_SECONDS: i64 = 480; // 8 minutes

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionStatus {
    Scheduled,
    Starting,
    Ringing,
    Snoozed,
    Dismissed,
    TimedOut,
    FailedSafe,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RingingPhase {
    Gentle,
    Plateau,
    Strong,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DismissSource {
    Manual,
    RemoteButton,
    RemoteApi,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionConfig {
    pub alarm_id: String,
    pub correlation_id: String,
    pub target_time: DateTime<Utc>,
    pub prewake_seconds: i64,
    pub sound_id: String,
    pub strong_sound_id: String,
    pub start_gain: i64,
    pub ceiling_gain: i64,
    pub strong_gain: i64,
    pub max_snoozes: i64,
    pub snooze_duration_seconds: i64,
    pub remote_dismiss_enabled: bool,
    pub light_target_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct WakeSession {
    pub id: String,
    pub config: SessionConfig,
    pub status: SessionStatus,
    pub phase: Option<RingingPhase>,
    pub current_gain: i64,
    pub current_sound_id: String,
    pub snooze_count: i64,
    pub scheduled_at: DateTime<Utc>,
    pub started_at: Option<DateTime<Utc>>,
    pub ringing_started_at: Option<DateTime<Utc>>,
    pub snoozed_until: Option<DateTime<Utc>>,
    pub ended_at: Option<DateTime<Utc>>,
    pub end_reason: Option<String>,
    pub total_ringing_seconds: i64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum SessionEvent {
    Start,
    Tick(DateTime<Utc>),
    Snooze,
    Dismiss { source: DismissSource },
    SoundFailed { reason: String },
    SoundRecovered,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum SessionEffect {
    PersistSession,
    AudioPlay {
        session_id: String,
        sound_id: String,
        gain: i64,
    },
    AudioSetGain {
        session_id: String,
        gain: i64,
    },
    AudioStop {
        session_id: String,
    },
    PublishEvent {
        event: String,
        data: serde_json::Value,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SessionError {
    AlreadyEnded,
    MaxSnoozesReached,
    RemoteDismissDisabled,
    InvalidTransition(String),
}

impl fmt::Display for SessionError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SessionError::AlreadyEnded => write!(f, "session already ended"),
            SessionError::MaxSnoozesReached => write!(f, "maximum snooze limit reached"),
            SessionError::RemoteDismissDisabled => write!(f, "remote dismissal is disabled"),
            SessionError::InvalidTransition(msg) => write!(f, "invalid transition: {msg}"),
        }
    }
}

impl core::error::Error for SessionError {}

impl WakeSession {
    pub fn new(id: impl Into<String>, config: SessionConfig, scheduled_at: DateTime<Utc>) -> Self {
        let sound_id = config.sound_id.clone();
        let start_gain = config.start_gain;
        Self {
            id: id.into(),
            config,
            status: SessionStatus::Scheduled,
            phase: None,
            current_gain: start_gain,
            current_sound_id: sound_id,
            snooze_count: 0,
            scheduled_at,
            started_at: None,
            ringing_started_at: None,
            snoozed_until: None,
            ended_at: None,
            end_reason: None,
            total_ringing_seconds: 0,
        }
    }

    /// Pure step transition: updates the session and generates ordered side effects.
    pub fn step(
        &mut self,
        event: SessionEvent,
        now: DateTime<Utc>,
    ) -> Result<Vec<SessionEffect>, SessionError> {
        let mut effects = Vec::new();

        match event {
            SessionEvent::Start => {
                if self.status != SessionStatus::Scheduled {
                    return Err(SessionError::InvalidTransition(format!(
                        "cannot start session in state {:?}",
                        self.status
                    )));
                }

                self.status = SessionStatus::Ringing;
                self.started_at = Some(now);
                self.ringing_started_at = Some(now);

                // Determine initial phase based on target_time
                if now < self.config.target_time {
                    self.phase = Some(RingingPhase::Gentle);
                    self.current_gain = self.config.start_gain;
                    self.current_sound_id = self.config.sound_id.clone();
                } else if now
                    < self.config.target_time + Duration::seconds(PLATEAU_DURATION_SECONDS)
                {
                    self.phase = Some(RingingPhase::Plateau);
                    self.current_gain = self.config.ceiling_gain;
                    self.current_sound_id = self.config.sound_id.clone();
                } else {
                    self.phase = Some(RingingPhase::Strong);
                    self.current_gain = self.config.strong_gain;
                    self.current_sound_id = self.config.strong_sound_id.clone();
                }

                // ALM-002.1: Session MUST be persisted before any audio effect
                effects.push(SessionEffect::PersistSession);

                effects.push(SessionEffect::AudioPlay {
                    session_id: self.id.clone(),
                    sound_id: self.current_sound_id.clone(),
                    gain: self.current_gain,
                });

                effects.push(SessionEffect::PublishEvent {
                    event: "session.started".into(),
                    data: json!({
                        "session_id": self.id,
                        "correlation_id": self.config.correlation_id,
                        "alarm_id": self.config.alarm_id,
                        "phase": self.phase,
                        "gain": self.current_gain,
                    }),
                });
            }

            SessionEvent::Tick(tick_now) => {
                match self.status {
                    SessionStatus::Ringing => {
                        // Track elapsed ringing time
                        if let Some(ringing_start) = self.ringing_started_at {
                            let elapsed = (tick_now - ringing_start).num_seconds();
                            if elapsed > 0 {
                                self.total_ringing_seconds += elapsed;
                                self.ringing_started_at = Some(tick_now);
                            }
                        }

                        // ALM-002.10: Safety timeout at 30 minutes
                        if self.total_ringing_seconds >= SAFETY_TIMEOUT_SECONDS {
                            self.status = SessionStatus::TimedOut;
                            self.ended_at = Some(tick_now);
                            self.end_reason = Some("timed_out".into());

                            effects.push(SessionEffect::AudioStop {
                                session_id: self.id.clone(),
                            });
                            effects.push(SessionEffect::PersistSession);
                            effects.push(SessionEffect::PublishEvent {
                                event: "session.timed_out".into(),
                                data: json!({
                                    "session_id": self.id,
                                    "total_ringing_seconds": self.total_ringing_seconds,
                                }),
                            });
                            return Ok(effects);
                        }

                        // Phase transitions and gain updates
                        match self.phase {
                            Some(RingingPhase::Gentle) => {
                                if tick_now >= self.config.target_time {
                                    // Gentle ramp completed -> enter 5-minute plateau
                                    self.phase = Some(RingingPhase::Plateau);
                                    self.current_gain = self.config.ceiling_gain;

                                    effects.push(SessionEffect::AudioSetGain {
                                        session_id: self.id.clone(),
                                        gain: self.current_gain,
                                    });
                                } else {
                                    // Calculate progress on the gentle ramp
                                    let new_gain = self.calculate_ramp_gain(tick_now);
                                    if new_gain != self.current_gain {
                                        self.current_gain = new_gain;
                                        effects.push(SessionEffect::AudioSetGain {
                                            session_id: self.id.clone(),
                                            gain: self.current_gain,
                                        });
                                    }
                                }
                            }
                            Some(RingingPhase::Plateau) => {
                                let plateau_end = self.config.target_time
                                    + Duration::seconds(PLATEAU_DURATION_SECONDS);
                                if tick_now >= plateau_end {
                                    // ALM-002.5: Escalate to strong sound after plateau
                                    self.phase = Some(RingingPhase::Strong);
                                    self.current_sound_id = self.config.strong_sound_id.clone();
                                    self.current_gain = self.config.strong_gain;

                                    effects.push(SessionEffect::AudioPlay {
                                        session_id: self.id.clone(),
                                        sound_id: self.current_sound_id.clone(),
                                        gain: self.current_gain,
                                    });
                                    effects.push(SessionEffect::PersistSession);
                                    effects.push(SessionEffect::PublishEvent {
                                        event: "gentle_wake_escalated".into(),
                                        data: json!({
                                            "session_id": self.id,
                                            "sound_id": self.current_sound_id,
                                            "gain": self.current_gain,
                                        }),
                                    });
                                }
                            }
                            Some(RingingPhase::Strong) => {
                                // Keep ringing at strong volume until timeout or dismiss
                            }
                            None => {}
                        }
                    }

                    SessionStatus::Snoozed => {
                        // Check if snooze period has expired
                        if let Some(until) = self.snoozed_until {
                            if tick_now >= until {
                                // Resume in Gentle phase with fresh ramp (ALM-002)
                                self.status = SessionStatus::Ringing;
                                self.phase = Some(RingingPhase::Gentle);
                                self.current_gain = self.config.start_gain;
                                self.current_sound_id = self.config.sound_id.clone();
                                self.ringing_started_at = Some(tick_now);
                                self.snoozed_until = None;

                                effects.push(SessionEffect::PersistSession);
                                effects.push(SessionEffect::AudioPlay {
                                    session_id: self.id.clone(),
                                    sound_id: self.current_sound_id.clone(),
                                    gain: self.current_gain,
                                });
                                effects.push(SessionEffect::PublishEvent {
                                    event: "session.resumed".into(),
                                    data: json!({
                                        "session_id": self.id,
                                        "snooze_count": self.snooze_count,
                                    }),
                                });
                            }
                        }
                    }

                    _ => {}
                }
            }

            SessionEvent::Snooze => {
                if matches!(
                    self.status,
                    SessionStatus::Dismissed | SessionStatus::TimedOut
                ) {
                    return Err(SessionError::AlreadyEnded);
                }

                // Idempotent if already snoozed
                if self.status == SessionStatus::Snoozed {
                    return Ok(effects);
                }

                if !matches!(
                    self.status,
                    SessionStatus::Ringing | SessionStatus::FailedSafe
                ) {
                    return Err(SessionError::InvalidTransition(format!(
                        "cannot snooze in state {:?}",
                        self.status
                    )));
                }

                // ALM-002.3: Snooze limit check
                if self.snooze_count >= self.config.max_snoozes {
                    return Err(SessionError::MaxSnoozesReached);
                }

                self.snooze_count += 1;
                self.status = SessionStatus::Snoozed;
                self.phase = None;
                self.snoozed_until =
                    Some(now + Duration::seconds(self.config.snooze_duration_seconds));
                self.ringing_started_at = None;

                effects.push(SessionEffect::AudioStop {
                    session_id: self.id.clone(),
                });
                effects.push(SessionEffect::PersistSession);
                effects.push(SessionEffect::PublishEvent {
                    event: "session.snoozed".into(),
                    data: json!({
                        "session_id": self.id,
                        "snooze_count": self.snooze_count,
                        "snoozed_until": self.snoozed_until.unwrap().to_rfc3339(),
                    }),
                });
            }

            SessionEvent::Dismiss { source } => {
                // ALM-002.2: Idempotent dismiss
                if self.status == SessionStatus::Dismissed {
                    return Ok(effects);
                }
                if self.status == SessionStatus::TimedOut {
                    return Ok(effects);
                }

                // ALM-002.7: Remote dismissal gate check
                if source == DismissSource::RemoteApi && !self.config.remote_dismiss_enabled {
                    return Err(SessionError::RemoteDismissDisabled);
                }

                self.status = SessionStatus::Dismissed;
                self.ended_at = Some(now);
                self.end_reason = Some("dismissed".into());
                self.phase = None;

                effects.push(SessionEffect::AudioStop {
                    session_id: self.id.clone(),
                });
                effects.push(SessionEffect::PersistSession);
                effects.push(SessionEffect::PublishEvent {
                    event: "session.dismissed".into(),
                    data: json!({
                        "session_id": self.id,
                        "source": source,
                        "ended_at": now.to_rfc3339(),
                    }),
                });
            }

            SessionEvent::SoundFailed { reason } => {
                if self.status == SessionStatus::Ringing {
                    self.status = SessionStatus::FailedSafe;

                    effects.push(SessionEffect::PersistSession);
                    effects.push(SessionEffect::PublishEvent {
                        event: "session.failed_safe".into(),
                        data: json!({
                            "session_id": self.id,
                            "reason": reason,
                        }),
                    });
                }
            }

            SessionEvent::SoundRecovered => {
                if self.status == SessionStatus::FailedSafe {
                    self.status = SessionStatus::Ringing;

                    effects.push(SessionEffect::PersistSession);
                    effects.push(SessionEffect::AudioPlay {
                        session_id: self.id.clone(),
                        sound_id: self.current_sound_id.clone(),
                        gain: self.current_gain,
                    });
                    effects.push(SessionEffect::PublishEvent {
                        event: "session.recovered".into(),
                        data: json!({
                            "session_id": self.id,
                        }),
                    });
                }
            }
        }

        Ok(effects)
    }

    /// Calculate gain on the gentle ramp towards target_time (ALM-002.6).
    fn calculate_ramp_gain(&self, now: DateTime<Utc>) -> i64 {
        let ramp_start = self.started_at.unwrap_or(now);
        let ramp_duration = (self.config.target_time - ramp_start).num_seconds();

        if ramp_duration <= 0 || now >= self.config.target_time {
            return self.config.ceiling_gain;
        }

        let elapsed = (now - ramp_start).num_seconds().max(0);
        let progress = (elapsed as f64) / (ramp_duration as f64);
        let start = self.config.start_gain as f64;
        let ceiling = self.config.ceiling_gain as f64;

        round(start + progress * (ceiling - start))
    }
}

/// `f64::round` lives in `std`; gains are never negative.
fn round(value: f64) -> i64 {
    (value + 0.5) as i64
}

#[cfg(test)]
mod tests {
    use std::prelude::rust_2021::*;
    use super::*;

    fn sample_config(target: DateTime<Utc>) -> SessionConfig {
        SessionConfig {
            alarm_id: "alarm-123".into(),
            correlation_id: "corr-456".into(),
            target_time: target,
            prewake_seconds: 1200, // 20 minutes
            sound_id: "gentle_forest".into(),
            strong_sound_id: "loud_bell".into(),
            start_gain: 15,
            ceiling_gain: 85,
            strong_gain: 95,
            max_snoozes: 3,
            snooze_duration_seconds: 480, // 8 minutes
            remote_dismiss_enabled: false,
            light_target_id: None,
        }
    }

    #[test]
    fn persists_session_before_audio_effect() {
        let now = Utc::now();
        let target = now + Duration::minutes(20);
        let mut session = WakeSession::new("sess-1", sample_config(target), now);

        let effects = session.step(SessionEvent::Start, now).unwrap();

        // ALM-002.1: PersistSession MUST precede AudioPlay
        let persist_idx = effects
            .iter()
            .position(|e| matches!(e, SessionEffect::PersistSession));
        let audio_idx = effects
            .iter()
            .position(|e| matches!(e, SessionEffect::AudioPlay { .. }));

        assert!(persist_idx.is_some());
        assert!(audio_idx.is_some());
        assert!(persist_idx.unwrap() < audio_idx.unwrap());
    }

    #[test]
    fn ramp_calculation_reaches_ceiling_at_target_time() {
        let start = Utc::now();
        let target = start + Duration::minutes(20);
        let mut session = WakeSession::new("sess-1", sample_config(target), start);

        session.step(SessionEvent::Start, start).unwrap();
        assert_eq!(session.current_gain, 15);
        assert_eq!(session.phase, Some(RingingPhase::Gentle));

        // Halfway through ramp (10 minutes)
        session
            .step(
                SessionEvent::Tick(start + Duration::minutes(10)),
                start + Duration::minutes(10),
            )
            .unwrap();
        assert_eq!(session.current_gain, 50);

        // At target time (20 minutes)
        session.step(SessionEvent::Tick(target), target).unwrap();
        assert_eq!(session.current_gain, 85);
        assert_eq!(session.phase, Some(RingingPhase::Plateau));
    }

    #[test]
    fn escalates_to_strong_sound_after_five_minute_plateau() {
        let start = Utc::now();
        let target = start + Duration::minutes(20);
        let mut session = WakeSession::new("sess-1", sample_config(target), start);

        session.step(SessionEvent::Start, start).unwrap();

        // Enter plateau at target time
        session.step(SessionEvent::Tick(target), target).unwrap();
        assert_eq!(session.phase, Some(RingingPhase::Plateau));
        assert_eq!(session.current_sound_id, "gentle_forest");

        // Plateau at 4 minutes: still gentle sound at ceiling
        let plateau_mid = target + Duration::minutes(4);
        session
            .step(SessionEvent::Tick(plateau_mid), plateau_mid)
            .unwrap();
        assert_eq!(session.phase, Some(RingingPhase::Plateau));

        // Plateau at 5 minutes: escalates to strong sound!
        let plateau_end = target + Duration::minutes(5);
        let effects = session
            .step(SessionEvent::Tick(plateau_end), plateau_end)
            .unwrap();

        assert_eq!(session.phase, Some(RingingPhase::Strong));
        assert_eq!(session.current_sound_id, "loud_bell");
        assert_eq!(session.current_gain, 95);

        let escalated_event = effects.iter().any(|e| match e {
            SessionEffect::PublishEvent { event, .. } => event == "gentle_wake_escalated",
            _ => false,
        });
        assert!(escalated_event);
    }

    #[test]
    fn enforces_snooze_limit() {
        let start = Utc::now();
        let target = start + Duration::minutes(20);
        let mut session = WakeSession::new("sess-1", sample_config(target), start);
        session.step(SessionEvent::Start, start).unwrap();

        // 3 snoozes allowed
        for i in 1..=3 {
            let res = session.step(SessionEvent::Snooze, start);
            assert!(res.is_ok());
            assert_eq!(session.snooze_count, i);

            // Resume
            let resume_time = session.snoozed_until.unwrap();
            session
                .step(SessionEvent::Tick(resume_time), resume_time)
                .unwrap();
            assert_eq!(session.status, SessionStatus::Ringing);
        }

        // 4th snooze rejected
        let res = session.step(SessionEvent::Snooze, start);
        assert_eq!(res, Err(SessionError::MaxSnoozesReached));
        assert_eq!(session.status, SessionStatus::Ringing);
    }

    #[test]
    fn enforces_remote_dismissal_gate() {
        let start = Utc::now();
        let target = start + Duration::minutes(20);
        let mut session = WakeSession::new("sess-1", sample_config(target), start);
        session.step(SessionEvent::Start, start).unwrap();

        // RemoteApi dismissal refused when remote_dismiss_enabled is false
        let res = session.step(
            SessionEvent::Dismiss {
                source: DismissSource::RemoteApi,
            },
            start,
        );
        assert_eq!(res, Err(SessionError::RemoteDismissDisabled));
        assert_eq!(session.status, SessionStatus::Ringing);

        // RemoteButton dismissal accepted
        let res = session.step(
            SessionEvent::Dismiss {
                source: DismissSource::RemoteButton,
            },
            start,
        );
        assert!(res.is_ok());
        assert_eq!(session.status, SessionStatus::Dismissed);

        // Dismissal is idempotent
        let res2 = session.step(
            SessionEvent::Dismiss {
                source: DismissSource::Manual,
            },
            start,
        );
        assert!(res2.is_ok());
    }

    #[test]
    fn triggers_safety_timeout_at_thirty_minutes() {
        let start = Utc::now();
        let target = start + Duration::minutes(10);
        let mut session = WakeSession::new("sess-1", sample_config(target), start);
        session.step(SessionEvent::Start, start).unwrap();

        // Tick 30 minutes later (1800s)
        let timeout_time = start + Duration::seconds(1800);
        session
            .step(SessionEvent::Tick(timeout_time), timeout_time)
            .unwrap();

        assert_eq!(session.status, SessionStatus::TimedOut);
        assert_eq!(session.end_reason, Some("timed_out".into()));
    }
}
