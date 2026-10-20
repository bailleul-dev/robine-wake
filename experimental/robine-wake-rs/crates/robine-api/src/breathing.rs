//! Guided breathing on an LED strip (30-003): a dim red sliding window. With
//! empty lungs only the centre pixel glows; on the inhale a window slides
//! from the centre to each end, widening linearly up to 10 pixels per side,
//! and slides back on the exhale. It stays dim at its peak so it does not
//! keep the sleeper awake.

use crate::light::Rgb;

/// Red level of the glow, empty lungs and full lungs, out of 255: barely on,
/// then a little brighter.
const MIN_LEVEL: f32 = 2.0;
const MAX_LEVEL: f32 = 18.0;
/// Width of the window on each side, in pixels: the centre pixel alone when
/// the lungs are empty, then growing linearly to this at the ends.
const MAX_WINDOW: f32 = 10.0;

/// Phase durations of one breath, in milliseconds, written `hold empty -
/// inhale - hold full - exhale` in seconds: `0-4-0-6` for cardiac coherence.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cadence {
    pub hold_empty_ms: u64,
    pub inhale_ms: u64,
    pub hold_full_ms: u64,
    pub exhale_ms: u64,
}

impl Cadence {
    /// Cardiac coherence: inhale 4 s, exhale 6 s, six breaths a minute.
    pub const COHERENCE: Cadence = Cadence { hold_empty_ms: 0, inhale_ms: 4_000, hold_full_ms: 0, exhale_ms: 6_000 };

    /// Parses `hold empty-inhale-hold full-exhale`, in seconds (decimals
    /// allowed). A breath needs an inhale and an exhale.
    pub fn parse(text: &str) -> Option<Cadence> {
        let mut parts = text.trim().split('-').map(|part| {
            let seconds: f32 = part.trim().parse().ok()?;
            (seconds.is_finite() && (0.0..=60.0).contains(&seconds)).then_some((seconds * 1000.0 + 0.5) as u64)
        });
        let cadence = Cadence {
            hold_empty_ms: parts.next()??,
            inhale_ms: parts.next()??,
            hold_full_ms: parts.next()??,
            exhale_ms: parts.next()??,
        };
        (parts.next().is_none() && cadence.inhale_ms > 0 && cadence.exhale_ms > 0).then_some(cadence)
    }

    pub fn breath_ms(&self) -> u64 {
        self.hold_empty_ms + self.inhale_ms + self.hold_full_ms + self.exhale_ms
    }

    /// Fullness of the lungs at `elapsed_ms` into the session, from 0 to 1.
    pub fn fullness_at(&self, elapsed_ms: u64) -> f32 {
        let mut t = elapsed_ms % self.breath_ms().max(1);
        if t < self.hold_empty_ms {
            return 0.0;
        }
        t -= self.hold_empty_ms;
        if t < self.inhale_ms {
            return t as f32 / self.inhale_ms as f32;
        }
        t -= self.inhale_ms;
        if t < self.hold_full_ms {
            return 1.0;
        }
        t -= self.hold_full_ms;
        1.0 - t as f32 / self.exhale_ms as f32
    }
}

/// A breathing session, from its first inhale until the next command.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Breathing {
    /// Monotonic start of the first breath.
    pub started_ms: u64,
    pub cadence: Cadence,
}

impl Breathing {
    /// Colour of pixel `index` on a strip of `count` pixels.
    pub fn pixel_at(&self, monotonic_ms: u64, index: usize, count: usize) -> Rgb {
        if count == 0 {
            return Rgb::OFF;
        }
        let fullness = self.cadence.fullness_at(monotonic_ms.saturating_sub(self.started_ms));
        let centre = (count / 2) as f32;
        let distance = (index as f32 - centre).abs();
        // Window [front - width, front] in pixels from the centre: its front
        // reaches the farthest end when the lungs are full.
        let front = fullness * centre;
        let width = 1.0 + (MAX_WINDOW - 1.0) * fullness;
        // Share of the pixel inside the window, so it slides smoothly.
        let coverage = ((distance + 0.5).min(front + 0.5) - (distance - 0.5).max(front + 0.5 - width)).clamp(0.0, 1.0);
        let level = (MIN_LEVEL + (MAX_LEVEL - MIN_LEVEL) * fullness) * coverage;
        Rgb { r: (level + 0.5) as u8, g: 0, b: 0 }
    }
}
