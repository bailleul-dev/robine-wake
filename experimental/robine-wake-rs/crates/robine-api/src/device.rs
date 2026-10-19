//! Device state: alarms, wake sessions, remote buttons and the scheduler.
//!
//! Ports `RobineWake.Settings`, `Scheduler`, `WakeSession`, `Nap` and
//! `RemoteButton`, keeping their rules (revisions, catch-up window, one-shot
//! alarms, smartphone dismiss gate, counter anti-replay).

use alloc::collections::BTreeMap;
use alloc::string::{String, ToString};
use alloc::vec::Vec;

use chrono::{DateTime, Duration, Timelike, Utc};
use robine_core::session::PLATEAU_DURATION_SECONDS;
use robine_core::{
    Alarm, DismissSource, Errors, RingingPhase, SessionConfig, SessionError, SessionEvent,
    SessionStatus, WakeSession,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};

use crate::command::CommandCache;
use crate::dto::{self, iso8601};
use crate::light::LightFade;
use crate::{Context, Outcome, Platform, SESSION_CHANGED, STATE_CHANGED};

/// A missed occurrence still rings if the device catches up within this delay.
const CATCH_UP_SECONDS: i64 = 300;
/// Wake sessions kept in the persistent history.
const MAX_HISTORY: usize = 20;
/// Alarms the persistent snapshot is sized for.
const MAX_ALARMS: usize = 24;
const SNAPSHOT_VERSION: u32 = 1;

const MAC_DOMAIN: &str = "rw-remote-v1";
const MAX_COUNTER: u64 = 9_007_199_254_740_991;
const MIN_PAIRING_SECONDS: u64 = 30;
const MAX_PAIRING_SECONDS: u64 = 300;

/// Error of an operation: a code, or field messages (`validation_failed`).
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Error {
    Code(&'static str),
    Validation(Errors),
}

impl From<Errors> for Error {
    fn from(errors: Errors) -> Self {
        Error::Validation(errors)
    }
}

pub(crate) type Result<T> = core::result::Result<T, Error>;

fn validation(field: &str, message: &str) -> Error {
    Error::Validation(BTreeMap::from([(field.to_string(), message.to_string())]))
}

/// Who asked to stop the alarm.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum DismissOrigin {
    Smartphone,
    RemoteButton,
}

impl DismissOrigin {
    fn reason(self) -> &'static str {
        match self {
            DismissOrigin::Smartphone => "smartphone",
            DismissOrigin::RemoteButton => "remote_button",
        }
    }
}

/// What the speaker should play right now.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct AudioOutput<'a> {
    pub sound_id: &'a str,
    /// Gain in percent of the safety ceiling.
    pub gain: i64,
}

/// The persistent snapshot could not be decoded.
#[derive(Debug)]
pub struct SnapshotError;

#[derive(Clone, Debug, Serialize, Deserialize)]
struct SessionRecord {
    id: String,
    alarm_id: String,
    scheduled_for: DateTime<Utc>,
    created_at: DateTime<Utc>,
    state: String,
    #[serde(default)]
    test_mode: bool,
    #[serde(default)]
    snooze_count: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    terminal_reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    ended_at: Option<DateTime<Utc>>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct ButtonRecord {
    id: String,
    name: String,
    secret_hex: String,
    last_counter: u64,
    paired_at: DateTime<Utc>,
    #[serde(default)]
    last_seen_at: Option<DateTime<Utc>>,
}

#[derive(Serialize, Deserialize)]
struct Snapshot {
    version: u32,
    alarms: Vec<Alarm>,
    sessions: Vec<SessionRecord>,
    buttons: Vec<ButtonRecord>,
    smartphone_dismiss_enabled: bool,
}

struct ActiveSession {
    core: WakeSession,
    alarm: Alarm,
    test_mode: bool,
    smartphone_dismiss_allowed: bool,
    created_at: DateTime<Utc>,
}

struct ScheduleEntry {
    alarm_id: String,
    scheduled_for: DateTime<Utc>,
    starts_at: DateTime<Utc>,
}

struct Pairing {
    deadline_ms: u64,
    expires_at: DateTime<Utc>,
}

/// A session that was ringing when the device restarted.
struct Recovery {
    alarm_id: String,
    scheduled_for: DateTime<Utc>,
}

pub struct Device {
    pub(crate) platform: Platform,
    alarms: Vec<Alarm>,
    sessions: Vec<SessionRecord>,
    buttons: Vec<ButtonRecord>,
    smartphone_dismiss_enabled: bool,
    active: Option<ActiveSession>,
    schedule: Vec<ScheduleEntry>,
    pairing: Option<Pairing>,
    recovery: Option<Recovery>,
    pub(crate) light: Option<LightFade>,
    pub(crate) cache: CommandCache,
}

impl Device {
    pub fn new(platform: Platform) -> Self {
        Self {
            platform,
            alarms: Vec::new(),
            sessions: Vec::new(),
            buttons: Vec::new(),
            smartphone_dismiss_enabled: false,
            active: None,
            schedule: Vec::new(),
            pairing: None,
            recovery: None,
            light: None,
            cache: CommandCache::default(),
        }
    }

    /// Restores the state saved by [`Device::snapshot`]. A session that was
    /// still ringing is marked interrupted and rings again on the next
    /// trusted tick.
    pub fn restore(platform: Platform, snapshot: &[u8]) -> core::result::Result<Self, SnapshotError> {
        let snapshot: Snapshot = serde_json::from_slice(snapshot).map_err(|_| SnapshotError)?;
        if snapshot.version != SNAPSHOT_VERSION {
            return Err(SnapshotError);
        }
        let mut device = Self::new(platform);
        device.alarms = snapshot.alarms;
        device.sessions = snapshot.sessions;
        device.buttons = snapshot.buttons;
        device.smartphone_dismiss_enabled = snapshot.smartphone_dismiss_enabled;

        if let Some(record) = device
            .sessions
            .iter_mut()
            .find(|record| record.ended_at.is_none() && !is_terminal(&record.state))
        {
            if !record.test_mode {
                device.recovery = Some(Recovery {
                    alarm_id: record.alarm_id.clone(),
                    scheduled_for: record.scheduled_for,
                });
            }
            record.state = "interrupted".into();
            record.terminal_reason = Some("restart".into());
        }
        Ok(device)
    }

    /// JSON snapshot of everything that must survive a restart.
    pub fn snapshot(&self) -> Vec<u8> {
        let snapshot = Snapshot {
            version: SNAPSHOT_VERSION,
            alarms: self.alarms.clone(),
            sessions: self.sessions.clone(),
            buttons: self.buttons.clone(),
            smartphone_dismiss_enabled: self.smartphone_dismiss_enabled,
        };
        serde_json::to_vec(&snapshot).expect("snapshot always serializes")
    }

    /// What the speaker should play, if an alarm is audible.
    pub fn audio(&self) -> Option<AudioOutput<'_>> {
        let active = self.active.as_ref()?;
        matches!(active.core.status, SessionStatus::Ringing | SessionStatus::FailedSafe).then(|| {
            AudioOutput {
                sound_id: &active.core.current_sound_id,
                gain: active.core.current_gain,
            }
        })
    }

    // ----- Scheduler (`RobineWake.Scheduler`) -------------------------------

    /// Recomputes the next occurrence of every enabled alarm. Call it after
    /// the clock becomes trusted or jumps.
    pub fn refresh_schedule(&mut self, ctx: &Context) {
        self.schedule.clear();
        for alarm in self.alarms.iter().filter(|alarm| alarm.enabled) {
            let from = ctx.now - Duration::seconds(CATCH_UP_SECONDS + alarm.prewake_seconds);
            if let Some(occurrence) = alarm.next_occurrence(from) {
                self.schedule.push(entry_for(alarm, occurrence.with_timezone(&Utc)));
            }
        }
    }

    /// Advances the scheduler and the active session. Call it about once a
    /// second.
    pub fn tick(&mut self, ctx: &Context) -> Outcome {
        let mut out = Outcome::default();
        if ctx.clock_trusted {
            self.recover(ctx, &mut out);
            let now = ctx.now;
            let (due, pending): (Vec<_>, Vec<_>) = core::mem::take(&mut self.schedule)
                .into_iter()
                .partition(|entry| entry.starts_at <= now);
            self.schedule = pending;
            for entry in due {
                self.fire(entry, ctx, &mut out);
            }
        }
        self.tick_session(ctx, &mut out);
        if self
            .pairing
            .as_ref()
            .is_some_and(|pairing| ctx.monotonic_ms >= pairing.deadline_ms)
        {
            self.pairing = None;
        }
        out
    }

    fn fire(&mut self, entry: ScheduleEntry, ctx: &Context, out: &mut Outcome) {
        let Some(alarm) = self.alarm(&entry.alarm_id).cloned() else {
            return;
        };

        if self.session_recorded(&alarm.id, entry.scheduled_for) {
            // Already rang, e.g. before a restart.
        } else if (ctx.now - entry.scheduled_for).num_seconds() > CATCH_UP_SECONDS {
            self.record_missed(&alarm, entry.scheduled_for, "catch_up_expired", ctx, out);
        } else if self
            .start_session(alarm.clone(), entry.scheduled_for, false, false, ctx, out)
            .is_ok()
        {
            if alarm.one_shot_date.is_some() {
                self.disable_alarm(&alarm.id, out);
            }
        } else {
            self.record_missed(&alarm, entry.scheduled_for, "another_session_active", ctx, out);
        }

        if alarm.enabled && alarm.one_shot_date.is_none() {
            if let Some(next) = alarm.next_occurrence(entry.scheduled_for + Duration::seconds(1)) {
                self.schedule.push(entry_for(&alarm, next.with_timezone(&Utc)));
            }
        }
    }

    fn recover(&mut self, ctx: &Context, out: &mut Outcome) {
        let Some(recovery) = self.recovery.take() else {
            return;
        };
        let Some(alarm) = self.alarm(&recovery.alarm_id).cloned() else {
            return;
        };
        let still_relevant = (ctx.now - recovery.scheduled_for).num_seconds()
            < robine_core::session::SAFETY_TIMEOUT_SECONDS;
        if still_relevant {
            let _ = self.start_session(alarm, recovery.scheduled_for, false, false, ctx, out);
        }
    }

    fn session_recorded(&self, alarm_id: &str, scheduled_for: DateTime<Utc>) -> bool {
        self.sessions
            .iter()
            .any(|record| record.alarm_id == alarm_id && record.scheduled_for == scheduled_for)
    }

    fn record_missed(
        &mut self,
        alarm: &Alarm,
        scheduled_for: DateTime<Utc>,
        reason: &str,
        ctx: &Context,
        out: &mut Outcome,
    ) {
        let now = seconds(ctx.now);
        self.push_record(SessionRecord {
            id: robine_core::alarm::generate_id(),
            alarm_id: alarm.id.clone(),
            scheduled_for,
            created_at: now,
            state: "missed".into(),
            test_mode: false,
            snooze_count: 0,
            terminal_reason: Some(reason.into()),
            ended_at: Some(now),
        });
        if alarm.one_shot_date.is_some() {
            self.disable_alarm(&alarm.id, out);
        }
        out.changed(STATE_CHANGED);
    }

    fn disable_alarm(&mut self, alarm_id: &str, out: &mut Outcome) {
        if let Some(alarm) = self.alarms.iter_mut().find(|alarm| alarm.id == alarm_id) {
            alarm.enabled = false;
            alarm.revision += 1;
            out.changed(STATE_CHANGED);
        }
    }

    // ----- Alarms (`RobineWake.Settings`) -----------------------------------

    pub(crate) fn alarms(&self) -> &[Alarm] {
        &self.alarms
    }

    pub(crate) fn alarm(&self, id: &str) -> Option<&Alarm> {
        self.alarms.iter().find(|alarm| alarm.id == id)
    }

    pub(crate) fn create_alarm(&mut self, attrs: &Value, ctx: &Context, out: &mut Outcome) -> Result<Alarm> {
        let alarm = Alarm::new(attrs, seconds(ctx.now))?;
        self.validate_sounds(&alarm)?;
        if self.alarm(&alarm.id).is_some() {
            return Err(Error::Code("already_exists"));
        }
        if self.alarms.len() >= MAX_ALARMS {
            return Err(validation("alarm", "the device holds at most 24 alarms"));
        }
        self.alarms.push(alarm.clone());
        self.alarm_changed(ctx, out);
        Ok(alarm)
    }

    pub(crate) fn update_alarm(
        &mut self,
        id: &str,
        attrs: &Map<String, Value>,
        ctx: &Context,
        out: &mut Outcome,
    ) -> Result<Alarm> {
        let index = self.alarm_index(id)?;
        let current = &self.alarms[index];
        check_revision(current, attrs.get("revision"))?;

        let mut merged = current.to_map();
        for (key, value) in attrs {
            merged.insert(key.clone(), value.clone());
        }
        merged.insert("revision".into(), json!(current.revision + 1));
        let alarm = Alarm::new(&Value::Object(merged), seconds(ctx.now))?;
        self.validate_sounds(&alarm)?;

        self.alarms[index] = alarm.clone();
        self.alarm_changed(ctx, out);
        Ok(alarm)
    }

    pub(crate) fn delete_alarm(&mut self, id: &str, revision: &Value, ctx: &Context, out: &mut Outcome) -> Result<()> {
        let index = self.alarm_index(id)?;
        check_revision(&self.alarms[index], Some(revision))?;
        self.alarms.remove(index);
        self.alarm_changed(ctx, out);
        Ok(())
    }

    fn alarm_index(&self, id: &str) -> Result<usize> {
        self.alarms
            .iter()
            .position(|alarm| alarm.id == id)
            .ok_or(Error::Code("not_found"))
    }

    fn alarm_changed(&mut self, ctx: &Context, out: &mut Outcome) {
        self.refresh_schedule(ctx);
        out.changed(STATE_CHANGED);
    }

    fn validate_sounds(&self, alarm: &Alarm) -> Result<()> {
        if !self.sound_available(&alarm.sound_id) {
            return Err(validation("sound_id", "does not reference an available validated sound"));
        }
        if !self.sound_available(&alarm.strong_sound_id) {
            return Err(validation(
                "strong_sound_id",
                "does not reference an available validated sound",
            ));
        }
        Ok(())
    }

    fn sound_available(&self, id: &str) -> bool {
        id == "default" || self.platform.sounds.iter().any(|sound| sound.id == id)
    }

    // ----- Nap (`RobineWake.Nap`) --------------------------------------------

    pub(crate) fn start_nap(&mut self, minutes: &Value, ctx: &Context, out: &mut Outcome) -> Result<Alarm> {
        let minutes = minutes
            .as_u64()
            .filter(|minutes| (1..=u64::from(robine_core::nap::MAXIMUM_MINUTES)).contains(minutes))
            .ok_or_else(|| validation("duration_minutes", "must be between 1 and 180"))?;
        let template = robine_core::select_template_alarm(&self.alarms).cloned();
        let payload = robine_core::build_nap_payload(minutes as u32, template.as_ref(), ctx.now)?;

        match self.alarm(robine_core::NAP_ALARM_ID).map(|nap| nap.revision) {
            Some(revision) => {
                let mut attrs = payload.as_object().cloned().unwrap_or_default();
                attrs.insert("revision".into(), json!(revision));
                self.update_alarm(robine_core::NAP_ALARM_ID, &attrs, ctx, out)
            }
            None => self.create_alarm(&payload, ctx, out),
        }
    }

    pub(crate) fn cancel_nap(&mut self, ctx: &Context, out: &mut Outcome) -> Result<()> {
        match self.alarm(robine_core::NAP_ALARM_ID).map(|nap| nap.revision) {
            Some(revision) => self.delete_alarm(robine_core::NAP_ALARM_ID, &json!(revision), ctx, out),
            None => Ok(()),
        }
    }

    // ----- Wake sessions (`RobineWake.WakeSession`) --------------------------

    pub(crate) fn start_session(
        &mut self,
        alarm: Alarm,
        scheduled_for: DateTime<Utc>,
        test_mode: bool,
        strong: bool,
        ctx: &Context,
        out: &mut Outcome,
    ) -> Result<()> {
        if self.active.is_some() {
            return Err(Error::Code("active_session"));
        }
        let now = seconds(ctx.now);
        let id = robine_core::alarm::generate_id();
        let smartphone_dismiss_allowed = test_mode || self.smartphone_dismiss_enabled;
        // The core starts in the strong phase once the plateau after the
        // target time is over.
        let target_time = if strong {
            now - Duration::seconds(PLATEAU_DURATION_SECONDS + 1)
        } else {
            scheduled_for
        };
        let config = SessionConfig {
            alarm_id: alarm.id.clone(),
            correlation_id: id.clone(),
            target_time,
            prewake_seconds: alarm.prewake_seconds,
            sound_id: alarm.sound_id.clone(),
            strong_sound_id: alarm.strong_sound_id.clone(),
            start_gain: alarm.volume_profile.start,
            ceiling_gain: alarm.volume_profile.ceiling,
            strong_gain: alarm.volume_profile.strong,
            max_snoozes: if alarm.snooze.enabled { alarm.snooze.maximum } else { 0 },
            snooze_duration_seconds: alarm.snooze.duration_seconds,
            remote_dismiss_enabled: smartphone_dismiss_allowed,
            light_target_id: alarm.light_profile.target_id.clone(),
        };
        let mut core = WakeSession::new(id.clone(), config, scheduled_for);
        core.step(SessionEvent::Start, now)
            .map_err(|_| Error::Code("invalid_state"))?;

        self.push_record(SessionRecord {
            id,
            alarm_id: alarm.id.clone(),
            scheduled_for,
            created_at: now,
            state: status_text(core.status).into(),
            test_mode,
            snooze_count: 0,
            terminal_reason: None,
            ended_at: None,
        });
        self.active = Some(ActiveSession {
            core,
            alarm,
            test_mode,
            smartphone_dismiss_allowed,
            created_at: now,
        });
        out.changed(SESSION_CHANGED);
        Ok(())
    }

    pub(crate) fn trigger_alarm(&mut self, id: &str, strong: bool, ctx: &Context, out: &mut Outcome) -> Result<()> {
        let alarm = self.alarm(id).cloned().ok_or(Error::Code("not_found"))?;
        let scheduled_for = if strong {
            seconds(ctx.now)
        } else {
            seconds(ctx.now) + Duration::seconds(alarm.prewake_seconds)
        };
        self.start_session(alarm, scheduled_for, true, strong, ctx, out)
    }

    fn tick_session(&mut self, ctx: &Context, out: &mut Outcome) {
        let now = seconds(ctx.now);
        let Some(active) = self.active.as_mut() else {
            return;
        };
        let before = (active.core.status, active.core.phase);
        let _ = active.core.step(SessionEvent::Tick(now), now);
        let after = (active.core.status, active.core.phase);
        if before == after {
            return;
        }
        if after.0 == SessionStatus::TimedOut {
            self.finish("timed_out", now, out);
        } else {
            let state = status_text(after.0);
            let id = active.core.id.clone();
            self.update_record(&id, |record| record.state = state.into());
            out.changed(SESSION_CHANGED);
        }
    }

    pub(crate) fn snooze(&mut self, ctx: &Context, out: &mut Outcome) -> Result<Value> {
        let now = seconds(ctx.now);
        let active = self.active.as_mut().ok_or(Error::Code("no_active_session"))?;
        if active.core.status == SessionStatus::Snoozed {
            return Ok(session_dto(active, None, None));
        }
        if !active.alarm.snooze.enabled {
            return Err(Error::Code("snooze_disabled"));
        }
        active.core.step(SessionEvent::Snooze, now).map_err(|error| match error {
            SessionError::MaxSnoozesReached => Error::Code("snooze_limit"),
            SessionError::AlreadyEnded => Error::Code("no_active_session"),
            _ => Error::Code("invalid_state"),
        })?;

        let dto = session_dto(active, None, None);
        let (id, count) = (active.core.id.clone(), active.core.snooze_count);
        self.update_record(&id, |record| {
            record.state = "snoozed".into();
            record.snooze_count = count;
        });
        out.changed(SESSION_CHANGED);
        Ok(dto)
    }

    pub(crate) fn dismiss(&mut self, origin: DismissOrigin, ctx: &Context, out: &mut Outcome) -> Result<Value> {
        let now = seconds(ctx.now);
        let Some(active) = self.active.as_mut() else {
            return Ok(json!({ "state": "idle", "terminal_reason": "already_inactive" }));
        };
        let gated = !self.platform.remote_dismiss_enabled || !active.smartphone_dismiss_allowed;
        if origin == DismissOrigin::Smartphone && !active.test_mode && gated {
            return Err(Error::Code("smartphone_dismiss_disabled"));
        }
        // The gate above is the Elixir one; the core only records the stop.
        let _ = active.core.step(SessionEvent::Dismiss { source: DismissSource::Manual }, now);
        Ok(self.finish(origin.reason(), now, out))
    }

    fn finish(&mut self, reason: &str, now: DateTime<Utc>, out: &mut Outcome) -> Value {
        let active = self.active.take().expect("finish requires an active session");
        let state = status_text(active.core.status);
        let snooze_count = active.core.snooze_count;
        self.update_record(&active.core.id, |record| {
            record.state = state.into();
            record.terminal_reason = Some(reason.into());
            record.ended_at = Some(now);
            record.snooze_count = snooze_count;
        });
        out.changed(SESSION_CHANGED);
        session_dto(&active, Some(reason), Some(now))
    }

    pub(crate) fn active_session(&self) -> Value {
        self.active
            .as_ref()
            .map_or(Value::Null, |active| session_dto(active, None, None))
    }

    pub(crate) fn recent_sessions(&self, limit: usize) -> Vec<Value> {
        self.sessions
            .iter()
            .take(limit)
            .map(|record| match serde_json::to_value(record) {
                Ok(Value::Object(map)) => dto::select(&map, dto::SESSION_KEYS),
                _ => Value::Null,
            })
            .collect()
    }

    pub(crate) fn erase_history(&mut self, out: &mut Outcome) {
        let active_id = self.active.as_ref().map(|active| active.core.id.clone());
        self.sessions.retain(|record| Some(&record.id) == active_id.as_ref());
        out.changed(STATE_CHANGED);
    }

    fn push_record(&mut self, record: SessionRecord) {
        self.sessions.insert(0, record);
        self.sessions.truncate(MAX_HISTORY);
    }

    fn update_record(&mut self, id: &str, update: impl FnOnce(&mut SessionRecord)) {
        if let Some(record) = self.sessions.iter_mut().find(|record| record.id == id) {
            update(record);
        }
    }

    // ----- Smartphone dismiss setting ----------------------------------------

    pub(crate) fn smartphone_dismiss(&self) -> Value {
        json!({
            "enabled": self.smartphone_dismiss_enabled,
            "locked": self.smartphone_dismiss_locked(),
        })
    }

    fn smartphone_dismiss_locked(&self) -> bool {
        !self.platform.remote_dismiss_enabled || self.active.is_some()
    }

    pub(crate) fn set_smartphone_dismiss(&mut self, enabled: bool, out: &mut Outcome) -> Result<Value> {
        if self.smartphone_dismiss_locked() {
            return Err(Error::Code("smartphone_dismiss_setting_locked"));
        }
        self.smartphone_dismiss_enabled = enabled;
        out.changed(STATE_CHANGED);
        Ok(json!({ "enabled": enabled, "locked": false }))
    }

    // ----- Remote button (`RobineWake.RemoteButton`) -------------------------

    pub(crate) fn remote_button_status(&self, ctx: &Context) -> Value {
        let pairing_active = self.pairing_active(ctx);
        let mut buttons: Vec<&ButtonRecord> = self.buttons.iter().collect();
        buttons.sort_by(|left, right| (&left.name, &left.id).cmp(&(&right.name, &right.id)));
        let buttons: Vec<Value> = buttons
            .into_iter()
            .map(|button| {
                json!({
                    "id": button.id,
                    "name": button.name,
                    "last_counter": button.last_counter,
                    "paired_at": iso8601(&button.paired_at),
                    "last_seen_at": button.last_seen_at.as_ref().map(iso8601),
                })
            })
            .collect();
        json!({
            "state": if self.buttons.is_empty() { "unpaired" } else { "available" },
            "transport": "wifi",
            "protocol": MAC_DOMAIN,
            "security": "hmac_sha256_counter",
            "buttons": buttons,
            "pairing": {
                "active": pairing_active,
                "expires_at": self
                    .pairing
                    .as_ref()
                    .filter(|_| pairing_active)
                    .map(|pairing| iso8601(&pairing.expires_at)),
            },
        })
    }

    fn pairing_active(&self, ctx: &Context) -> bool {
        self.pairing
            .as_ref()
            .is_some_and(|pairing| ctx.monotonic_ms < pairing.deadline_ms)
    }

    pub(crate) fn begin_pairing(&mut self, seconds_value: Option<&Value>, ctx: &Context, out: &mut Outcome) -> Result<Value> {
        let duration = match seconds_value {
            None => 120,
            Some(value) => value
                .as_u64()
                .filter(|seconds| (MIN_PAIRING_SECONDS..=MAX_PAIRING_SECONDS).contains(seconds))
                .ok_or(Error::Code("invalid_pairing_duration"))?,
        };
        self.pairing = Some(Pairing {
            deadline_ms: ctx.monotonic_ms + duration * 1_000,
            expires_at: seconds(ctx.now) + Duration::seconds(duration as i64),
        });
        out.publish(STATE_CHANGED);
        Ok(self.remote_button_status(ctx))
    }

    pub(crate) fn pair_button(&mut self, id: &str, name: &str, ctx: &Context, out: &mut Outcome) -> Result<Value> {
        if !self.pairing_active(ctx) {
            return Err(Error::Code("pairing_window_closed"));
        }
        validate_button_id(id)?;
        let name = name.trim();
        if !(1..=64).contains(&name.chars().count()) {
            return Err(Error::Code("invalid_button_name"));
        }

        let mut secret = [0u8; 32];
        robine_core::random::fill(&mut secret);
        let secret_hex = hex::encode(secret);
        self.buttons.retain(|button| button.id != id);
        self.buttons.push(ButtonRecord {
            id: id.into(),
            name: name.into(),
            secret_hex: secret_hex.clone(),
            last_counter: 0,
            paired_at: seconds(ctx.now),
            last_seen_at: None,
        });
        self.pairing = None;
        out.changed(STATE_CHANGED);
        Ok(json!({
            "button_id": id,
            "algorithm": "hmac-sha256",
            "protocol": MAC_DOMAIN,
            "secret_hex": secret_hex,
            "next_counter": 1,
        }))
    }

    pub(crate) fn remove_button(&mut self, id: &str, out: &mut Outcome) -> Result<()> {
        let index = self
            .buttons
            .iter()
            .position(|button| button.id == id)
            .ok_or(Error::Code("remote_button_not_paired"))?;
        self.buttons.remove(index);
        out.changed(STATE_CHANGED);
        Ok(())
    }

    pub(crate) fn remote_dismiss(&mut self, body: &Map<String, Value>, ctx: &Context, out: &mut Outcome) -> Result<Value> {
        let id = body
            .get("button_id")
            .and_then(Value::as_str)
            .ok_or(Error::Code("invalid_button_id"))?;
        validate_button_id(id)?;
        let counter = body
            .get("counter")
            .and_then(Value::as_u64)
            .filter(|counter| (1..=MAX_COUNTER).contains(counter))
            .ok_or(Error::Code("invalid_remote_button_counter"))?;
        let mac = body
            .get("mac")
            .and_then(Value::as_str)
            .filter(|mac| mac.len() == 64 && mac.bytes().all(|byte| byte.is_ascii_hexdigit()))
            .ok_or(Error::Code("invalid_remote_button_signature"))?;

        let button = self
            .buttons
            .iter_mut()
            .find(|button| button.id == id)
            .ok_or(Error::Code("remote_button_not_paired"))?;
        let secret = hex::decode(&button.secret_hex).map_err(|_| Error::Code("invalid_remote_button_secret"))?;
        let expected = robine_core::remote_button::compute_dismiss_hmac(&secret, id, counter)
            .map_err(|_| Error::Code("invalid_remote_button_secret"))?;
        if !constant_time_eq(expected.as_bytes(), mac.to_ascii_lowercase().as_bytes()) {
            return Err(Error::Code("invalid_remote_button_signature"));
        }

        let previous = button.last_counter;
        if counter < previous {
            return Err(Error::Code("remote_button_replay"));
        }
        if counter == previous {
            return Ok(json!({ "accepted": true, "duplicate": true, "button_id": id, "counter": counter }));
        }
        // ACC-002.3: the counter is persisted together with the dismissal.
        button.last_counter = counter;
        button.last_seen_at = Some(seconds(ctx.now));
        out.changed(STATE_CHANGED);

        let session = self.dismiss(DismissOrigin::RemoteButton, ctx, out)?;
        Ok(json!({
            "accepted": true,
            "duplicate": false,
            "button_id": id,
            "counter": counter,
            "session": session,
        }))
    }

    // ----- Factory reset ------------------------------------------------------

    pub(crate) fn factory_reset(&mut self, out: &mut Outcome) {
        let platform = self.platform.clone();
        *self = Self::new(platform);
        out.changed(STATE_CHANGED);
        out.publish(SESSION_CHANGED);
    }
}

fn entry_for(alarm: &Alarm, scheduled_for: DateTime<Utc>) -> ScheduleEntry {
    ScheduleEntry {
        alarm_id: alarm.id.clone(),
        scheduled_for,
        starts_at: scheduled_for - Duration::seconds(alarm.prewake_seconds),
    }
}

fn check_revision(alarm: &Alarm, requested: Option<&Value>) -> Result<()> {
    if requested.and_then(Value::as_i64) == Some(alarm.revision) {
        Ok(())
    } else {
        Err(Error::Code("revision_conflict"))
    }
}

fn validate_button_id(id: &str) -> Result<()> {
    let valid = (1..=48).contains(&id.len())
        && id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'-');
    if valid {
        Ok(())
    } else {
        Err(Error::Code("invalid_button_id"))
    }
}

fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    left.len() == right.len()
        && left
            .iter()
            .zip(right)
            .fold(0u8, |acc, (a, b)| acc | (a ^ b))
            == 0
}

fn seconds(datetime: DateTime<Utc>) -> DateTime<Utc> {
    datetime.with_nanosecond(0).unwrap_or(datetime)
}

fn status_text(status: SessionStatus) -> &'static str {
    match status {
        SessionStatus::Scheduled | SessionStatus::Starting => "starting",
        SessionStatus::Ringing => "ringing",
        SessionStatus::Snoozed => "snoozed",
        SessionStatus::Dismissed => "dismissed",
        SessionStatus::TimedOut => "timed_out",
        SessionStatus::FailedSafe => "failed_safe",
    }
}

fn is_terminal(state: &str) -> bool {
    matches!(state, "dismissed" | "timed_out" | "missed" | "interrupted")
}

fn session_dto(active: &ActiveSession, terminal_reason: Option<&str>, ended_at: Option<DateTime<Utc>>) -> Value {
    let audio_phase = match active.core.phase {
        Some(RingingPhase::Strong) => "strong",
        _ => "gentle",
    };
    let map = json!({
        "id": active.core.id,
        "alarm_id": active.alarm.id,
        "state": status_text(active.core.status),
        "terminal_reason": terminal_reason,
        "created_at": iso8601(&active.created_at),
        "ended_at": ended_at.as_ref().map(iso8601),
        "audio_phase": audio_phase,
        "current_gain": active.core.current_gain,
        "snooze_count": active.core.snooze_count,
        "smartphone_dismiss_allowed": active.smartphone_dismiss_allowed,
        "test_mode": active.test_mode,
    });
    match map {
        Value::Object(map) => dto::select(&map, dto::SESSION_KEYS),
        _ => unreachable!(),
    }
}
