//! Nap mode: single one-shot alarm ringing N minutes from now (ALM-003).
//!
//! Port of `RobineWake.Nap`. It reuses the sounds, volume, and light of the user's
//! regular alarm, but its gentle ramp is short: at most two minutes, and never
//! longer than the nap.

use alloc::collections::BTreeMap;
use alloc::format;
use alloc::string::ToString;

use chrono::{DateTime, Datelike, Timelike, Utc};
use chrono_tz::Tz;
use serde_json::{json, Value};

use crate::alarm::{Alarm, EndBehavior, Errors, LightProfile, VolumeProfile};

pub const NAP_ALARM_ID: &str = "nap";
pub const MAXIMUM_RAMP_SECONDS: i64 = 120;
pub const MAXIMUM_MINUTES: u32 = 180;

/// Select the user alarm to serve as a template for the nap.
///
/// Discards any existing `nap` alarm, then picks the first enabled alarm,
/// or the first alarm in the list if none are enabled, or `None`.
pub fn select_template_alarm<'a>(alarms: impl IntoIterator<Item = &'a Alarm>) -> Option<&'a Alarm> {
    let mut first = None;
    for alarm in alarms {
        if alarm.id != NAP_ALARM_ID {
            if alarm.enabled {
                return Some(alarm);
            }
            if first.is_none() {
                first = Some(alarm);
            }
        }
    }
    first
}

/// Compute the nap ramp in seconds: `min(120 s, duration)` (ALM-003.2).
pub fn ramp_seconds_for_duration(minutes: u32) -> i64 {
    core::cmp::min(MAXIMUM_RAMP_SECONDS, (minutes as i64) * 60)
}

/// Build the JSON payload to create or update a nap alarm.
pub fn build_nap_payload(
    minutes: u32,
    template: Option<&Alarm>,
    now: DateTime<Utc>,
) -> Result<Value, Errors> {
    if minutes == 0 || minutes > MAXIMUM_MINUTES {
        let mut errs = BTreeMap::new();
        errs.insert(
            "duration_minutes".to_string(),
            "must be between 1 and 180".to_string(),
        );
        return Err(errs);
    }

    let timezone = template
        .map(|t| t.timezone.clone())
        .unwrap_or_else(|| "Europe/Paris".to_string());
    let tz: Tz = timezone.parse().unwrap_or(chrono_tz::Europe::Paris);

    let wake_at = now + chrono::TimeDelta::minutes(minutes as i64);
    let local = wake_at.with_timezone(&tz);

    let ramp_seconds = ramp_seconds_for_duration(minutes);

    let (sound_id, strong_sound_id, volume_profile, light_profile) = match template {
        Some(t) => {
            let mut vp = t.volume_profile.clone();
            vp.ramp_seconds = ramp_seconds;
            let mut lp = t.light_profile.clone();
            lp.ramp_seconds = ramp_seconds;
            (t.sound_id.clone(), t.strong_sound_id.clone(), vp, lp)
        }
        None => {
            let vp = VolumeProfile {
                start: 15,
                ceiling: 85,
                strong: 85,
                ramp_seconds,
            };
            let lp = LightProfile {
                enabled: false,
                target_id: None,
                target_name: None,
                start_brightness: 1,
                end_brightness: 100,
                ramp_seconds,
                end_behavior: EndBehavior::Off,
            };
            ("default".to_string(), "default".to_string(), vp, lp)
        }
    };

    let local_time_str = format!(
        "{:02}:{:02}:{:02}",
        local.time().hour(),
        local.time().minute(),
        local.time().second()
    );
    let one_shot_date_str = format!(
        "{:04}-{:02}-{:02}",
        local.date_naive().year(),
        local.date_naive().month(),
        local.date_naive().day()
    );

    Ok(json!({
        "id": NAP_ALARM_ID,
        "label": "Sieste",
        "enabled": true,
        "local_time": local_time_str,
        "one_shot_date": one_shot_date_str,
        "days_of_week": [],
        "timezone": timezone,
        "prewake_seconds": ramp_seconds,
        "sound_id": sound_id,
        "strong_sound_id": strong_sound_id,
        "volume_profile": volume_profile,
        "light_profile": light_profile,
        "snooze": {
            "enabled": false,
            "duration_seconds": 540,
            "maximum": 3
        }
    }))
}

#[cfg(test)]
mod tests {
    use std::prelude::rust_2021::*;
    use super::*;
    use chrono::TimeZone;

    fn make_test_alarm(id: &str, enabled: bool) -> Alarm {
        let now = Utc.with_ymd_and_hms(2026, 10, 17, 12, 0, 0).unwrap();
        Alarm::new(
            &json!({
                "id": id,
                "enabled": enabled,
                "label": "Matin",
                "local_time": "07:00",
                "days_of_week": [1, 2, 3, 4, 5],
                "sound_id": "birds",
                "strong_sound_id": "siren",
                "volume_profile": { "start": 20, "ceiling": 90, "strong": 95, "ramp_seconds": 600 }
            }),
            now,
        )
        .unwrap()
    }

    #[test]
    fn ramp_calculation_limits_to_120_seconds_and_never_exceeds_duration() {
        // ALM-003.2: min(120 s, duration)
        assert_eq!(ramp_seconds_for_duration(1), 60);
        assert_eq!(ramp_seconds_for_duration(2), 120);
        assert_eq!(ramp_seconds_for_duration(20), 120);
        assert_eq!(ramp_seconds_for_duration(180), 120);
    }

    #[test]
    fn rejects_durations_outside_1_to_180_minutes() {
        let now = Utc.with_ymd_and_hms(2026, 10, 17, 14, 0, 0).unwrap();
        assert!(build_nap_payload(0, None, now).is_err());
        assert!(build_nap_payload(181, None, now).is_err());
        assert!(build_nap_payload(1, None, now).is_ok());
        assert!(build_nap_payload(180, None, now).is_ok());
    }

    #[test]
    fn selects_template_alarm_prioritizing_enabled_non_nap() {
        let a1 = make_test_alarm("a1", false);
        let a2 = make_test_alarm("a2", true);
        let nap = make_test_alarm(NAP_ALARM_ID, true);

        let list = vec![nap.clone(), a1.clone(), a2.clone()];
        let selected = select_template_alarm(&list);
        assert_eq!(selected.unwrap().id, "a2");

        // When none enabled, picks first non-nap
        let a2_disabled = make_test_alarm("a2", false);
        let list2 = vec![nap, a1.clone(), a2_disabled];
        let selected2 = select_template_alarm(&list2);
        assert_eq!(selected2.unwrap().id, "a1");
    }

    #[test]
    fn reuses_template_alarm_settings_and_overrides_ramp_and_snooze() {
        let template = make_test_alarm("a1", true);
        let now = Utc.with_ymd_and_hms(2026, 10, 17, 14, 0, 0).unwrap();
        let payload = build_nap_payload(20, Some(&template), now).unwrap();

        assert_eq!(payload["id"], NAP_ALARM_ID);
        assert_eq!(payload["label"], "Sieste");
        assert_eq!(payload["sound_id"], "birds");
        assert_eq!(payload["strong_sound_id"], "siren");
        assert_eq!(payload["volume_profile"]["ramp_seconds"], 120);
        assert_eq!(payload["prewake_seconds"], 120);
        assert_eq!(payload["snooze"]["enabled"], false);
        assert_eq!(payload["days_of_week"], json!([]));

        // Alarm::new validates successfully
        let alarm = Alarm::new(&payload, now).unwrap();
        assert_eq!(alarm.id, NAP_ALARM_ID);
        assert!(alarm.one_shot_date.is_some());
    }
}
