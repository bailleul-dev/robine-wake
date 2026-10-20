//! Guided breathing on the LED strip (30-003).

use robine_api::{Breathing, Cadence, Rgb};

const PIXELS: usize = 60;

fn session(cadence: Cadence) -> Breathing {
    Breathing { started_ms: 1_000, cadence }
}

fn strip(breathing: &Breathing, monotonic_ms: u64) -> Vec<Rgb> {
    (0..PIXELS).map(|index| breathing.pixel_at(monotonic_ms, index, PIXELS)).collect()
}

fn lit(pixels: &[Rgb]) -> usize {
    pixels.iter().filter(|pixel| **pixel != Rgb::OFF).count()
}

#[test]
fn parses_the_cadence_notation() {
    assert_eq!(Cadence::parse("0-4-0-6"), Some(Cadence::COHERENCE));
    assert_eq!(
        Cadence::parse(" 4-4-4-4 "),
        Some(Cadence { hold_empty_ms: 4_000, inhale_ms: 4_000, hold_full_ms: 4_000, exhale_ms: 4_000 })
    );
    assert_eq!(Cadence::parse("0-4.5-0-5.5").map(|c| c.inhale_ms), Some(4_500));
    for invalid in ["", "4-6", "0-0-0-6", "0-4-0-0", "0-4-0-6-1", "0-x-0-6", "0--4-0-6", "0-61-0-6"] {
        assert_eq!(Cadence::parse(invalid), None, "{invalid}");
    }
}

#[test]
fn follows_the_breath() {
    let cadence = Cadence::COHERENCE;
    assert_eq!(cadence.fullness_at(0), 0.0);
    assert!((cadence.fullness_at(2_000) - 0.5).abs() < 1e-6);
    assert_eq!(cadence.fullness_at(4_000), 1.0);
    assert!((cadence.fullness_at(7_000) - 0.5).abs() < 1e-6);
    assert_eq!(cadence.fullness_at(10_000), 0.0);
    assert!((cadence.fullness_at(12_000) - 0.5).abs() < 1e-6, "second breath");
}

#[test]
fn holds_the_lungs_full_and_empty() {
    let cadence = Cadence::parse("2-4-3-6").unwrap();
    assert_eq!(cadence.fullness_at(1_000), 0.0);
    assert_eq!(cadence.fullness_at(7_500), 1.0);
}

#[test]
fn rests_on_the_centre_pixel_alone() {
    let pixels = strip(&session(Cadence::COHERENCE), 1_000);
    assert_eq!(lit(&pixels), 1);
    assert_eq!(pixels[PIXELS / 2], Rgb { r: 2, g: 0, b: 0 });
}

/// Distances from the centre of the lit pixels on the left side.
fn window(pixels: &[Rgb]) -> Vec<usize> {
    (0..=PIXELS / 2).filter(|distance| pixels[PIXELS / 2 - distance] != Rgb::OFF).collect()
}

#[test]
fn slides_a_widening_window_to_both_ends() {
    let breathing = session(Cadence::COHERENCE);
    // Halfway through the inhale: front at 15, about 5.5 pixels wide.
    let halfway = strip(&breathing, 1_000 + 2_000);
    let left = window(&halfway);
    assert_eq!(halfway[PIXELS / 2], Rgb::OFF, "the window has left the centre");
    assert!(left.len() >= 5 && left.len() <= 7, "{left:?}");
    assert_eq!(*left.last().unwrap(), 15);
    // Full lungs: 10 pixels per side, touching both ends.
    let full = strip(&breathing, 1_000 + 4_000);
    assert_eq!(window(&full), (21..=30).collect::<Vec<_>>());
    assert_ne!(full[PIXELS - 1], Rgb::OFF);
    assert!(full.iter().all(|pixel| pixel.r <= 20 && pixel.g == 0 && pixel.b == 0));
}

#[test]
fn widens_linearly() {
    let breathing = session(Cadence::COHERENCE);
    let widths: Vec<usize> = [0, 1_000, 2_000, 3_000, 4_000].iter().map(|ms| window(&strip(&breathing, 1_000 + ms)).len()).collect();
    assert!(widths.windows(2).all(|pair| pair[0] <= pair[1]), "{widths:?}");
    assert_eq!((widths[0], widths[4]), (1, 10), "{widths:?}");
}
