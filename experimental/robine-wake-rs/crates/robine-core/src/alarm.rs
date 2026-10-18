//! Validated alarm aggregate and time-zone-aware occurrence calculation.
//!
//! Port of `RobineWake.Alarm`. Input is accepted leniently (strings for
//! integers, day names, "HH:MM"), output is the exact JSON shape produced by
//! `Alarm.to_map/1` in the Elixir application.

use alloc::boxed::Box;
use alloc::collections::BTreeMap;
use alloc::format;
use alloc::string::{String, ToString};
use alloc::vec::Vec;

use chrono::{
    DateTime, Datelike, LocalResult, NaiveDate, NaiveDateTime, NaiveTime, TimeDelta, TimeZone,
    Timelike, Utc,
};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

/// Field -> message, mirrors the `%{field: "message"}` error maps of Elixir.
pub type Errors = BTreeMap<String, String>;

pub const SAFETY_CEILING: i64 = 100;
const CANDIDATE_DAYS: i64 = 370;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DismissPolicy {
    Manual,
    BedExit,
    Either,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EndBehavior {
    Restore,
    Off,
    Leave,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct VolumeProfile {
    pub start: i64,
    pub ceiling: i64,
    pub strong: i64,
    pub ramp_seconds: i64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LightProfile {
    pub enabled: bool,
    pub target_id: Option<String>,
    pub target_name: Option<String>,
    pub start_brightness: i64,
    pub end_brightness: i64,
    pub ramp_seconds: i64,
    pub end_behavior: EndBehavior,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Snooze {
    pub enabled: bool,
    pub duration_seconds: i64,
    pub maximum: i64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Alarm {
    pub id: String,
    pub created_at: DateTime<Utc>,
    pub label: String,
    pub enabled: bool,
    pub local_time: NaiveTime,
    pub days_of_week: Vec<u8>,
    pub one_shot_date: Option<NaiveDate>,
    pub timezone: String,
    pub sound_id: String,
    pub strong_sound_id: String,
    pub prewake_seconds: i64,
    pub volume_profile: VolumeProfile,
    pub light_profile: LightProfile,
    pub dismiss_policy: DismissPolicy,
    pub snooze: Snooze,
    pub revision: i64,
}

impl Alarm {
    /// Build a validated alarm from loose JSON input. `now` seeds `created_at`.
    pub fn new(input: &Value, now: DateTime<Utc>) -> Result<Alarm, Errors> {
        let attrs = match input.as_object() {
            Some(map) => map,
            None => return Err(error("alarm", "must be an object")),
        };

        let created_at = match attrs.get("created_at") {
            None | Some(Value::Null) => truncate(now),
            Some(value) => parse_datetime(value)?,
        };
        let local_time = parse_time(attrs.get("local_time"))?;
        let one_shot_date = parse_date(attrs.get("one_shot_date"))?;
        let days_of_week = parse_days(attrs.get("days_of_week"))?;
        let timezone = validate_timezone(attrs.get("timezone"))?;
        let dismiss_policy = parse_policy(attrs.get("dismiss_policy"))?;
        let volume_profile = parse_volume(attrs.get("volume_profile"))?;
        let prewake_seconds =
            parse_prewake(attrs.get("prewake_seconds"), volume_profile.ramp_seconds)?;
        let light_profile = parse_light(attrs.get("light_profile"))?;
        let snooze = parse_snooze(attrs.get("snooze"))?;

        let alarm = Alarm {
            id: text(attrs.get("id")).unwrap_or_else(generate_id),
            created_at,
            label: text(attrs.get("label"))
                .unwrap_or_else(|| "Alarm".to_string())
                .chars()
                .take(80)
                .collect(),
            enabled: attrs.get("enabled").is_none_or(truthy),
            local_time,
            days_of_week,
            one_shot_date,
            timezone,
            sound_id: text(attrs.get("sound_id")).unwrap_or_else(|| "default".into()),
            strong_sound_id: text(attrs.get("strong_sound_id")).unwrap_or_else(|| "default".into()),
            prewake_seconds,
            volume_profile,
            light_profile,
            dismiss_policy,
            snooze,
            revision: integer(attrs.get("revision"), 1),
        };

        if alarm.days_of_week.is_empty() && alarm.one_shot_date.is_none() {
            return Err(error(
                "days_of_week",
                "must not be empty for a recurring alarm",
            ));
        }

        Ok(alarm)
    }

    /// JSON object with the exact key set of `Alarm.to_map/1`.
    pub fn to_map(&self) -> Map<String, Value> {
        match serde_json::to_value(self) {
            Ok(Value::Object(map)) => map,
            _ => unreachable!("alarm always serializes to an object"),
        }
    }

    pub fn tz(&self) -> Tz {
        self.timezone
            .parse()
            .expect("timezone validated at construction")
    }

    pub fn next_occurrence(&self, from_utc: DateTime<Utc>) -> Option<DateTime<Tz>> {
        let tz = self.tz();
        let today = from_utc.with_timezone(&tz).date_naive();
        self.candidate_dates(today, 1).find_map(|date| {
            self.occurrence_on(date, &tz)
                .filter(|dt| dt.with_timezone(&Utc) > from_utc)
        })
    }

    /// Kept for parity with the Elixir API; only the HTTP layer's unused so far.
    #[allow(dead_code)]
    pub fn previous_occurrence(&self, before_utc: DateTime<Utc>) -> Option<DateTime<Tz>> {
        let tz = self.tz();
        let today = before_utc.with_timezone(&tz).date_naive();
        self.candidate_dates(today, -1).find_map(|date| {
            self.occurrence_on(date, &tz)
                .filter(|dt| dt.with_timezone(&Utc) < before_utc)
        })
    }

    pub fn next_occurrences(&self, count: usize, from_utc: DateTime<Utc>) -> Vec<DateTime<Tz>> {
        let mut cursor = from_utc;
        let mut occurrences = Vec::with_capacity(count);
        while occurrences.len() < count {
            match self.next_occurrence(cursor) {
                Some(occurrence) => {
                    cursor = occurrence.with_timezone(&Utc) + TimeDelta::seconds(1);
                    occurrences.push(occurrence);
                }
                None => break,
            }
        }
        occurrences
    }

    fn candidate_dates(
        &self,
        today: NaiveDate,
        direction: i64,
    ) -> Box<dyn Iterator<Item = NaiveDate> + '_> {
        match self.one_shot_date {
            Some(one) if direction > 0 && one != today => Box::new([today, one].into_iter()),
            Some(one) => Box::new(core::iter::once(one)),
            None => Box::new((0..=CANDIDATE_DAYS).filter_map(move |offset| {
                today.checked_add_signed(TimeDelta::days(offset * direction))
            })),
        }
    }

    fn scheduled_on(&self, date: NaiveDate) -> bool {
        match self.one_shot_date {
            Some(one) => one == date,
            None => self
                .days_of_week
                .contains(&(date.weekday().number_from_monday() as u8)),
        }
    }

    fn occurrence_on(&self, date: NaiveDate, tz: &Tz) -> Option<DateTime<Tz>> {
        if self.scheduled_on(date) {
            local_datetime(tz, date.and_time(self.local_time))
        } else {
            None
        }
    }
}

/// Resolve a wall-clock time like `DateTime.from_naive/2`: an ambiguous time
/// takes its first occurrence, a time inside a DST gap moves to the first
/// valid instant after the gap.
fn local_datetime(tz: &Tz, naive: NaiveDateTime) -> Option<DateTime<Tz>> {
    match tz.from_local_datetime(&naive) {
        LocalResult::Single(dt) => Some(dt),
        LocalResult::Ambiguous(first, _second) => Some(first),
        LocalResult::None => (1..=180).find_map(|minutes| {
            match tz.from_local_datetime(&(naive + TimeDelta::minutes(minutes))) {
                LocalResult::Single(dt) => Some(dt),
                _ => None,
            }
        }),
    }
}

pub fn generate_id() -> String {
    let mut bytes = [0u8; 16];
    crate::random::fill(&mut bytes);
    uuid::Builder::from_random_bytes(bytes)
        .into_uuid()
        .to_string()
        .to_uppercase()
}

fn error(field: &str, message: &str) -> Errors {
    BTreeMap::from([(field.to_string(), message.to_string())])
}

fn truncate(datetime: DateTime<Utc>) -> DateTime<Utc> {
    datetime.with_nanosecond(0).unwrap_or(datetime)
}

fn parse_datetime(value: &Value) -> Result<DateTime<Utc>, Errors> {
    match value
        .as_str()
        .and_then(|text| DateTime::parse_from_rfc3339(text).ok())
    {
        Some(parsed) => Ok(truncate(parsed.with_timezone(&Utc))),
        None if value.is_string() => Err(error("created_at", "must use ISO 8601")),
        None => Err(error("created_at", "is invalid")),
    }
}

fn parse_time(value: Option<&Value>) -> Result<NaiveTime, Errors> {
    let raw = match value {
        None | Some(Value::Null) => "07:00".to_string(),
        Some(Value::String(text)) => text.clone(),
        Some(_) => return Err(error("local_time", "is invalid")),
    };
    let raw = if raw.chars().count() == 5 {
        format!("{raw}:00")
    } else {
        raw
    };
    NaiveTime::parse_from_str(&raw, "%H:%M:%S")
        .or_else(|_| NaiveTime::parse_from_str(&raw, "%H:%M:%S%.f"))
        .map(|time| time.with_nanosecond(0).unwrap_or(time))
        .map_err(|_| error("local_time", "must use HH:MM or HH:MM:SS"))
}

fn parse_date(value: Option<&Value>) -> Result<Option<NaiveDate>, Errors> {
    match value {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(text)) if text.is_empty() => Ok(None),
        Some(Value::String(text)) => NaiveDate::parse_from_str(text, "%Y-%m-%d")
            .map(Some)
            .map_err(|_| error("one_shot_date", "must use YYYY-MM-DD")),
        Some(_) => Err(error("one_shot_date", "is invalid")),
    }
}

fn parse_days(value: Option<&Value>) -> Result<Vec<u8>, Errors> {
    const NAMES: [&str; 7] = [
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday",
        "saturday",
        "sunday",
    ];
    let items = match value {
        None | Some(Value::Null) => return Ok((1..=7).collect()),
        Some(Value::Array(items)) => items,
        Some(_) => return Err(error("days_of_week", "must be a list")),
    };
    let mut days = Vec::with_capacity(items.len());
    for item in items {
        let day = match item {
            Value::Number(number) => number.as_i64(),
            Value::String(text) => NAMES
                .iter()
                .position(|name| name.eq_ignore_ascii_case(text))
                .map(|index| index as i64 + 1)
                .or_else(|| text.parse::<i64>().ok()),
            _ => None,
        };
        match day {
            Some(day) if (1..=7).contains(&day) => days.push(day as u8),
            _ => return Err(error("days_of_week", "must contain weekdays 1 through 7")),
        }
    }
    days.sort_unstable();
    days.dedup();
    Ok(days)
}

fn validate_timezone(value: Option<&Value>) -> Result<String, Errors> {
    match value {
        None | Some(Value::Null) => Ok("Europe/Paris".to_string()),
        Some(Value::String(text)) => match text.parse::<Tz>() {
            Ok(_) => Ok(text.clone()),
            Err(_) => Err(error("timezone", "is not a known IANA time zone")),
        },
        Some(_) => Err(error("timezone", "is invalid")),
    }
}

fn parse_policy(value: Option<&Value>) -> Result<DismissPolicy, Errors> {
    match value {
        None | Some(Value::Null) => Ok(DismissPolicy::Manual),
        Some(Value::String(text)) => match text.as_str() {
            "manual" => Ok(DismissPolicy::Manual),
            "bed_exit" => Ok(DismissPolicy::BedExit),
            "either" => Ok(DismissPolicy::Either),
            _ => Err(error(
                "dismiss_policy",
                "must be manual, bed_exit, or either",
            )),
        },
        Some(_) => Err(error("dismiss_policy", "is invalid")),
    }
}

fn parse_volume(value: Option<&Value>) -> Result<VolumeProfile, Errors> {
    let map = match value {
        None | Some(Value::Null) => &Map::new(),
        Some(Value::Object(map)) => map,
        Some(_) => return Err(error("volume_profile", "must be an object")),
    };
    let ceiling = integer(map.get("ceiling"), 85);
    // Alarms saved before the strong level existed keep ringing at the ceiling.
    let profile = VolumeProfile {
        start: integer(map.get("start"), 15),
        ceiling,
        strong: integer(map.get("strong"), ceiling),
        ramp_seconds: integer(map.get("ramp_seconds"), 1_200),
    };
    let safe = (0..=SAFETY_CEILING).contains(&profile.start)
        && (profile.start..=SAFETY_CEILING).contains(&profile.ceiling)
        && (0..=SAFETY_CEILING).contains(&profile.strong)
        && (0..=3600).contains(&profile.ramp_seconds);
    if safe {
        Ok(profile)
    } else {
        Err(error(
            "volume_profile",
            "contains values outside safe bounds",
        ))
    }
}

fn parse_prewake(value: Option<&Value>, default: i64) -> Result<i64, Errors> {
    let seconds = match value {
        None | Some(Value::Null) => default,
        Some(value) => integer(Some(value), -1),
    };
    if (0..=3600).contains(&seconds) {
        Ok(seconds)
    } else {
        Err(error(
            "prewake_seconds",
            "must be between 0 and 3600 seconds",
        ))
    }
}

fn parse_light(value: Option<&Value>) -> Result<LightProfile, Errors> {
    let map = match value {
        None | Some(Value::Null) => &Map::new(),
        Some(Value::Object(map)) => map,
        Some(_) => return Err(error("light_profile", "must be an object")),
    };
    let end_behavior = match map.get("end_behavior") {
        None | Some(Value::Null) => Some(EndBehavior::Restore),
        Some(Value::String(text)) => match text.as_str() {
            "restore" => Some(EndBehavior::Restore),
            "off" => Some(EndBehavior::Off),
            "leave" => Some(EndBehavior::Leave),
            _ => None,
        },
        Some(_) => None,
    };
    let enabled = map.get("enabled").is_some_and(truthy);
    let target_id = optional_text(map.get("target_id"));
    let start = integer(map.get("start_brightness"), 1);
    let end = integer(map.get("end_brightness"), 70);
    let ramp_seconds = integer(map.get("ramp_seconds"), 900);

    if enabled && target_id.is_none() {
        return Err(error("light_profile", "requires a Hue target when enabled"));
    }
    if let Some(id) = &target_id {
        let valid = !id.is_empty()
            && id.len() <= 64
            && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-');
        if !valid {
            return Err(error(
                "light_profile",
                "contains an invalid Hue target identifier",
            ));
        }
    }
    if !(1..=100).contains(&start) || !(1..=100).contains(&end) {
        return Err(error(
            "light_profile",
            "brightness must be between 1 and 100",
        ));
    }
    if end < start {
        return Err(error(
            "light_profile",
            "end brightness must be at least the start brightness",
        ));
    }
    let end_behavior = match end_behavior {
        Some(behavior) if (0..=3600).contains(&ramp_seconds) => behavior,
        _ => {
            return Err(error(
                "light_profile",
                "contains values outside supported bounds",
            ))
        }
    };

    Ok(LightProfile {
        enabled,
        target_id,
        target_name: optional_text(map.get("target_name")),
        start_brightness: start,
        end_brightness: end,
        ramp_seconds,
        end_behavior,
    })
}

fn parse_snooze(value: Option<&Value>) -> Result<Snooze, Errors> {
    let map = match value {
        None | Some(Value::Null) => &Map::new(),
        Some(Value::Object(map)) => map,
        Some(_) => return Err(error("snooze", "must be an object")),
    };
    let snooze = Snooze {
        enabled: map.get("enabled").is_none_or(truthy),
        duration_seconds: integer(map.get("duration_seconds"), 480),
        maximum: integer(map.get("maximum"), 3),
    };
    if (60..=1800).contains(&snooze.duration_seconds) && (0..=10).contains(&snooze.maximum) {
        Ok(snooze)
    } else {
        Err(error("snooze", "contains values outside safe bounds"))
    }
}

/// `integer/2`: integers pass through, numeric strings parse, anything else
/// falls back to the default.
fn integer(value: Option<&Value>, default: i64) -> i64 {
    match value {
        Some(Value::Number(number)) => number.as_i64().unwrap_or(default),
        Some(Value::String(text)) => text.parse().unwrap_or(default),
        _ => default,
    }
}

/// `truthy?/1`: `true`, `"true"`, `1`, `"1"`, `"on"`.
fn truthy(value: &Value) -> bool {
    match value {
        Value::Bool(flag) => *flag,
        Value::Number(number) => number.as_i64() == Some(1),
        Value::String(text) => matches!(text.as_str(), "true" | "1" | "on"),
        _ => false,
    }
}

fn text(value: Option<&Value>) -> Option<String> {
    match value {
        None | Some(Value::Null) => None,
        Some(Value::String(text)) => Some(text.clone()),
        Some(Value::Bool(flag)) => Some(flag.to_string()),
        Some(Value::Number(number)) => Some(number.to_string()),
        Some(_) => None,
    }
}

fn optional_text(value: Option<&Value>) -> Option<String> {
    text(value)
        .filter(|text| !text.is_empty())
        .map(|text| text.chars().take(120).collect())
}

#[cfg(test)]
mod tests {
    use std::prelude::rust_2021::*;
    use super::*;
    use chrono::Offset;
    use serde_json::json;

    fn utc(text: &str) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(text)
            .unwrap()
            .with_timezone(&Utc)
    }

    fn new(input: Value) -> Result<Alarm, Errors> {
        Alarm::new(&input, utc("2026-01-01T00:00:00Z"))
    }

    #[test]
    fn validates_and_normalizes_input() {
        let alarm = new(json!({
            "label": "Weekdays",
            "local_time": "07:30",
            "days_of_week": [5, 1, 1, 3],
            "timezone": "Europe/Paris",
            "dismiss_policy": "bed_exit"
        }))
        .unwrap();

        assert_eq!(alarm.days_of_week, vec![1, 3, 5]);
        assert_eq!(alarm.local_time, NaiveTime::from_hms_opt(7, 30, 0).unwrap());
        assert_eq!(alarm.dismiss_policy, DismissPolicy::BedExit);
        assert_eq!(alarm.prewake_seconds, 1_200);
        assert_eq!(alarm.revision, 1);
        assert_eq!(alarm.id.len(), 36);
        assert_eq!(alarm.id, alarm.id.to_uppercase());
    }

    #[test]
    fn prewake_is_configurable_and_falls_back_to_legacy_ramp() {
        let configured = new(json!({ "prewake_seconds": 1_800 })).unwrap();
        assert_eq!(configured.prewake_seconds, 1_800);
        assert_eq!(configured.to_map()["prewake_seconds"], json!(1_800));

        let legacy = new(json!({ "volume_profile": { "ramp_seconds": 420 } })).unwrap();
        assert_eq!(legacy.prewake_seconds, 420);

        let err = new(json!({ "prewake_seconds": 3_601 })).unwrap_err();
        assert!(err.contains_key("prewake_seconds"));
    }

    #[test]
    fn rejects_unsafe_or_incomplete_input() {
        let err = new(json!({ "days_of_week": [], "one_shot_date": null })).unwrap_err();
        assert!(err.contains_key("days_of_week"));

        let err = new(json!({ "timezone": "Nowhere/Invalid" })).unwrap_err();
        assert!(err.contains_key("timezone"));

        for volume in [
            json!({ "start": 80, "ceiling": 20, "ramp_seconds": 10 }),
            json!({ "start": 15, "ceiling": 101, "ramp_seconds": 10 }),
            json!({ "start": 15, "ceiling": 60, "strong": 101 }),
        ] {
            let err = new(json!({ "volume_profile": volume })).unwrap_err();
            assert!(err.contains_key("volume_profile"), "{volume}");
        }

        let err =
            new(json!({ "light_profile": { "enabled": true, "target_id": null } })).unwrap_err();
        assert!(err.contains_key("light_profile"));
    }

    #[test]
    fn strong_volume_defaults_to_ceiling_and_can_differ() {
        let alarm = new(json!({ "volume_profile": { "start": 15, "ceiling": 60 } })).unwrap();
        assert_eq!(
            (alarm.volume_profile.ceiling, alarm.volume_profile.strong),
            (60, 60)
        );

        let alarm =
            new(json!({ "volume_profile": { "start": 15, "ceiling": 60, "strong": 90 } })).unwrap();
        assert_eq!(
            (alarm.volume_profile.ceiling, alarm.volume_profile.strong),
            (60, 90)
        );

        let alarm =
            new(json!({ "volume_profile": { "start": "15", "ceiling": "60", "strong": "40" } }))
                .unwrap();
        assert_eq!(
            (alarm.volume_profile.ceiling, alarm.volume_profile.strong),
            (60, 40)
        );
    }

    #[test]
    fn normalizes_a_hue_wake_light_profile() {
        let alarm = new(json!({
            "light_profile": {
                "enabled": true,
                "target_id": "bedroom-group",
                "target_name": "Chambre",
                "start_brightness": 2,
                "end_brightness": 80,
                "ramp_seconds": 1_200,
                "end_behavior": "off"
            }
        }))
        .unwrap();

        assert_eq!(alarm.light_profile.end_behavior, EndBehavior::Off);
        assert_eq!(
            alarm.to_map()["light_profile"]["target_name"],
            json!("Chambre")
        );
        assert_eq!(
            alarm.to_map()["light_profile"]["end_behavior"],
            json!("off")
        );
    }

    #[test]
    fn moves_a_nonexistent_dst_local_time_to_the_first_valid_instant() {
        let alarm = new(json!({
            "local_time": "02:30",
            "one_shot_date": "2026-03-29",
            "days_of_week": [],
            "timezone": "Europe/Paris"
        }))
        .unwrap();

        let occurrence = alarm.next_occurrence(utc("2026-03-28T00:00:00Z")).unwrap();
        assert_eq!((occurrence.hour(), occurrence.minute()), (3, 0));
        assert_eq!(occurrence.timezone().name(), "Europe/Paris");
    }

    #[test]
    fn uses_the_first_occurrence_of_an_ambiguous_dst_local_time() {
        let alarm = new(json!({
            "local_time": "02:30",
            "one_shot_date": "2026-10-25",
            "days_of_week": [],
            "timezone": "Europe/Paris"
        }))
        .unwrap();

        let occurrence = alarm.next_occurrence(utc("2026-10-24T00:00:00Z")).unwrap();
        assert_eq!(occurrence.offset().fix().local_minus_utc(), 7_200);
    }

    #[test]
    fn generates_ordered_recurring_occurrences() {
        let alarm = new(json!({ "local_time": "07:00", "days_of_week": [1, 2, 3, 4, 5] })).unwrap();
        let occurrences = alarm.next_occurrences(5, utc("2026-01-16T07:00:00Z"));

        assert_eq!(occurrences.len(), 5);
        assert!(occurrences.windows(2).all(|pair| pair[0] < pair[1]));
    }

    #[test]
    fn finds_the_previous_occurrence_and_none_for_a_zero_count_preview() {
        let alarm = new(json!({ "local_time": "07:00", "days_of_week": [1, 2, 3, 4, 5] })).unwrap();
        assert!(alarm
            .next_occurrences(0, utc("2026-01-16T07:00:00Z"))
            .is_empty());

        let previous = alarm
            .previous_occurrence(utc("2026-01-16T07:00:00Z"))
            .unwrap();
        assert_eq!(
            previous.to_rfc3339_opts(chrono::SecondsFormat::Secs, false),
            "2026-01-16T07:00:00+01:00"
        );
    }

    #[test]
    fn serializes_with_the_elixir_key_set() {
        let alarm = new(json!({ "label": "Demo" })).unwrap();
        let map = alarm.to_map();
        let keys: Vec<&String> = map.keys().collect();
        assert_eq!(
            keys,
            [
                "created_at",
                "days_of_week",
                "dismiss_policy",
                "enabled",
                "id",
                "label",
                "light_profile",
                "local_time",
                "one_shot_date",
                "prewake_seconds",
                "revision",
                "snooze",
                "sound_id",
                "strong_sound_id",
                "timezone",
                "volume_profile"
            ]
            .iter()
            .map(|key| key.to_string())
            .collect::<Vec<_>>()
            .iter()
            .collect::<Vec<_>>()
        );
        assert_eq!(map["created_at"], json!("2026-01-01T00:00:00Z"));
        assert_eq!(map["local_time"], json!("07:00:00"));
        assert_eq!(map["dismiss_policy"], json!("manual"));
    }

    #[test]
    fn reloads_an_alarm_persisted_by_the_elixir_application() {
        let persisted = json!({
            "created_at": "2026-10-01T20:30:00Z",
            "days_of_week": [1, 2, 3, 4, 5, 6, 7],
            "dismiss_policy": "manual",
            "enabled": true,
            "id": "8A0AA605-1AAA-4783-98D0-9E85A1218090",
            "label": "Demo · Réveil",
            "light_profile": {
                "enabled": true, "end_behavior": "restore", "end_brightness": 25,
                "ramp_seconds": 1200, "start_brightness": 1, "target_id": "lamps",
                "target_name": "Lampes de chevet"
            },
            "local_time": "07:00:00",
            "one_shot_date": null,
            "prewake_seconds": 1200,
            "revision": 1,
            "snooze": { "duration_seconds": 480, "enabled": true, "maximum": 3 },
            "sound_id": "jungle_sunrise",
            "strong_sound_id": "wake_up_call",
            "timezone": "Europe/Paris",
            "volume_profile": { "ceiling": 85, "ramp_seconds": 1200, "start": 15 }
        });

        let alarm = new(persisted.clone()).unwrap();
        let mut expected = persisted.as_object().unwrap().clone();
        expected["volume_profile"]["strong"] = json!(85);
        assert_eq!(Value::Object(alarm.to_map()), Value::Object(expected));
    }
}
