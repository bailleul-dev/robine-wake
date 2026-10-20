//! Artificial dawn on an LED strip (00-002): a single faint orange pixel at
//! the centre, the sun, that spreads along the strip, brightens and cools
//! like a real sunrise, then ends as a uniform daylight white.
//!
//! The colour follows the sun from the horizon (≈ 1800 K, deep orange) to
//! morning daylight (≈ 5500 K). The centre is ahead of the edges, so the
//! strip shows a gradient during the rise; it flattens over the last third.

use crate::light::Rgb;

/// Colour of the sun along the dawn, from the horizon to daylight, as WS2812B
/// channel values (green and blue tamed: the green die is the most efficient).
const KEYFRAMES: [(f32, Rgb); 5] = [
    (0.00, Rgb { r: 255, g: 60, b: 0 }),    // ≈ 1800 K, sun on the horizon
    (0.25, Rgb { r: 255, g: 95, b: 8 }),    // ≈ 2200 K, orange
    (0.50, Rgb { r: 255, g: 140, b: 40 }),  // ≈ 2700 K, warm white
    (0.75, Rgb { r: 255, g: 185, b: 105 }), // ≈ 3800 K
    (1.00, Rgb { r: 255, g: 228, b: 195 }), // ≈ 5500 K, morning daylight
];

/// Intensity of the first pixel: faint, yet enough for the orange to show
/// through the 8-bit channels.
pub(crate) const START_INTENSITY: f32 = 0.03;

/// A dawn in progress, or finished and held at full daylight.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Dawn {
    /// Monotonic start of the dawn.
    pub started_ms: u64,
    pub duration_ms: u64,
    /// Ceiling of the final white, in percent, to stay within the supply.
    pub max_brightness: f32,
}

impl Dawn {
    /// Progress from 0 (first pixel) to 1 (full daylight).
    pub fn progress_at(&self, monotonic_ms: u64) -> f32 {
        if self.duration_ms == 0 {
            return 1.0;
        }
        let elapsed = monotonic_ms.saturating_sub(self.started_ms);
        (elapsed as f32 / self.duration_ms as f32).min(1.0)
    }

    /// Colour of pixel `index` on a strip of `count` pixels.
    pub fn pixel_at(&self, monotonic_ms: u64, index: usize, count: usize) -> Rgb {
        let p = self.progress_at(monotonic_ms);
        let weight = weight(p, index, count);
        if weight <= 0.0 {
            return Rgb::OFF;
        }
        // The edges lag behind the sun, warmer, until the strip flattens.
        let color = keyframe_color(&KEYFRAMES, p * (0.55 + 0.45 * weight));
        let intensity = intensity(p);
        let scale = intensity * weight * self.max_brightness.clamp(0.0, 100.0) / 100.0;
        let channel = |value: u8| (f32::from(value) * scale + 0.5) as u8;
        Rgb {
            r: channel(color.r),
            g: channel(color.g),
            b: channel(color.b),
        }
    }
}

/// Intensity of the sun at height `p`, from one faint pixel to full light.
/// Cubic: slow near the horizon, as the eye perceives light (00-002).
pub(crate) fn intensity(p: f32) -> f32 {
    START_INTENSITY + (1.0 - START_INTENSITY) * p * p * p
}

/// Share of the sun a pixel receives, from 0 (dark) to 1 (centre), at sun
/// height `p` (0 one pixel on the horizon, 1 uniform over the strip).
pub(crate) fn weight(p: f32, index: usize, count: usize) -> f32 {
    if count == 0 {
        return 0.0;
    }
    let centre = (count / 2) as f32;
    let distance = (index as f32 - centre).abs();
    // The lit zone grows from one pixel to past both ends by 70 % of the dawn.
    let radius = 0.5 + smoothstep(p / 0.7) * (centre + 1.0) * 1.5;
    let falloff = (1.0 - distance / radius).max(0.0);
    // Over the last third the gradient flattens into a uniform daylight.
    let flat = smoothstep((p - 0.65) / 0.35);
    if falloff <= 0.0 && flat <= 0.0 {
        return 0.0;
    }
    falloff + (1.0 - falloff) * flat
}

/// Colour at position `k` (0 to 1) between `keyframes`, sorted from 0 to 1.
pub(crate) fn keyframe_color(keyframes: &[(f32, Rgb)], k: f32) -> Rgb {
    let k = k.clamp(0.0, 1.0);
    let upper = keyframes.iter().position(|(at, _)| *at >= k).unwrap_or(keyframes.len() - 1).max(1);
    let (from_at, from) = keyframes[upper - 1];
    let (to_at, to) = keyframes[upper];
    let t = (k - from_at) / (to_at - from_at);
    let mix = |a: u8, b: u8| (f32::from(a) + (f32::from(b) - f32::from(a)) * t + 0.5) as u8;
    Rgb {
        r: mix(from.r, to.r),
        g: mix(from.g, to.g),
        b: mix(from.b, to.b),
    }
}

fn smoothstep(x: f32) -> f32 {
    let x = x.clamp(0.0, 1.0);
    x * x * (3.0 - 2.0 * x)
}
