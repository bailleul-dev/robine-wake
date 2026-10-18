//! Encrypted control channel after pairing (HomeKit secure session).
//!
//! Keys: HKDF-SHA512 of the pairing secret with salt `Control-Salt`. Framing:
//! blocks of `[u16 LE length][ciphertext][16-byte tag]`, at most 1024 bytes
//! of plaintext, the length as AAD, nonce = 4 zero bytes + 64-bit LE block
//! counter, one counter per direction.

use alloc::vec::Vec;

use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
use hkdf::Hkdf;
use sha2::Sha512;

const BLOCK_MAX: usize = 1024;
const TAG_LEN: usize = 16;
const SALT: &[u8] = b"Control-Salt";
/// Key the sender writes with, so the receiver reads with it.
const SENDER_WRITE: &[u8] = b"Control-Write-Encryption-Key";
const SENDER_READ: &[u8] = b"Control-Read-Encryption-Key";

fn derive(secret: &[u8], info: &[u8]) -> ChaCha20Poly1305 {
    let mut key = [0u8; 32];
    Hkdf::<Sha512>::new(Some(SALT), secret)
        .expand(info, &mut key)
        .expect("32 bytes is a valid HKDF output");
    ChaCha20Poly1305::new(Key::from_slice(&key))
}

fn nonce(counter: u64) -> Nonce {
    let mut nonce = [0u8; 12];
    nonce[4..].copy_from_slice(&counter.to_le_bytes());
    nonce.into()
}

pub struct Sealer {
    cipher: ChaCha20Poly1305,
    counter: u64,
}

pub struct Opener {
    cipher: ChaCha20Poly1305,
    counter: u64,
}

/// Receiver side: opens what the sender writes, seals what it reads.
pub fn receiver(secret: &[u8]) -> (Sealer, Opener) {
    (
        Sealer { cipher: derive(secret, SENDER_READ), counter: 0 },
        Opener { cipher: derive(secret, SENDER_WRITE), counter: 0 },
    )
}

/// Sender side, for tests.
#[cfg(test)]
pub fn sender(secret: &[u8]) -> (Sealer, Opener) {
    (
        Sealer { cipher: derive(secret, SENDER_WRITE), counter: 0 },
        Opener { cipher: derive(secret, SENDER_READ), counter: 0 },
    )
}

impl Sealer {
    pub fn seal(&mut self, plaintext: &[u8]) -> Vec<u8> {
        let mut out = Vec::with_capacity(plaintext.len() + 32);
        for block in plaintext.chunks(BLOCK_MAX) {
            let aad = (block.len() as u16).to_le_bytes();
            let sealed = self
                .cipher
                .encrypt(&nonce(self.counter), Payload { msg: block, aad: &aad })
                .expect("ChaCha20-Poly1305 encryption does not fail");
            out.extend_from_slice(&aad);
            out.extend_from_slice(&sealed);
            self.counter += 1;
        }
        out
    }
}

impl Opener {
    /// Decrypts the complete blocks at the front of `input` into `output` and
    /// returns how many input bytes were consumed. `None` if a block fails
    /// authentication, which is fatal for the connection.
    pub fn open(&mut self, input: &[u8], output: &mut Vec<u8>) -> Option<usize> {
        let mut position = 0;
        while let Some(header) = input.get(position..position + 2) {
            let len = usize::from(u16::from_le_bytes([header[0], header[1]]));
            let end = position + 2 + len + TAG_LEN;
            let Some(sealed) = input.get(position + 2..end) else {
                break;
            };
            let plain = self
                .cipher
                .decrypt(&nonce(self.counter), Payload { msg: sealed, aad: header })
                .ok()?;
            output.extend_from_slice(&plain);
            self.counter += 1;
            position = end;
        }
        Some(position)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_directions_round_trip_across_blocks() {
        let secret = [0x11u8; 64];
        let (mut receiver_seal, mut receiver_open) = receiver(&secret);
        let (mut sender_seal, mut sender_open) = sender(&secret);

        let request: Vec<u8> = (0..2500).map(|i| i as u8).collect();
        let sealed = sender_seal.seal(&request);
        let mut plain = Vec::new();
        // A partial trailing block stays unconsumed.
        assert_eq!(receiver_open.open(&sealed[..sealed.len() - 3], &mut plain), Some(2 * (2 + 1024 + 16)));
        let consumed = 2 * (2 + 1024 + 16);
        assert_eq!(receiver_open.open(&sealed[consumed..], &mut plain), Some(sealed.len() - consumed));
        assert_eq!(plain, request);

        let reply = receiver_seal.seal(b"RTSP/1.0 200 OK\r\n\r\n");
        let mut plain = Vec::new();
        sender_open.open(&reply, &mut plain).unwrap();
        assert_eq!(plain, b"RTSP/1.0 200 OK\r\n\r\n");
    }

    #[test]
    fn tampering_is_detected() {
        let (mut sender_seal, _) = sender(&[1; 64]);
        let (_, mut receiver_open) = receiver(&[1; 64]);
        let mut sealed = sender_seal.seal(b"GET /info");
        sealed[5] ^= 1;
        assert_eq!(receiver_open.open(&sealed, &mut Vec::new()), None);
    }
}
