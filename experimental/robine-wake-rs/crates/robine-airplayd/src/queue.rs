//! Encoded frames waiting for the player, in RTP time order.
//!
//! Buffered frames arrive in order over TCP. Realtime frames come over UDP:
//! they may be reordered or duplicated, and a jump in sequence numbers marks
//! lost packets to ask the sender for again (`0xD5`).

use std::collections::VecDeque;

/// Larger gaps are not worth a resend request: the frames would arrive
/// after their play time (about 0.5 s of ALAC frames).
const MAX_RESEND: u16 = 64;

pub struct Frame {
    pub sequence: u32,
    pub timestamp: u32,
    pub data: Vec<u8>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Insert {
    Queued,
    /// Queued after a gap: `count` packets from sequence `first` are missing.
    Missing { first: u16, count: u16 },
    /// Older than a frame already handed to the player.
    Late,
    Duplicate,
}

/// `a` before `b` in wrapping RTP time.
pub fn before(a: u32, b: u32) -> bool {
    (a.wrapping_sub(b) as i32) < 0
}

#[derive(Default)]
pub struct FrameQueue {
    frames: VecDeque<Frame>,
    /// Newest realtime sequence number seen, queued or played.
    newest: Option<u16>,
    /// Timestamp of the last frame handed to the player.
    played: Option<u32>,
}

impl FrameQueue {
    /// A buffered frame, in order.
    pub fn push(&mut self, frame: Frame) {
        self.frames.push_back(frame);
    }

    /// A realtime frame, from the data port or resent.
    pub fn insert(&mut self, frame: Frame) -> Insert {
        if self.played.is_some_and(|played| !before(played, frame.timestamp)) {
            return Insert::Late;
        }
        let sequence = frame.sequence as u16;
        let gap = self.newest.map_or(1, |newest| sequence.wrapping_sub(newest));
        if gap == 0 {
            return Insert::Duplicate;
        }
        if gap < 0x8000 {
            self.newest = Some(sequence);
            self.frames.push_back(frame);
            let lost = gap - 1;
            return if (1..=MAX_RESEND).contains(&lost) {
                Insert::Missing { first: sequence.wrapping_sub(lost), count: lost }
            } else {
                Insert::Queued
            };
        }
        // Older than the newest: a resent or reordered packet.
        let at = self.frames.partition_point(|queued| before(queued.timestamp, frame.timestamp));
        if self.frames.get(at).is_some_and(|queued| queued.timestamp == frame.timestamp) {
            return Insert::Duplicate;
        }
        self.frames.insert(at, frame);
        Insert::Queued
    }

    pub fn pop(&mut self) -> Option<Frame> {
        let frame = self.frames.pop_front()?;
        self.played = Some(frame.timestamp);
        Some(frame)
    }

    /// Drops buffered frames before sequence `until` (`FLUSHBUFFERED`).
    pub fn flush(&mut self, until: u32) {
        self.frames.retain(|frame| frame.sequence >= until);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(sequence: u16) -> Frame {
        Frame { sequence: u32::from(sequence), timestamp: u32::from(sequence).wrapping_mul(352), data: vec![] }
    }

    fn timestamps(queue: &mut FrameQueue) -> Vec<u32> {
        std::iter::from_fn(|| queue.pop()).map(|frame| frame.timestamp / 352).collect()
    }

    #[test]
    fn realtime_frames_are_reordered_and_gaps_reported() {
        let mut queue = FrameQueue::default();
        assert_eq!(queue.insert(frame(10)), Insert::Queued);
        assert_eq!(queue.insert(frame(13)), Insert::Missing { first: 11, count: 2 });
        assert_eq!(queue.insert(frame(13)), Insert::Duplicate);
        assert_eq!(queue.insert(frame(12)), Insert::Queued);
        assert_eq!(queue.insert(frame(12)), Insert::Duplicate);
        assert_eq!(queue.insert(frame(11)), Insert::Queued);
        assert_eq!(timestamps(&mut queue), [10, 11, 12, 13]);

        // Once played, older frames are late.
        assert_eq!(queue.insert(frame(9)), Insert::Late);
        assert_eq!(queue.insert(frame(14)), Insert::Queued);
    }

    #[test]
    fn sequence_numbers_wrap_and_large_gaps_are_not_requested() {
        let mut queue = FrameQueue::default();
        queue.insert(Frame { sequence: 0xFFFF, timestamp: 1000, data: vec![] });
        assert_eq!(
            queue.insert(Frame { sequence: 1, timestamp: 1704, data: vec![] }),
            Insert::Missing { first: 0, count: 1 }
        );
        assert_eq!(queue.insert(Frame { sequence: 200, timestamp: 71_000, data: vec![] }), Insert::Queued);
    }

    #[test]
    fn flush_keeps_frames_from_the_given_sequence() {
        let mut queue = FrameQueue::default();
        (1..=5).for_each(|sequence| queue.push(frame(sequence)));
        queue.flush(4);
        assert_eq!(timestamps(&mut queue), [4, 5]);
    }
}
