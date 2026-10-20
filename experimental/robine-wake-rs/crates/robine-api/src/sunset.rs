//! Artificial sunset on an LED strip, to fall asleep: the dawn played
//! backwards without its cool half. The whole strip starts at once in a warm
//! amber poor in blue, then dims and reddens while the edges go dark first,
//! down to one red pixel at the centre that fades out.

use crate::dawn::{intensity, keyframe_color, weight};
use crate::light::Rgb;

/// Colour of the sun along the sunset, from its start to its end: never
/// colder than ≈ 2200 K.
const KEYFRAMES: [(f32, Rgb); 3] = [
    (0.0, Rgb { r: 255, g: 95, b: 0 }), // ≈ 2200 K, amber, without blue before sleep
    (0.5, Rgb { r: 255, g: 60, b: 0 }), // ≈ 1800 K, sun on the horizon
    (1.0, Rgb { r: 255, g: 15, b: 0 }), // red afterglow
];

/// Intensity at the start, in share of `max_brightness`: a calm evening
/// light, not a reading light.
const START_INTENSITY: f32 = 0.4;

/// A sunset in progress, or finished and held dark.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Sunset {
    /// Monotonic start of the sunset.
    pub started_ms: u64,
    pub duration_ms: u64,
    /// Ceiling of the light, in percent, to stay within the supply.
    pub max_brightness: f32,
}

impl Sunset {
    /// Progress from 0 (whole strip amber) to 1 (dark).
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
        if p >= 1.0 {
            return Rgb::OFF;
        }
        // Height of the sun: uniform at first, then shrinking to the centre.
        let height = 1.0 - p;
        let weight = weight(height, index, count);
        if weight <= 0.0 {
            return Rgb::OFF;
        }
        // The edges run ahead of the centre, redder.
        let color = keyframe_color(&KEYFRAMES, 1.0 - height * (0.55 + 0.45 * weight));
        // The dawn's curve backwards, down to its faint first pixel.
        let scale = START_INTENSITY * intensity(height) * weight * self.max_brightness.clamp(0.0, 100.0) / 100.0;
        let channel = |value: u8| (f32::from(value) * scale + 0.5) as u8;
        Rgb {
            r: channel(color.r),
            g: channel(color.g),
            b: channel(color.b),
        }
    }
}
