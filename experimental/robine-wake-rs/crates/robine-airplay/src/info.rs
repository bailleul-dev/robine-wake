//! Discovery records (`_airplay._tcp`) and the `GET /info` plist.

use alloc::format;
use alloc::string::String;
use alloc::vec::Vec;

use crate::bplist::{self, dict, Value};
use crate::{Config, Identity, SOURCE_VERSION};

/// TXT records of the `_airplay._tcp` service, as `(key, value)`.
/// `gid` equals `pi` while the speaker is not part of a group.
pub fn txt_records(config: &Config, identity: &Identity) -> Vec<(&'static str, String)> {
    let features = config.features;
    let pi = identity.pi_text();
    alloc::vec![
        ("acl", "0".into()),
        ("deviceid", identity.device_id_text()),
        ("features", format!("0x{:X},0x{:X}", features as u32, (features >> 32) as u32)),
        ("flags", format!("0x{:X}", config.status_flags)),
        ("gid", pi.clone()),
        ("gcgl", "0".into()),
        ("igl", "0".into()),
        ("model", config.model.clone()),
        ("protovers", "1.1".into()),
        ("pi", pi),
        ("pk", hex::encode(identity.public_key())),
        ("srcvers", SOURCE_VERSION.into()),
        ("vv", "2".into()),
    ]
}

/// DNS-SD TXT wire format: length-prefixed `key=value` strings.
fn packed_txt(config: &Config, identity: &Identity) -> Vec<u8> {
    let mut out = Vec::new();
    for (key, value) in txt_records(config, identity) {
        let record = format!("{key}={value}");
        let bytes = &record.as_bytes()[..record.len().min(255)];
        out.push(bytes.len() as u8);
        out.extend_from_slice(bytes);
    }
    out
}

/// Body of `GET /info` (fields of shairport-sync's `get_info_response`).
pub fn info_plist(config: &Config, identity: &Identity) -> Vec<u8> {
    let value = dict([
        ("vv", Value::Integer(2)),
        ("protocolVersion", Value::String("1.1".into())),
        ("volumeControlType", Value::Integer(3)),
        ("canRecordScreenStream", Value::Bool(false)),
        ("keepAliveSendStatsAsBody", Value::Bool(false)),
        ("screenDemoMode", Value::Bool(false)),
        (
            "playbackCapabilities",
            dict([
                ("supportsInterstitials", Value::Bool(false)),
                ("supportsFPSSecureStop", Value::Bool(false)),
                ("supportsUIForAudioOnlyContent", Value::Bool(false)),
            ]),
        ),
        ("deviceID", Value::String(identity.device_id_text())),
        ("name", Value::String(config.name.clone())),
        ("model", Value::String(config.model.clone())),
        ("sourceVersion", Value::String(SOURCE_VERSION.into())),
        ("features", Value::Integer(config.features as i64)),
        ("statusFlags", Value::Integer(i64::from(config.status_flags))),
        ("pi", Value::String(identity.pi_text())),
        ("pk", Value::Data(identity.public_key().to_vec())),
        ("txtAirPlay", Value::Data(packed_txt(config, identity))),
    ]);
    bplist::to_bytes(&value)
}
