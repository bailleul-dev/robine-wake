//! AirPlay 2 audio receiver core.
//!
//! Only what an AirPlay 2 speaker needs: discovery records, `GET /info`,
//! transient pairing, the encrypted control channel and (next steps) the
//! audio session. No video, screen mirroring, photos or multi-room grouping.
//!
//! The crate is `no_std + alloc` and does no I/O: [`Connection`] consumes the
//! bytes read from a control socket and returns the bytes to write back, so
//! the same code runs on the ESP32 (embassy-net) and on Linux (std sockets).
//! The platform provides randomness and stores the [`Identity`].

#![no_std]

extern crate alloc;
#[cfg(test)]
extern crate std;

pub mod aac;
pub mod alac;
pub mod audio;
pub mod bplist;
mod bits;
mod cipher;
mod connection;
#[cfg(feature = "fairplay")]
mod fairplay;
mod info;
mod pairing;
pub mod ptp;
pub mod realtime;
mod rtsp;
mod session;
mod srp;
pub mod tlv;

pub use connection::{Connection, Error, Event, Output, Receiver};
pub use info::txt_records;
pub use session::{summarize, Ports, Stream, STREAM_BUFFERED, STREAM_REALTIME};
pub use srp::SrpClient;

use alloc::string::String;
use alloc::vec::Vec;
use ed25519_dalek::SigningKey;

/// Fills a buffer with cryptographically secure random bytes.
pub type RandomSource = fn(&mut [u8]);

/// Capabilities announced to senders: audio only, transient pairing, buffered
/// and realtime audio, as shairport-sync advertises in AirPlay 2 mode.
pub const DEFAULT_FEATURES: u64 = 0x0001_8340_405F_CA00;
/// Status flags: bit 2, "audio cable attached" (the speaker is usable).
pub const DEFAULT_STATUS_FLAGS: u32 = 0x4;
/// Version of the AirPlay stack the receiver claims to implement.
pub const SOURCE_VERSION: &str = "366.0";
/// Port of the control connection.
pub const DEFAULT_PORT: u16 = 7000;

/// Static description of the receiver.
#[derive(Clone, Debug)]
pub struct Config {
    /// Name shown in the AirPlay picker.
    pub name: String,
    /// Apple model string.
    pub model: String,
    pub features: u64,
    pub status_flags: u32,
    /// Bytes the sender may push ahead of playback on a buffered stream.
    pub audio_buffer_size: u32,
}

impl Config {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            model: "RobineWake1,1".into(),
            features: DEFAULT_FEATURES,
            status_flags: DEFAULT_STATUS_FLAGS,
            audio_buffer_size: 8 * 1024 * 1024,
        }
    }
}

/// Stable identity: senders recognize a receiver by its device id, Ed25519
/// public key and public identifier, so the platform must persist it.
#[derive(Clone)]
pub struct Identity {
    /// AirPlay `deviceid`, a MAC address.
    pub device_id: [u8; 6],
    /// Ed25519 signing key seed.
    pub seed: [u8; 32],
    /// Public identifier (`pi`), a UUID.
    pub pi: [u8; 16],
}

impl Identity {
    /// A fresh identity with a locally administered device id.
    pub fn generate(random: RandomSource) -> Self {
        let mut identity = Self {
            device_id: [0; 6],
            seed: [0; 32],
            pi: [0; 16],
        };
        random(&mut identity.device_id);
        random(&mut identity.seed);
        random(&mut identity.pi);
        // Locally administered, unicast.
        identity.device_id[0] = (identity.device_id[0] & 0xFC) | 0x02;
        // UUID version 4, RFC 4122 variant.
        identity.pi[6] = (identity.pi[6] & 0x0F) | 0x40;
        identity.pi[8] = (identity.pi[8] & 0x3F) | 0x80;
        identity
    }

    /// A stable identity derived from the device MAC and a device secret,
    /// for platforms without storage for [`Identity::to_bytes`]. Transient
    /// pairing never signs with the key, so its secrecy does not matter.
    pub fn derive(device_id: [u8; 6], secret: &[u8]) -> Self {
        use sha2::{Digest, Sha256};
        let digest = |label: &[u8]| -> [u8; 32] {
            Sha256::new().chain_update(label).chain_update(device_id).chain_update(secret).finalize().into()
        };
        let mut pi: [u8; 16] = digest(b"robine-airplay-pi")[..16].try_into().expect("16 bytes");
        pi[6] = (pi[6] & 0x0F) | 0x40;
        pi[8] = (pi[8] & 0x3F) | 0x80;
        Self { device_id, seed: digest(b"robine-airplay-key"), pi }
    }

    /// `AA:BB:CC:DD:EE:FF`.
    pub fn device_id_text(&self) -> String {
        let parts: Vec<String> = self
            .device_id
            .iter()
            .map(|byte| alloc::format!("{byte:02X}"))
            .collect();
        parts.join(":")
    }

    /// Lowercase hyphenated UUID.
    pub fn pi_text(&self) -> String {
        let hex = hex::encode(self.pi);
        alloc::format!(
            "{}-{}-{}-{}-{}",
            &hex[0..8],
            &hex[8..12],
            &hex[12..16],
            &hex[16..20],
            &hex[20..32]
        )
    }

    pub fn public_key(&self) -> [u8; 32] {
        SigningKey::from_bytes(&self.seed).verifying_key().to_bytes()
    }

    /// Serialized form for the platform's storage (54 bytes).
    pub fn to_bytes(&self) -> [u8; 54] {
        let mut bytes = [0u8; 54];
        bytes[..6].copy_from_slice(&self.device_id);
        bytes[6..38].copy_from_slice(&self.seed);
        bytes[38..].copy_from_slice(&self.pi);
        bytes
    }

    pub fn from_bytes(bytes: &[u8]) -> Option<Self> {
        let bytes: &[u8; 54] = bytes.try_into().ok()?;
        Some(Self {
            device_id: bytes[..6].try_into().ok()?,
            seed: bytes[6..38].try_into().ok()?,
            pi: bytes[38..].try_into().ok()?,
        })
    }
}
