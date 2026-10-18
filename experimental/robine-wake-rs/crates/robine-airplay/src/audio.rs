//! Audio packets of both stream types.
//!
//! - Realtime (type 96): one UDP datagram per ALAC frame, RTP header.
//! - Buffered (type 103): TCP blocks `[u16 BE length incl. itself][packet]`;
//!   the packet header carries a 24-bit sequence number in bytes 1..4.
//!
//! Either packet is a 12-byte header followed by the frame sealed with
//! ChaCha20-Poly1305 under the stream key `shk`. The tag (16 bytes) and an
//! 8-byte nonce trail the ciphertext; the authenticated data is header bytes
//! 4..12 (timestamp and SSRC).

use alloc::vec::Vec;

use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};

const HEADER_LEN: usize = 12;
const TAG_LEN: usize = 16;
const NONCE_LEN: usize = 8;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RtpHeader {
    pub payload_type: u8,
    pub marker: bool,
    pub sequence: u16,
    /// Position of the first sample, in samples.
    pub timestamp: u32,
    pub ssrc: u32,
}

impl RtpHeader {
    pub fn parse(packet: &[u8]) -> Option<Self> {
        let header = packet.get(..HEADER_LEN)?;
        // RTP version 2.
        if header[0] >> 6 != 2 {
            return None;
        }
        Some(Self {
            payload_type: header[1] & 0x7F,
            marker: header[1] & 0x80 != 0,
            sequence: u16::from_be_bytes([header[2], header[3]]),
            timestamp: u32::from_be_bytes([header[4], header[5], header[6], header[7]]),
            ssrc: u32::from_be_bytes([header[8], header[9], header[10], header[11]]),
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BufferedHeader {
    /// 24-bit sequence number, the unit of `FLUSHBUFFERED`.
    pub sequence: u32,
    pub timestamp: u32,
    pub ssrc: u32,
}

impl BufferedHeader {
    pub fn parse(packet: &[u8]) -> Option<Self> {
        let header = packet.get(..HEADER_LEN)?;
        let word = |at: usize| u32::from_be_bytes([header[at], header[at + 1], header[at + 2], header[at + 3]]);
        Some(Self { sequence: word(0) & 0xFF_FFFF, timestamp: word(4), ssrc: word(8) })
    }
}

/// Splits buffered-stream bytes into packets. Returns the packets and the
/// number of bytes consumed; a trailing partial block stays for later.
pub fn split_buffered(input: &[u8]) -> (Vec<&[u8]>, usize) {
    let mut packets = Vec::new();
    let mut position = 0;
    while let Some(length) = input.get(position..position + 2) {
        let length = usize::from(u16::from_be_bytes([length[0], length[1]]));
        let Some(packet) = input.get(position + 2..position + length).filter(|_| length >= 2) else {
            break;
        };
        packets.push(packet);
        position += length;
    }
    (packets, position)
}

/// Opens the audio packets of one stream.
pub struct StreamCipher {
    cipher: ChaCha20Poly1305,
}

impl StreamCipher {
    pub fn new(key: &[u8; 32]) -> Self {
        Self { cipher: ChaCha20Poly1305::new(Key::from_slice(key)) }
    }

    /// Header and decrypted frame of a realtime packet; `None` if the packet
    /// is malformed or fails authentication.
    pub fn open(&self, packet: &[u8]) -> Option<(RtpHeader, Vec<u8>)> {
        let header = RtpHeader::parse(packet)?;
        Some((header, self.open_payload(packet)?))
    }

    /// Header and decrypted frame of a buffered packet.
    pub fn open_buffered(&self, packet: &[u8]) -> Option<(BufferedHeader, Vec<u8>)> {
        let header = BufferedHeader::parse(packet)?;
        Some((header, self.open_payload(packet)?))
    }

    fn open_payload(&self, packet: &[u8]) -> Option<Vec<u8>> {
        if packet.len() < HEADER_LEN + TAG_LEN + NONCE_LEN {
            return None;
        }
        let (sealed, nonce) = packet[HEADER_LEN..].split_at(packet.len() - HEADER_LEN - NONCE_LEN);
        let mut full_nonce = [0u8; 12];
        full_nonce[4..].copy_from_slice(nonce);
        self.cipher
            .decrypt(Nonce::from_slice(&full_nonce), Payload { msg: sealed, aad: &packet[4..HEADER_LEN] })
            .ok()
    }

    /// Builds a packet the way a sender does, for tests and test senders.
    pub fn seal(&self, header: &[u8; 12], nonce: [u8; 8], frame: &[u8]) -> Vec<u8> {
        let mut full_nonce = [0u8; 12];
        full_nonce[4..].copy_from_slice(&nonce);
        let sealed = self
            .cipher
            .encrypt(Nonce::from_slice(&full_nonce), Payload { msg: frame, aad: &header[4..] })
            .expect("ChaCha20-Poly1305 encryption does not fail");
        let mut packet = header.to_vec();
        packet.extend_from_slice(&sealed);
        packet.extend_from_slice(&nonce);
        packet
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sealed_packets_open_and_tampering_fails() {
        let cipher = StreamCipher::new(&[7; 32]);
        let header = [0x80, 0x60, 0x12, 0x34, 0, 0, 0x01, 0x60, 0xAA, 0xBB, 0xCC, 0xDD];
        let packet = cipher.seal(&header, [1, 2, 3, 4, 5, 6, 7, 8], b"alac frame");
        let (rtp, frame) = cipher.open(&packet).unwrap();
        assert_eq!((rtp.sequence, rtp.timestamp, rtp.payload_type), (0x1234, 352, 0x60));
        assert_eq!(frame, b"alac frame");

        let mut forged = packet.clone();
        forged[6] ^= 1; // timestamp is authenticated
        assert!(cipher.open(&forged).is_none());
        assert!(StreamCipher::new(&[8; 32]).open(&packet).is_none());
    }

    #[test]
    fn buffered_blocks_are_split_and_opened() {
        let cipher = StreamCipher::new(&[9; 32]);
        let header = [0x80, 0x01, 0x02, 0x03, 0, 0, 0x04, 0x00, 1, 2, 3, 4];
        let packet = cipher.seal(&header, [8; 8], b"aac frame");
        let mut stream = Vec::new();
        for _ in 0..2 {
            stream.extend_from_slice(&((packet.len() + 2) as u16).to_be_bytes());
            stream.extend_from_slice(&packet);
        }
        let (packets, used) = split_buffered(&stream[..stream.len() - 5]);
        assert_eq!((packets.len(), used), (1, packet.len() + 2));
        let (header, frame) = cipher.open_buffered(packets[0]).unwrap();
        assert_eq!((header.sequence, header.timestamp, frame.as_slice()), (0x010203, 1024, &b"aac frame"[..]));
        assert_eq!(split_buffered(&stream).0.len(), 2);
    }
}
