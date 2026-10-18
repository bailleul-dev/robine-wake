//! Follower of the sender's PTP clock (IEEE 1588-2008, UDP 319 and 320).
//!
//! AirPlay 2 schedules audio on the sender's PTP timeline: "RTP sample N
//! plays at network time T". The sender is the PTP master and sends two-step
//! Sync then Follow_Up messages; the receiver only listens. Each pair gives
//! `master_time - local_arrival_time`, which equals the clock offset minus
//! the network delay, so the maximum over recent pairs (the least delayed)
//! estimates the offset. No Delay_Req: on a LAN the path delay is well below
//! a millisecond, far under lip-sync tolerance.

const HEADER_LEN: usize = 34;
const TIMESTAMP_LEN: usize = 10;
const SYNC: u8 = 0x0;
const FOLLOW_UP: u8 = 0x8;
/// Samples kept for the estimate (about 2 s at 8 Sync per second).
const WINDOW: usize = 16;

/// Nanoseconds of a PTP timestamp, plus the correction field.
fn timestamp_ns(packet: &[u8]) -> Option<i64> {
    let raw = packet.get(HEADER_LEN..HEADER_LEN + TIMESTAMP_LEN)?;
    let seconds = raw[..6].iter().fold(0u64, |acc, byte| (acc << 8) | u64::from(*byte));
    let nanoseconds = u32::from_be_bytes([raw[6], raw[7], raw[8], raw[9]]);
    let correction = i64::from_be_bytes(packet[8..16].try_into().ok()?) >> 16;
    Some((seconds as i64).checked_mul(1_000_000_000)? + i64::from(nanoseconds) + correction)
}

#[derive(Clone, Copy, Debug)]
struct Pending {
    clock: u64,
    sequence: u16,
    arrival_ns: i64,
}

/// Estimates `master_ns - local_ns` for one master clock.
#[derive(Debug, Default)]
pub struct PtpFollower {
    /// Master to follow (the session's `networkTimeTimelineID`); the first
    /// clock heard until one is set.
    timeline: Option<u64>,
    pending: Option<Pending>,
    samples: [i64; WINDOW],
    count: usize,
    next: usize,
}

impl PtpFollower {
    pub fn new() -> Self {
        Self::default()
    }

    /// Follows the given clock identity, forgetting any other.
    pub fn set_timeline(&mut self, clock: u64) {
        if self.timeline != Some(clock) {
            *self = Self { timeline: Some(clock), ..Self::default() };
        }
    }

    pub fn timeline(&self) -> Option<u64> {
        self.timeline
    }

    /// Feeds a PTP datagram received at `arrival_ns` on the local clock.
    /// Returns `true` when the estimate changed.
    pub fn receive(&mut self, packet: &[u8], arrival_ns: i64) -> bool {
        if packet.len() < HEADER_LEN || packet[1] & 0x0F != 2 {
            return false;
        }
        let clock = u64::from_be_bytes(packet[20..28].try_into().expect("8 bytes"));
        if *self.timeline.get_or_insert(clock) != clock {
            return false;
        }
        let sequence = u16::from_be_bytes([packet[30], packet[31]]);
        match packet[0] & 0x0F {
            SYNC => {
                let two_step = packet[6] & 0x02 != 0;
                if two_step {
                    self.pending = Some(Pending { clock, sequence, arrival_ns });
                    false
                } else {
                    timestamp_ns(packet).is_some_and(|master| self.add(master - arrival_ns))
                }
            }
            FOLLOW_UP => match self.pending.take() {
                Some(sync) if sync.clock == clock && sync.sequence == sequence => {
                    timestamp_ns(packet).is_some_and(|master| self.add(master - sync.arrival_ns))
                }
                _ => false,
            },
            _ => false,
        }
    }

    fn add(&mut self, offset: i64) -> bool {
        self.samples[self.next] = offset;
        self.next = (self.next + 1) % WINDOW;
        self.count = (self.count + 1).min(WINDOW);
        true
    }

    /// `master_ns - local_ns`, once a Sync/Follow_Up pair was received.
    pub fn offset(&self) -> Option<i64> {
        self.samples[..self.count].iter().copied().max()
    }

    /// Local time at which the master clock reads `master_ns`.
    pub fn to_local(&self, master_ns: i64) -> Option<i64> {
        Some(master_ns - self.offset()?)
    }
}

/// Ties the stream to the PTP timeline: RTP sample `rtp_time` plays when
/// the master clock reads `network_ns`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Anchor {
    pub rtp_time: u32,
    pub network_ns: i64,
}

impl Anchor {
    /// Master time at which RTP sample `rtp_time` plays. RTP time wraps; the
    /// nearest interpretation (within about 13 hours at 44.1 kHz) is used.
    pub fn master_time(&self, rtp_time: u32, sample_rate: u32) -> i64 {
        let samples = i64::from(rtp_time.wrapping_sub(self.rtp_time) as i32);
        self.network_ns + samples * 1_000_000_000 / i64::from(sample_rate)
    }
}

/// `networkTimeSecs` and `networkTimeFrac` (a 64-bit fraction of a second)
/// as nanoseconds.
pub fn network_time_ns(seconds: i64, fraction: u64) -> i64 {
    seconds * 1_000_000_000 + ((u128::from(fraction) * 1_000_000_000) >> 64) as i64
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::vec::Vec;

    fn message(kind: u8, clock: u64, sequence: u16, two_step: bool, master_ns: i64) -> Vec<u8> {
        let mut packet = std::vec![0u8; HEADER_LEN + TIMESTAMP_LEN];
        packet[0] = kind;
        packet[1] = 2;
        packet[6] = if two_step { 0x02 } else { 0 };
        packet[20..28].copy_from_slice(&clock.to_be_bytes());
        packet[30..32].copy_from_slice(&sequence.to_be_bytes());
        let seconds = (master_ns / 1_000_000_000) as u64;
        packet[34..40].copy_from_slice(&seconds.to_be_bytes()[2..]);
        packet[40..44].copy_from_slice(&((master_ns % 1_000_000_000) as u32).to_be_bytes());
        packet
    }

    #[test]
    fn two_step_pairs_give_the_offset_of_the_least_delayed_sample() {
        let mut follower = PtpFollower::new();
        let clock = 4_098_625_066_737_139_720;
        // Master is 98 478 s ahead of the local clock; delays of 3, 1 and 2 ms.
        let skew = 98_478_000_000_000i64;
        for (sequence, (local, delay)) in [(1_000_000_000i64, 3_000_000i64), (1_125_000_000, 1_000_000), (1_250_000_000, 2_000_000)]
            .into_iter()
            .enumerate()
        {
            let sent_master = local + skew;
            let arrival = local + delay;
            assert!(!follower.receive(&message(SYNC, clock, sequence as u16, true, 0), arrival));
            assert!(follower.receive(&message(FOLLOW_UP, clock, sequence as u16, false, sent_master), arrival + 50_000));
        }
        assert_eq!(follower.offset(), Some(skew - 1_000_000));
        assert_eq!(follower.to_local(skew + 5_000_000_000), Some(5_001_000_000));
    }

    #[test]
    fn other_masters_and_mismatched_follow_ups_are_ignored() {
        let mut follower = PtpFollower::new();
        follower.set_timeline(7);
        assert!(!follower.receive(&message(SYNC, 8, 1, false, 5), 1));
        follower.receive(&message(SYNC, 7, 1, true, 0), 10);
        assert!(!follower.receive(&message(FOLLOW_UP, 7, 2, false, 100), 20));
        assert_eq!(follower.offset(), None);
    }

    #[test]
    fn anchors_place_samples_on_the_master_timeline() {
        let anchor = Anchor { rtp_time: u32::MAX - 43_099, network_ns: 1_000_000_000 };
        // 44 100 samples later (across the RTP wrap): one second later.
        assert_eq!(anchor.master_time(1_000, 44_100), 2_000_000_000);
        assert_eq!(anchor.master_time(u32::MAX - 43_099 - 44_100, 44_100), 0);
    }

    #[test]
    fn network_time_fraction_is_converted() {
        assert_eq!(network_time_ns(2, 1 << 63), 2_500_000_000);
        // Values from a real SETRATEANCHORTIME.
        assert_eq!(network_time_ns(98_478, 1_117_457_639_131_840_512), 98_478_060_577_500);
    }
}
