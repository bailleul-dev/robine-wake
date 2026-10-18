//! Background alarm scheduler actor (ALM-001).
//!
//! Evaluates active alarm occurrences, triggers wake sessions within the catch-up window
//! when the clock is trusted, advances session ticks, and auto-disables one-shot alarms.

use chrono::{DateTime, Utc};
use serde_json::json;
use std::collections::HashSet;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use crate::clock::{Clock, ClockQuality};
use crate::events::EventStream;
use crate::session_manager::SessionManager;
use crate::store::Store;

pub struct Scheduler {
    store: Arc<Store>,
    clock: Arc<Clock>,
    sessions: Arc<SessionManager>,
    events: EventStream,
    notify: Arc<tokio::sync::Notify>,
    triggered: Mutex<HashSet<(String, DateTime<Utc>)>>,
}

impl Scheduler {
    pub fn new(
        store: Arc<Store>,
        clock: Arc<Clock>,
        sessions: Arc<SessionManager>,
        events: EventStream,
    ) -> Self {
        Self {
            store,
            clock,
            sessions,
            events,
            notify: Arc::new(tokio::sync::Notify::new()),
            triggered: Mutex::new(HashSet::new()),
        }
    }

    /// Wake up the scheduler loop immediately (e.g., when an alarm is added/updated/deleted).
    pub fn notify(&self) {
        self.notify.notify_one();
    }

    /// Whether the scheduler is armed (clock quality is trusted per ALM-001.7).
    pub fn is_armed(&self) -> bool {
        self.clock.quality() == ClockQuality::Trusted
    }

    /// Next scheduled occurrence across all enabled alarms.
    pub fn next_occurrence(&self, now: DateTime<Utc>) -> Option<(DateTime<Utc>, String)> {
        self.store
            .list()
            .iter()
            .filter(|alarm| alarm.enabled)
            .filter_map(|alarm| {
                alarm
                    .next_occurrence(now)
                    .map(|at| (at.with_timezone(&Utc), alarm.id.clone()))
            })
            .min()
    }

    /// Single scheduler step: advances active session ticks and triggers due alarms.
    /// Returns the next timestamp at which the scheduler should run.
    pub async fn step(&self, now: DateTime<Utc>) -> Option<DateTime<Utc>> {
        // 1. If a session is active, tick it (advances ramps, plateau escalation, snooze resume, timeouts)
        if self.sessions.active_snapshot().is_some() {
            self.sessions.tick(now).await;
        }

        let is_trusted = self.is_armed();
        let alarms = self.store.list();
        let mut next_wake_time: Option<DateTime<Utc>> = None;

        for alarm in alarms.iter().filter(|a| a.enabled) {
            // 2. Check previous occurrence for catch-up (< 5 min late) or missed (> 5 min late)
            if let Some(prev) = alarm.previous_occurrence(now) {
                let prev_target = prev.with_timezone(&Utc);
                let prev_key = (alarm.id.clone(), prev_target);

                let is_prev_triggered = {
                    let lock = self.triggered.lock().unwrap();
                    lock.contains(&prev_key)
                };

                if !is_prev_triggered && now <= prev_target + chrono::Duration::hours(24) {
                    let catchup_limit = prev_target + chrono::Duration::seconds(300);
                    if now <= catchup_limit {
                        if is_trusted {
                            {
                                let mut lock = self.triggered.lock().unwrap();
                                lock.insert(prev_key);
                            }
                            self.sessions.trigger_alarm(alarm, now).await.ok();
                            if alarm.days_of_week.is_empty() || alarm.one_shot_date.is_some() {
                                self.store.disable_alarm(&alarm.id, now).ok();
                                self.events.publish("state.changed", None);
                            }
                        }
                    } else {
                        // Late start beyond catch-up window (> 5 mins) -> record missed (ALM-001.6)
                        {
                            let mut lock = self.triggered.lock().unwrap();
                            lock.insert(prev_key);
                        }
                        let prev_start =
                            prev_target - chrono::Duration::seconds(alarm.prewake_seconds);
                        let missed_session = json!({
                            "id": format!("missed-{}", uuid::Uuid::new_v4()),
                            "alarm_id": alarm.id,
                            "scheduled_at": prev_start.to_rfc3339(),
                            "target_time": prev_target.to_rfc3339(),
                            "status": "missed",
                            "end_reason": "missed_catchup_window",
                            "ended_at": now.to_rfc3339(),
                        });
                        self.store.record_session(missed_session).ok();
                        if alarm.days_of_week.is_empty() || alarm.one_shot_date.is_some() {
                            self.store.disable_alarm(&alarm.id, now).ok();
                            self.events.publish("state.changed", None);
                        }
                    }
                }
            }

            // 3. Check upcoming occurrence
            let target_time = match alarm.next_occurrence(now) {
                Some(at) => at.with_timezone(&Utc),
                None => continue,
            };

            let start_time = target_time - chrono::Duration::seconds(alarm.prewake_seconds);
            let occurrence_key = (alarm.id.clone(), target_time);

            let is_already_triggered = {
                let lock = self.triggered.lock().unwrap();
                lock.contains(&occurrence_key)
            };

            if is_already_triggered {
                continue;
            }

            if now >= start_time {
                if is_trusted {
                    {
                        let mut lock = self.triggered.lock().unwrap();
                        lock.insert(occurrence_key);
                    }

                    self.sessions.trigger_alarm(alarm, now).await.ok();

                    // ALM-001.5: A one-shot alarm is disabled upon session creation
                    if alarm.days_of_week.is_empty() || alarm.one_shot_date.is_some() {
                        self.store.disable_alarm(&alarm.id, now).ok();
                        self.events.publish("state.changed", None);
                    }
                }
            } else {
                // Not yet due; track earliest future start
                next_wake_time = match next_wake_time {
                    Some(earliest) if start_time < earliest => Some(start_time),
                    None => Some(start_time),
                    Some(earliest) => Some(earliest),
                };
            }
        }

        // Clean up old triggered occurrences periodically (> 24h ago)
        {
            let mut lock = self.triggered.lock().unwrap();
            let cutoff = now - chrono::Duration::days(1);
            lock.retain(|(_, target)| *target > cutoff);
        }

        if self.sessions.active_snapshot().is_some() {
            Some(now + chrono::Duration::seconds(1))
        } else {
            next_wake_time
        }
    }

    /// Spawns the background scheduler actor loop.
    pub fn start(self: Arc<Self>) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move {
            let mut event_sub = self.events.subscribe(None);
            loop {
                let now = Utc::now();
                let next_step = self.step(now).await;

                let wait_duration = if self.sessions.active_snapshot().is_some() {
                    Duration::from_secs(1)
                } else if let Some(wake_at) = next_step {
                    let diff = (wake_at - now).to_std().unwrap_or(Duration::from_secs(0));
                    // Check at least every 60s for wall-clock jump detection (ALM-001)
                    diff.min(Duration::from_secs(60))
                } else {
                    Duration::from_secs(60)
                };

                tokio::select! {
                    _ = tokio::time::sleep(wait_duration) => {}
                    _ = self.notify.notified() => {}
                    _ = event_sub.receiver.recv() => {}
                }
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audio::AudioSink;
    use serde_json::Value;

    fn test_alarm(hour: u32, minute: u32, days: Vec<u8>) -> Value {
        json!({
            "id": format!("alarm-{hour}-{minute}"),
            "label": "Test Alarm",
            "enabled": true,
            "local_time": format!("{hour:02}:{minute:02}:00"),
            "days_of_week": days,
            "timezone": "Europe/Paris",
            "sound_id": "default",
            "strong_sound_id": "default",
            "prewake_seconds": 300,
            "volume_profile": { "start": 10, "ceiling": 80, "strong": 90, "ramp_seconds": 300 },
            "light_profile": { "enabled": false },
            "snooze": { "enabled": true, "duration_seconds": 300, "maximum": 3 },
            "dismiss_policy": "manual",
            "revision": 1
        })
    }

    #[tokio::test]
    async fn does_not_trigger_when_clock_is_untrusted() {
        let scratch = std::env::temp_dir().join(format!("sched-test-{}", uuid::Uuid::new_v4()));
        let store = Arc::new(Store::open(scratch.join("db.json"), |_| true));
        let audio = Arc::new(AudioSink::new());
        let events = EventStream::new();
        let sessions = Arc::new(SessionManager::new(audio, store.clone(), events.clone()));
        let clock = Arc::new(Clock::new()); // Untrusted by default in tests without confirm

        let scheduler = Arc::new(Scheduler::new(
            store.clone(),
            clock.clone(),
            sessions.clone(),
            events,
        ));

        let now = Utc::now();
        let alarm_val = test_alarm(8, 0, vec![1, 2, 3, 4, 5, 6, 7]);
        store.create(&alarm_val, now).unwrap();

        // Simulate step at exact target time
        let alarm = store.list().into_iter().next().unwrap();
        let target = alarm.next_occurrence(now).unwrap().with_timezone(&Utc);

        scheduler.step(target).await;

        // Alarm should NOT trigger because clock is untrusted (ALM-001.7)
        assert!(sessions.active_snapshot().is_none());
    }

    #[tokio::test]
    async fn triggers_when_clock_is_trusted_and_disables_oneshot() {
        let scratch = std::env::temp_dir().join(format!("sched-test-{}", uuid::Uuid::new_v4()));
        let store = Arc::new(Store::open(scratch.join("db.json"), |_| true));
        let audio = Arc::new(AudioSink::new());
        let events = EventStream::new();
        let sessions = Arc::new(SessionManager::new(
            audio.clone(),
            store.clone(),
            events.clone(),
        ));
        let clock = Arc::new(Clock::new());
        clock.confirm(); // Clock trusted

        let scheduler = Arc::new(Scheduler::new(
            store.clone(),
            clock.clone(),
            sessions.clone(),
            events,
        ));

        let now = Utc::now();
        // One-shot alarm (one_shot_date set, empty days_of_week)
        let target_date = (now + chrono::Duration::days(1))
            .format("%Y-%m-%d")
            .to_string();
        let mut alarm_val = test_alarm(8, 0, vec![]);
        alarm_val
            .as_object_mut()
            .unwrap()
            .insert("one_shot_date".into(), json!(target_date));
        let created = store.create(&alarm_val, now).unwrap();

        let target = created.next_occurrence(now).unwrap().with_timezone(&Utc);
        let start = target - chrono::Duration::seconds(300);

        scheduler.step(start).await;

        // Session must be active (ALM-001.1, ALM-002)
        assert!(sessions.active_snapshot().is_some());
        assert!(audio.is_playing());

        // One-shot alarm must be disabled (ALM-001.5)
        let updated = store
            .list()
            .into_iter()
            .find(|a| a.id == created.id)
            .unwrap();
        assert!(!updated.enabled);
    }

    #[tokio::test]
    async fn records_missed_beyond_catchup_window() {
        let scratch = std::env::temp_dir().join(format!("sched-test-{}", uuid::Uuid::new_v4()));
        let store = Arc::new(Store::open(scratch.join("db.json"), |_| true));
        let audio = Arc::new(AudioSink::new());
        let events = EventStream::new();
        let sessions = Arc::new(SessionManager::new(
            audio.clone(),
            store.clone(),
            events.clone(),
        ));
        let clock = Arc::new(Clock::new());
        clock.confirm();

        let scheduler = Arc::new(Scheduler::new(
            store.clone(),
            clock.clone(),
            sessions.clone(),
            events,
        ));

        let now = Utc::now();
        let alarm_val = test_alarm(8, 0, vec![1, 2, 3, 4, 5, 6, 7]);
        let created = store.create(&alarm_val, now).unwrap();

        let target = created.next_occurrence(now).unwrap().with_timezone(&Utc);
        // Simulate running 10 minutes past target (> 5 min catchup limit)
        let late = target + chrono::Duration::seconds(600);

        scheduler.step(late).await;

        // Should NOT trigger audio
        assert!(sessions.active_snapshot().is_none());
        assert!(!audio.is_playing());

        // Should record a missed session (ALM-001.6)
        let raw_sessions = store.raw("sessions");
        assert!(raw_sessions.as_array().is_some_and(|arr| !arr.is_empty()));
    }
}
