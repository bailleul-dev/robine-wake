//! Artificial sunset on the LED strip, to fall asleep.

use robine_api::{Rgb, Sunset};

const PIXELS: usize = 60;

fn sunset() -> Sunset {
    Sunset { started_ms: 1_000, duration_ms: 60_000, max_brightness: 100.0 }
}

fn strip(sunset: &Sunset, monotonic_ms: u64) -> Vec<Rgb> {
    (0..PIXELS).map(|index| sunset.pixel_at(monotonic_ms, index, PIXELS)).collect()
}

fn lit(pixels: &[Rgb]) -> usize {
    pixels.iter().filter(|pixel| **pixel != Rgb::OFF).count()
}

#[test]
fn starts_at_once_with_the_whole_strip_amber() {
    let pixels = strip(&sunset(), 1_000);
    assert!(pixels.iter().all(|pixel| *pixel == pixels[0]), "{pixels:?}");
    let amber = pixels[0];
    assert!(amber.r > 60 && amber.r < 128, "calm, not a reading light: {amber:?}");
    assert!(amber.g > 0 && amber.b == 0, "amber, without blue: {amber:?}");
}

#[test]
fn never_turns_cold() {
    let sunset = sunset();
    for ms in (0..=60_000).step_by(500) {
        for pixel in strip(&sunset, 1_000 + ms) {
            assert_eq!(pixel.b, 0, "{ms} ms: {pixel:?}");
            assert!(u16::from(pixel.g) * 2 <= u16::from(pixel.r).max(1), "{ms} ms: {pixel:?}");
        }
    }
}

#[test]
fn darkens_from_the_edges_and_reddens() {
    let sunset = sunset();
    let start = strip(&sunset, 1_000);
    let later = strip(&sunset, 1_000 + 40_000);
    assert!(lit(&later) < PIXELS, "{}", lit(&later));
    let centre = later[PIXELS / 2];
    assert!(centre.r < start[PIXELS / 2].r, "dimmer: {centre:?}");
    let green_share = |pixel: Rgb| f32::from(pixel.g) / f32::from(pixel.r.max(1));
    assert!(green_share(centre) < green_share(start[PIXELS / 2]), "redder: {centre:?}");
}

#[test]
fn fades_out_to_dark() {
    let sunset = sunset();
    let near_end = strip(&sunset, 1_000 + 57_000);
    assert!(lit(&near_end) <= 3, "{}", lit(&near_end));
    assert_eq!(lit(&strip(&sunset, 1_000 + 60_000)), 0);
    assert_eq!(lit(&strip(&sunset, 1_000 + 3_600_000)), 0);
}
