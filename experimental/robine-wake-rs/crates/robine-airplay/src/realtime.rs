//! Control channel of a realtime stream: UDP datagrams on the `control` port
//! announced in `SETUP`, both ways.
//!
//! - `0xD7` sync (sender → receiver), about once a second: the PTP time at
//!   which an RTP frame plays, which anchors the stream like
//!   `SETRATEANCHORTIME` anchors a buffered one.
//! - `0xD5` resend request (receiver → sender): missing sequence numbers.
//! - `0xD6` resent packet (sender → receiver): a 4-byte header, then the
//!   original audio packet.
//!
//! Layouts follow Shairport Sync (`rtp.c`, AirPlay 2 control receiver).

use crate::ptp::Anchor;

const SYNC: u8 = 0xD7;
const RESEND_REQUEST: u8 = 0xD5;
const RESENT: u8 = 0xD6;

/// Frames subtracted from the sync frame to get the frame playing at the
/// sync time. Empirical, from Shairport Sync (0.25 s at 44.1 kHz); to check
/// against a reference speaker.
pub const ANCHOR_CORRECTION: u32 = 11_035;

/// A `0xD7` sync packet.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Sync {
    /// Frame playing at `network_ns`, before [`ANCHOR_CORRECTION`].
    pub rtp_time: u32,
    /// PTP time, in nanoseconds.
    pub network_ns: i64,
    /// Frame the sender is sending at `network_ns`.
    pub sent_rtp_time: u32,
    /// PTP clock identity of the timeline.
    pub clock: u64,
}

impl Sync {
    pub fn parse(packet: &[u8]) -> Option<Self> {
        let packet = packet.get(..28).filter(|packet| packet[1] == SYNC)?;
        let word = |at: usize| u32::from_be_bytes(packet[at..at + 4].try_into().expect("4 bytes"));
        let long = |at: usize| u64::from_be_bytes(packet[at..at + 8].try_into().expect("8 bytes"));
        Some(Self {
            rtp_time: word(4),
            network_ns: long(8) as i64,
            sent_rtp_time: word(16),
            clock: long(20),
        })
    }

    pub fn anchor(&self) -> Anchor {
        Anchor { rtp_time: self.rtp_time.wrapping_sub(ANCHOR_CORRECTION), network_ns: self.network_ns }
    }

    /// Frames between sending and playing, as the sender sees it.
    pub fn latency(&self) -> u32 {
        self.sent_rtp_time.wrapping_sub(self.rtp_time)
    }
}

/// Asks the sender for `count` packets from sequence number `first`.
pub fn resend_request(first: u16, count: u16) -> [u8; 8] {
    let [first_hi, first_lo] = first.to_be_bytes();
    let [count_hi, count_lo] = count.to_be_bytes();
    [0x80, RESEND_REQUEST, 0x00, 0x01, first_hi, first_lo, count_hi, count_lo]
}

/// The audio packet inside a `0xD6` resent packet, to open like one from
/// the data port.
pub fn resent_packet(packet: &[u8]) -> Option<&[u8]> {
    packet.get(4..).filter(|audio| packet[1] == RESENT && !audio.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sync_packets_anchor_the_stream() {
        let mut packet = [0u8; 28];
        packet[..2].copy_from_slice(&[0x90, 0xD7]);
        packet[4..8].copy_from_slice(&100_000u32.to_be_bytes());
        packet[8..16].copy_from_slice(&5_000_000_000u64.to_be_bytes());
        packet[16..20].copy_from_slice(&177_175u32.to_be_bytes());
        packet[20..28].copy_from_slice(&0x1122_3344_5566_7788u64.to_be_bytes());

        let sync = Sync::parse(&packet).unwrap();
        assert_eq!(sync.clock, 0x1122_3344_5566_7788);
        assert_eq!(sync.latency(), 77_175);
        assert_eq!(sync.anchor(), Anchor { rtp_time: 100_000 - 11_035, network_ns: 5_000_000_000 });

        assert!(Sync::parse(&packet[..27]).is_none());
        packet[1] = 0xD6;
        assert!(Sync::parse(&packet).is_none());
    }

    #[test]
    fn resend_requests_and_replies() {
        assert_eq!(resend_request(0xFFFE, 3), [0x80, 0xD5, 0, 1, 0xFF, 0xFE, 0, 3]);

        let audio = [0x80, 0x60, 0x12, 0x34, 0, 0, 1, 0x60];
        let mut resent = std::vec![0x80, 0xD6, 0x00, 0x01];
        resent.extend_from_slice(&audio);
        assert_eq!(resent_packet(&resent), Some(&audio[..]));
        assert_eq!(resent_packet(&resent[..4]), None);
        resent[1] = 0xD7;
        assert_eq!(resent_packet(&resent), None);
    }
}
