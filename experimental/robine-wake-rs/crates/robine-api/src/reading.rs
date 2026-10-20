//! Evening reading light on a vertical LED strip, pixel 0 at the bottom: a
//! warm white low down to read by, turning orange then red towards the top,
//! where it would reach the eyes. At the end of the chosen time it blends
//! into a sunset, to fall asleep, or fades out when there is none.

use crate::dawn::keyframe_color;
use crate::light::Rgb;
use crate::sunset::Sunset;

/// Colour from the bottom (0) to the top (1) of the strip.
/// No blue at all before sleep, which the WS2812B blue die would also make
/// look cold: the bottom is a candle flame, red and green only.
const KEYFRAMES: [(f32, Rgb); 4] = [
    (0.00, Rgb { r: 255, g: 80, b: 0 }), // ≈ 1900 K, candle flame
    (0.55, Rgb { r: 255, g: 68, b: 0 }), // ≈ 1800 K
    (0.75, Rgb { r: 255, g: 45, b: 0 }), // orange
    (1.00, Rgb { r: 255, g: 12, b: 0 }), // red
];

/// Intensity at the top, in share of the bottom's: the red stays dim.
const TOP_INTENSITY: f32 = 0.4;

/// Fade from dark when the reading light comes on.
const FADE_IN_MS: u64 = 3_000;

/// Blend into the first frame of the sunset, before the reading time ends.
const BLEND_MS: u64 = 60_000;

/// Fade to dark at the end of the reading time, without a sunset.
const FADE_OUT_MS: u64 = 5_000;

/// Sunset after the reading time, unless the command sets another.
pub const DEFAULT_SUNSET_MS: u64 = 30 * 60_000;

/// A reading light of `duration_ms`, then a sunset of `sunset_ms` (none at 0).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Reading {
    /// Monotonic start of the reading light.
    pub started_ms: u64,
    pub duration_ms: u64,
    pub sunset_ms: u64,
    /// Ceiling of the light, in percent, to stay within the supply.
    pub max_brightness: f32,
}

impl Reading {
    /// The reading light and the sunset after it.
    pub fn total_ms(&self) -> u64 {
        self.duration_ms + self.sunset_ms
    }

    /// The sunset that follows the reading time.
    pub fn sunset(&self) -> Sunset {
        Sunset {
            started_ms: self.started_ms + self.duration_ms,
            duration_ms: self.sunset_ms,
            max_brightness: self.max_brightness,
        }
    }

    /// Colour of pixel `index` on a strip of `count` pixels, 0 at the bottom.
    pub fn pixel_at(&self, monotonic_ms: u64, index: usize, count: usize) -> Rgb {
        let elapsed = monotonic_ms.saturating_sub(self.started_ms);
        if elapsed >= self.duration_ms {
            return self.sunset().pixel_at(monotonic_ms, index, count);
        }
        let left = self.duration_ms - elapsed;
        let mut level = (elapsed as f32 / FADE_IN_MS as f32).min(1.0);
        if self.sunset_ms == 0 {
            level = level.min(left as f32 / FADE_OUT_MS as f32);
        }
        let light = self.light_at(index, count, level);
        if left >= BLEND_MS || self.sunset_ms == 0 {
            return light;
        }
        let sunset = self.sunset().pixel_at(self.started_ms + self.duration_ms, index, count);
        mix(sunset, light, left as f32 / BLEND_MS as f32)
    }

    fn light_at(&self, index: usize, count: usize, level: f32) -> Rgb {
        let height = if count > 1 { index as f32 / (count - 1) as f32 } else { 0.0 };
        let color = keyframe_color(&KEYFRAMES, height);
        // Full light up to the orange, then dimming towards the red top.
        let fall = ((height - 0.55) / 0.45).clamp(0.0, 1.0);
        let scale = level * (1.0 - (1.0 - TOP_INTENSITY) * fall) * self.max_brightness.clamp(0.0, 100.0) / 100.0;
        let channel = |value: u8| (f32::from(value) * scale + 0.5) as u8;
        Rgb {
            r: channel(color.r),
            g: channel(color.g),
            b: channel(color.b),
        }
    }
}

/// `from` at 0, `to` at 1.
fn mix(from: Rgb, to: Rgb, t: f32) -> Rgb {
    let channel = |a: u8, b: u8| (f32::from(a) + (f32::from(b) - f32::from(a)) * t + 0.5) as u8;
    Rgb {
        r: channel(from.r, to.r),
        g: channel(from.g, to.g),
        b: channel(from.b, to.b),
    }
}
