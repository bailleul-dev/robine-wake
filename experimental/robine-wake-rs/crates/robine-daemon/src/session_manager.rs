//! Wake session manager and effects executor (ALM-002).
//!
//! Orchestrates the active wake session lifecycle, coordinates state transitions
//! with the pure `robine_core::session::WakeSession` machine, executes effects
//! on audio, persistence, and SSE event streaming.

use chrono::{DateTime, Utc};
use robine_core::alarm::Alarm;
use robine_core::session::{
    DismissSource, SessionConfig, SessionEffect, SessionError, SessionEvent, SessionStatus,
    WakeSession,
};
use robine_ports::AudioPort;
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};

use crate::audio::AudioSink;
use crate::events::EventStream;
use crate::store::Store;

pub struct SessionManager {
    active: Arc<Mutex<Option<WakeSession>>>,
    audio: Arc<AudioSink>,
    store: Arc<Store>,
    events: EventStream,
}

impl SessionManager {
    pub fn new(audio: Arc<AudioSink>, store: Arc<Store>, events: EventStream) -> Self {
        Self {
            active: Arc::new(Mutex::new(None)),
            audio,
            store,
            events,
        }
    }

    /// Trigger a session from an alarm (manual or scheduled trigger).
    pub async fn trigger_alarm(&self, alarm: &Alarm, now: DateTime<Utc>) -> Result<Value, String> {
        {
            let active_lock = self.active.lock().unwrap();
            if let Some(existing) = &*active_lock {
                if matches!(
                    existing.status,
                    SessionStatus::Ringing | SessionStatus::Starting | SessionStatus::Snoozed
                ) {
                    return Ok(session_json(existing));
                }
            }
        }

        let session_id = format!("sess-{}", uuid::Uuid::new_v4());
        let correlation_id = format!("corr-{}", uuid::Uuid::new_v4());
        let target_time = alarm
            .next_occurrence(now)
            .map(|t| t.with_timezone(&Utc))
            .unwrap_or(now);

        let config = SessionConfig {
            alarm_id: alarm.id.clone(),
            correlation_id,
            target_time,
            prewake_seconds: alarm.prewake_seconds,
            sound_id: alarm.sound_id.clone(),
            strong_sound_id: alarm.strong_sound_id.clone(),
            start_gain: alarm.volume_profile.start,
            ceiling_gain: alarm.volume_profile.ceiling,
            strong_gain: alarm.volume_profile.strong,
            max_snoozes: alarm.snooze.maximum,
            snooze_duration_seconds: alarm.snooze.duration_seconds,
            // ALM-002.7: Remote dismissal gate is frozen at session start
            remote_dismiss_enabled: self.store.get_smartphone_dismiss_enabled(),
            light_target_id: alarm.light_profile.target_id.clone(),
        };

        let mut session = WakeSession::new(session_id, config, now);
        let effects = session
            .step(SessionEvent::Start, now)
            .map_err(|e| e.to_string())?;

        self.dispatch_effects(&session, effects).await;
        let snapshot = session_json(&session);
        *self.active.lock().unwrap() = Some(session);

        Ok(snapshot)
    }

    /// Snooze the currently active session (ALM-002).
    pub async fn snooze(&self, now: DateTime<Utc>) -> Result<Value, String> {
        let (effects, session_snap) = {
            let mut active_lock = self.active.lock().unwrap();
            let session = match active_lock.as_mut() {
                Some(s)
                    if matches!(s.status, SessionStatus::Ringing | SessionStatus::FailedSafe) =>
                {
                    s
                }
                _ => return Err("no_active_session".to_string()),
            };

            let effects = session
                .step(SessionEvent::Snooze, now)
                .map_err(|e| match e {
                    SessionError::MaxSnoozesReached => "max_snoozes_reached".to_string(),
                    other => other.to_string(),
                })?;
            (effects, session.clone())
        };

        self.dispatch_effects(&session_snap, effects).await;
        Ok(session_json(&session_snap))
    }

    /// Dismiss the currently active session (ALM-002).
    pub async fn dismiss(
        &self,
        source: DismissSource,
        now: DateTime<Utc>,
    ) -> Result<Value, String> {
        let (effects, session_snap) = {
            let mut active_lock = self.active.lock().unwrap();
            let session = match active_lock.as_mut() {
                Some(s)
                    if !matches!(s.status, SessionStatus::Dismissed | SessionStatus::TimedOut) =>
                {
                    s
                }
                _ => {
                    return Ok(json!({
                        "status": "ok",
                        "session": Value::Null,
                        "message": "already_dismissed"
                    }));
                }
            };

            let effects = session
                .step(SessionEvent::Dismiss { source }, now)
                .map_err(|e| match e {
                    SessionError::RemoteDismissDisabled => {
                        "smartphone_dismiss_disabled".to_string()
                    }
                    other => other.to_string(),
                })?;
            let snap = session.clone();
            // Remove active session from memory once dismissed
            *active_lock = None;
            (effects, snap)
        };

        self.dispatch_effects(&session_snap, effects).await;
        Ok(session_json(&session_snap))
    }

    /// Periodic tick to advance ramps, plateau escalation, snooze expiration, and timeout.
    pub async fn tick(&self, now: DateTime<Utc>) {
        let mut effects_to_run = Vec::new();
        let mut session_to_save: Option<WakeSession> = None;
        let mut should_clear = false;

        {
            let mut active_lock = self.active.lock().unwrap();
            if let Some(session) = active_lock.as_mut() {
                if let Ok(effects) = session.step(SessionEvent::Tick(now), now) {
                    effects_to_run = effects;
                    session_to_save = Some(session.clone());
                    if matches!(
                        session.status,
                        SessionStatus::Dismissed | SessionStatus::TimedOut
                    ) {
                        should_clear = true;
                    }
                }
            }
            if should_clear {
                *active_lock = None;
            }
        }

        if let Some(session) = session_to_save {
            self.dispatch_effects(&session, effects_to_run).await;
        }
    }

    /// Current snapshot of the active session, if any.
    pub fn active_snapshot(&self) -> Option<Value> {
        self.active.lock().unwrap().as_ref().map(session_json)
    }

    async fn dispatch_effects(&self, session: &WakeSession, effects: Vec<SessionEffect>) {
        for effect in effects {
            match effect {
                SessionEffect::PersistSession => {
                    let snapshot = session_json(session);
                    self.store.record_session(snapshot).ok();
                }
                SessionEffect::AudioPlay {
                    session_id,
                    sound_id,
                    gain,
                } => {
                    self.audio.play(&session_id, &sound_id, gain).await.ok();
                }
                SessionEffect::AudioSetGain { session_id, gain } => {
                    self.audio.set_gain(&session_id, gain).await.ok();
                }
                SessionEffect::AudioStop { session_id } => {
                    self.audio.stop(&session_id).await.ok();
                }
                SessionEffect::PublishEvent { event, data } => {
                    self.events.publish(&event, Some(data));
                }
            }
        }
    }
}

pub fn session_json(session: &WakeSession) -> Value {
    json!({
        "id": session.id,
        "alarm_id": session.config.alarm_id,
        "correlation_id": session.config.correlation_id,
        "status": session.status,
        "phase": session.phase,
        "current_gain": session.current_gain,
        "current_sound_id": session.current_sound_id,
        "snooze_count": session.snooze_count,
        "max_snoozes": session.config.max_snoozes,
        "scheduled_at": session.scheduled_at.to_rfc3339(),
        "target_time": session.config.target_time.to_rfc3339(),
        "started_at": session.started_at.map(|t| t.to_rfc3339()),
        "snoozed_until": session.snoozed_until.map(|t| t.to_rfc3339()),
        "ended_at": session.ended_at.map(|t| t.to_rfc3339()),
        "end_reason": session.end_reason,
        "total_ringing_seconds": session.total_ringing_seconds,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use robine_core::alarm::Alarm;

    fn test_alarm() -> Alarm {
        let input = json!({
            "id": "alarm-test",
            "label": "Test",
            "enabled": true,
            "local_time": "08:00:00",
            "days_of_week": [1, 2, 3, 4, 5],
            "timezone": "Europe/Paris",
            "sound_id": "default",
            "strong_sound_id": "default",
            "prewake_seconds": 600,
            "volume_profile": { "start": 10, "ceiling": 80, "strong": 90, "ramp_seconds": 600 },
            "light_profile": { "enabled": false },
            "snooze": { "enabled": true, "duration_seconds": 300, "maximum": 3 },
            "dismiss_policy": "manual",
            "revision": 1
        });
        Alarm::new(&input, Utc::now()).unwrap()
    }

    #[tokio::test]
    async fn triggers_snoozes_and_dismisses_session() {
        let scratch = std::env::temp_dir().join(format!("mgr-test-{}", uuid::Uuid::new_v4()));
        let store = Arc::new(Store::open(scratch.join("db.json"), |_| true));
        let audio = Arc::new(AudioSink::new());
        let events = EventStream::new();
        let manager = SessionManager::new(audio.clone(), store.clone(), events);

        let now = Utc::now();
        let alarm = test_alarm();

        // 1. Trigger session
        let started = manager.trigger_alarm(&alarm, now).await.unwrap();
        assert_eq!(started["status"], json!("ringing"));
        assert!(audio.is_playing());

        // 2. Snooze session
        let snoozed = manager.snooze(now).await.unwrap();
        assert_eq!(snoozed["status"], json!("snoozed"));
        assert_eq!(snoozed["snooze_count"], 1);
        assert!(!audio.is_playing());

        // 3. Resume ringing after snooze
        let resume_time = now + chrono::Duration::seconds(301);
        manager.tick(resume_time).await;
        assert_eq!(
            manager.active_snapshot().unwrap()["status"],
            json!("ringing")
        );
        assert!(audio.is_playing());

        // 4. Dismiss session
        let dismissed = manager
            .dismiss(DismissSource::Manual, resume_time)
            .await
            .unwrap();
        assert_eq!(dismissed["status"], json!("dismissed"));
        assert!(!audio.is_playing());
        assert!(manager.active_snapshot().is_none());
    }
}
