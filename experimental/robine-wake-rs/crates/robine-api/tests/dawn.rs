//! Artificial dawn on the LED strip (00-002).

use robine_api::{Dawn, Rgb};

const PIXELS: usize = 60;

fn dawn() -> Dawn {
    Dawn { started_ms: 1_000, duration_ms: 60_000, max_brightness: 100.0 }
}

fn strip(dawn: &Dawn, monotonic_ms: u64) -> Vec<Rgb> {
    (0..PIXELS).map(|index| dawn.pixel_at(monotonic_ms, index, PIXELS)).collect()
}

fn lit(pixels: &[Rgb]) -> usize {
    pixels.iter().filter(|pixel| **pixel != Rgb::OFF).count()
}

#[test]
fn starts_with_one_faint_orange_pixel() {
    let pixels = strip(&dawn(), 1_000);
    assert_eq!(lit(&pixels), 1);
    let sun = pixels[PIXELS / 2];
    assert!(sun.r > 0 && sun.r <= 10, "{sun:?}");
    assert!(sun.g > 0 && sun.g < sun.r, "orange, not red: {sun:?}");
    assert_eq!(sun.b, 0);
}

#[test]
fn spreads_from_the_centre_with_a_gradient() {
    let pixels = strip(&dawn(), 1_000 + 25_000);
    let lit_count = lit(&pixels);
    assert!(lit_count > 1 && lit_count < PIXELS, "{lit_count}");
    let centre = pixels[PIXELS / 2];
    let side = pixels[PIXELS / 2 + 5];
    assert!(centre.r >= side.r && centre.g > side.g, "{centre:?} vs {side:?}");
}

#[test]
fn ends_as_a_uniform_daylight_white() {
    let pixels = strip(&dawn(), 1_000 + 60_000);
    assert!(pixels.iter().all(|pixel| *pixel == pixels[0]), "{pixels:?}");
    let white = pixels[0];
    assert_eq!(white.r, 255);
    assert!(white.g > 200 && white.b > 150, "{white:?}");
}

#[test]
fn cools_down_as_it_rises() {
    let dawn = dawn();
    let blue_ratio = |ms: u64| {
        let sun = dawn.pixel_at(ms, PIXELS / 2, PIXELS);
        f32::from(sun.b) / f32::from(sun.r.max(1))
    };
    let samples: Vec<f32> = [20_000, 35_000, 50_000, 61_000].iter().map(|ms| blue_ratio(1_000 + ms)).collect();
    assert!(samples.windows(2).all(|pair| pair[0] <= pair[1]), "{samples:?}");
}

#[test]
fn holds_daylight_and_honours_the_brightness_cap() {
    let capped = Dawn { max_brightness: 50.0, ..dawn() };
    let sun = capped.pixel_at(1_000 + 3_600_000, 0, PIXELS);
    assert_eq!(sun.r, 128);
}
