//! Evening reading light: warm white low, red high, then a sunset.

use robine_api::{Reading, Rgb, Sunset};

const PIXELS: usize = 60;

fn reading() -> Reading {
    Reading { started_ms: 1_000, duration_ms: 600_000, sunset_ms: 300_000, max_brightness: 60.0 }
}

#[test]
fn warm_white_at_the_bottom_dim_red_at_the_top() {
    let now = 1_000 + 10_000;
    let bottom = reading().pixel_at(now, 0, PIXELS);
    let top = reading().pixel_at(now, PIXELS - 1, PIXELS);
    // A candle amber, all but no blue: at 60 % of 2100 K.
    assert_eq!(bottom, Rgb { r: 153, g: 60, b: 6 });
    assert!(top.g * 8 <= top.r && top.b == 0, "red: {top:?}");
    assert!(top.r < bottom.r / 2, "dim: {top:?}");
    // From the bottom up, the light only gets redder.
    let pixels: Vec<Rgb> = (0..PIXELS).map(|index| reading().pixel_at(now, index, PIXELS)).collect();
    for pair in pixels.windows(2) {
        let ratio = |p: Rgb| f32::from(p.g) / f32::from(p.r.max(1));
        assert!(ratio(pair[1]) <= ratio(pair[0]) + 0.02, "{pair:?}");
    }
}

#[test]
fn fades_in_then_blends_into_the_sunset() {
    assert_eq!(reading().pixel_at(1_000, 0, PIXELS), Rgb::OFF);
    let first = reading().pixel_at(1_000 + 1_500, 0, PIXELS);
    assert!(first.r > 60 && first.r < 100, "half way in: {first:?}");

    let sunset = Sunset { started_ms: 601_000, duration_ms: 300_000, max_brightness: 60.0 };
    // Just before the end it is all but the sunset's first frame...
    let end = reading().pixel_at(600_999, 30, PIXELS);
    let start = sunset.pixel_at(601_000, 30, PIXELS);
    assert!(end.r.abs_diff(start.r) <= 1 && end.g.abs_diff(start.g) <= 1, "{end:?} {start:?}");
    // ...then the sunset itself, down to dark.
    assert_eq!(reading().pixel_at(700_000, 10, PIXELS), sunset.pixel_at(700_000, 10, PIXELS));
    assert_eq!(reading().pixel_at(901_000, 30, PIXELS), Rgb::OFF);
}

#[test]
fn without_a_sunset_it_fades_out_at_the_end() {
    let reading = Reading { sunset_ms: 0, ..reading() };
    assert_eq!(reading.total_ms(), 600_000);
    let full = reading.pixel_at(500_000, 0, PIXELS);
    let fading = reading.pixel_at(601_000 - 2_500, 0, PIXELS);
    assert!(u16::from(fading.r) * 3 > u16::from(full.r) && u16::from(fading.r) * 3 < u16::from(full.r) * 2, "{fading:?}");
    assert_eq!(reading.pixel_at(601_000, 0, PIXELS), Rgb::OFF);
    assert_eq!(reading.pixel_at(700_000, 30, PIXELS), Rgb::OFF);
}
