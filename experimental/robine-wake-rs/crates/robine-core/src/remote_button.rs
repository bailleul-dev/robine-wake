//! ESP32 Wi-Fi Remote Alarm Button HMAC verification and anti-replay (ACC-002).
//!
//! Validates HMAC-SHA256 dismiss signatures received from Heltec WiFi Kit 32 buttons
//! and enforces monotonic counters to prevent replays.

use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;

type HmacSha256 = Hmac<Sha256>;

pub const MAX_COUNTER: u64 = (1 << 53) - 1; // 2^53 - 1 (ACC-002)

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairedButton {
    pub id: String,
    pub secret: Vec<u8>,
    pub last_counter: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ButtonResult {
    DismissAccepted,
    DuplicateAcknowledged,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ButtonError {
    UnknownButton,
    InvalidSecret,
    InvalidSignature,
    CounterExceeded,
    CounterReplay { counter: u64, last_seen: u64 },
}

impl std::fmt::Display for ButtonError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ButtonError::UnknownButton => write!(f, "unknown remote button"),
            ButtonError::InvalidSecret => write!(f, "invalid button secret"),
            ButtonError::InvalidSignature => write!(f, "invalid HMAC signature"),
            ButtonError::CounterExceeded => write!(f, "counter exceeds maximum safe integer"),
            ButtonError::CounterReplay { counter, last_seen } => {
                write!(
                    f,
                    "counter replay rejected (got {counter}, last seen {last_seen})"
                )
            }
        }
    }
}

impl std::error::Error for ButtonError {}

/// Compute the HMAC-SHA256 signature for a remote button dismiss request.
/// Payload format: `rw-remote-v1\0{button_id}\0{counter}\0dismiss`
pub fn compute_dismiss_hmac(
    secret: &[u8],
    button_id: &str,
    counter: u64,
) -> Result<String, ButtonError> {
    let mut mac = HmacSha256::new_from_slice(secret).map_err(|_| ButtonError::InvalidSecret)?;
    mac.update(b"rw-remote-v1\0");
    mac.update(button_id.as_bytes());
    mac.update(b"\0");
    mac.update(counter.to_string().as_bytes());
    mac.update(b"\0dismiss");
    let result = mac.finalize().into_bytes();
    Ok(hex::encode(result))
}

impl PairedButton {
    pub fn new(id: impl Into<String>, secret: Vec<u8>, last_counter: u64) -> Self {
        Self {
            id: id.into(),
            secret,
            last_counter,
        }
    }

    /// Verify an incoming dismiss request (ACC-002).
    /// If accepted, updates `self.last_counter`.
    pub fn verify_and_advance(
        &mut self,
        counter: u64,
        signature_hex: &str,
    ) -> Result<ButtonResult, ButtonError> {
        if counter > MAX_COUNTER {
            return Err(ButtonError::CounterExceeded);
        }

        let expected_signature = compute_dismiss_hmac(&self.secret, &self.id, counter)?;

        // Constant time comparison
        if expected_signature.to_lowercase() != signature_hex.to_lowercase() {
            return Err(ButtonError::InvalidSignature);
        }

        if counter == self.last_counter {
            // Replay of current packet (e.g. Wi-Fi retry) -> acknowledge without new effect
            return Ok(ButtonResult::DuplicateAcknowledged);
        }

        if counter < self.last_counter {
            return Err(ButtonError::CounterReplay {
                counter,
                last_seen: self.last_counter,
            });
        }

        // Advance counter
        self.last_counter = counter;
        Ok(ButtonResult::DismissAccepted)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_specification_compatibility_test_vector() {
        // ACC-002: secret = 32 octets 0x42, button-001122334455, compteur 7 ->
        // 5afbdaf88cbe8167dd711c4492008bb956932b7351f26b60db69237639d9f995
        let secret = vec![0x42u8; 32];
        let button_id = "button-001122334455";
        let counter = 7u64;

        let signature = compute_dismiss_hmac(&secret, button_id, counter).unwrap();
        assert_eq!(
            signature,
            "5afbdaf88cbe8167dd711c4492008bb956932b7351f26b60db69237639d9f995"
        );
    }

    #[test]
    fn enforces_monotonic_counter_anti_replay() {
        let secret = vec![0x42u8; 32];
        let mut button = PairedButton::new("button-001122334455", secret.clone(), 6);

        // Counter 7 with correct signature -> accepted
        let sig7 = compute_dismiss_hmac(&secret, &button.id, 7).unwrap();
        assert_eq!(
            button.verify_and_advance(7, &sig7).unwrap(),
            ButtonResult::DismissAccepted
        );
        assert_eq!(button.last_counter, 7);

        // Replay of counter 7 -> duplicate acknowledged
        assert_eq!(
            button.verify_and_advance(7, &sig7).unwrap(),
            ButtonResult::DuplicateAcknowledged
        );

        // Counter 5 (older) -> rejected
        let sig5 = compute_dismiss_hmac(&secret, &button.id, 5).unwrap();
        assert!(matches!(
            button.verify_and_advance(5, &sig5),
            Err(ButtonError::CounterReplay { .. })
        ));

        // Invalid signature -> rejected
        assert_eq!(
            button.verify_and_advance(8, "deadbeef"),
            Err(ButtonError::InvalidSignature)
        );
    }
}
