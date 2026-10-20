//! Guide light: a WS2812B strip (or a single Flora NeoPixel) driven by the
//! RMT peripheral, so Wi-Fi interrupts cannot stretch a bit.
//!
//! The Raspberry Pi owns the 4/6 rhythm and sends `light.set` commands; this
//! task only renders the current transition at 50 Hz, the same colour on
//! every pixel. A dawn, a sunset or a breathing session is rendered pixel
//! by pixel instead.

use core::cell::Cell;

use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::blocking_mutex::Mutex;
use embassy_time::{Duration, Ticker};
use esp_hal::gpio::Level;
use esp_hal::rmt::{Channel, PulseCode, Tx};
use esp_hal::Async;
use log::warn;
use robine_api::{Breathing, Cadence, Dawn, LightFade, Rgb, Sunset};

use crate::clock;

/// RMT clock: 80 MHz with no divider, 12.5 ns per tick.
pub const RMT_FREQUENCY_MHZ: u32 = 80;
// WS2812B timings, in ticks: 0 = 0.4 µs high, 0.85 µs low;
// 1 = 0.8 µs high, 0.45 µs low.
const T0H: u16 = 32;
const T0L: u16 = 68;
const T1H: u16 = 64;
const T1L: u16 = 36;

const FRAME: Duration = Duration::from_millis(20);

/// Pixels sent per frame. Extra pixels fall off the end of a shorter strip.
pub const PIXELS: usize = 60;
/// RMT memory blocks of 64 codes: the driver refills half of it while the
/// other half is sent, so a deeper buffer tolerates longer interrupt delays.
pub const RMT_MEMSIZE: u8 = 4;

/// What the strip shows: the transition published by the app after every
/// command, a dawn, a sunset or a breathing session.
#[derive(Clone, Copy)]
enum Scene {
    Fade(Option<LightFade>),
    Dawn(Dawn),
    Sunset(Sunset),
    Breathing(Breathing),
}

static SCENE: Mutex<CriticalSectionRawMutex, Cell<Scene>> = Mutex::new(Cell::new(Scene::Fade(None)));

/// Shows a transition; replaces a dawn in progress.
pub fn publish(fade: Option<LightFade>) {
    SCENE.lock(|current| current.set(Scene::Fade(fade)));
}

/// Ceiling of the dawn's final white, and of the sunset: 60 pixels near 2 A
/// on a small 5 V supply.
pub const DAWN_MAX_BRIGHTNESS: f32 = 60.0;

/// Starts a dawn now, lasting `duration_ms` (30 minutes for an alarm), then
/// held at daylight until the next command.
pub fn start_dawn(duration_ms: u64) {
    let dawn = Dawn {
        started_ms: clock::monotonic_ms(),
        duration_ms,
        max_brightness: DAWN_MAX_BRIGHTNESS,
    };
    SCENE.lock(|current| current.set(Scene::Dawn(dawn)));
}

/// Starts a sunset now, lasting `duration_ms`, from a warm amber over the
/// whole strip down to dark.
pub fn start_sunset(duration_ms: u64) {
    let sunset = Sunset {
        started_ms: clock::monotonic_ms(),
        duration_ms,
        max_brightness: DAWN_MAX_BRIGHTNESS,
    };
    SCENE.lock(|current| current.set(Scene::Sunset(sunset)));
}

/// Starts breathing now at `cadence` (`Cadence::parse("0-4-0-6")` for
/// cardiac coherence), until the next command.
pub fn start_breathing(cadence: Cadence) {
    let breathing = Breathing { started_ms: clock::monotonic_ms(), cadence };
    SCENE.lock(|current| current.set(Scene::Breathing(breathing)));
}

/// Pulse codes of every pixel, GRB order, most significant bit first, then
/// the end marker. The 20 ms between frames is the reset (latch) pulse.
fn encode(pixel: impl Fn(usize) -> Rgb, codes: &mut [PulseCode; PIXELS * 24 + 1]) {
    let zero = PulseCode::new(Level::High, T0H, Level::Low, T0L);
    let one = PulseCode::new(Level::High, T1H, Level::Low, T1L);
    for (index, bits_codes) in codes[..PIXELS * 24].chunks_exact_mut(24).enumerate() {
        let color = pixel(index);
        let bits = (u32::from(color.g) << 16) | (u32::from(color.r) << 8) | u32::from(color.b);
        for (bit, code) in bits_codes.iter_mut().enumerate() {
            *code = if bits & (1 << (23 - bit)) != 0 { one } else { zero };
        }
    }
    codes[PIXELS * 24] = PulseCode::end_marker();
}

#[embassy_executor::task]
pub async fn run(mut channel: Channel<'static, Async, Tx>) {
    let mut ticker = Ticker::every(FRAME);
    let mut shown = None;
    let mut codes = [PulseCode::end_marker(); PIXELS * 24 + 1];
    loop {
        let now = clock::monotonic_ms();
        match SCENE.lock(Cell::get) {
            Scene::Fade(fade) => {
                let color = fade.map_or(Rgb::OFF, |fade| fade.level_at(now).output());
                if shown != Some(color) {
                    encode(|_| color, &mut codes);
                    match channel.transmit(&codes).await {
                        Ok(()) => shown = Some(color),
                        Err(error) => warn!("guide light: {error:?}"),
                    }
                }
            }
            Scene::Dawn(dawn) => {
                shown = None;
                encode(|index| dawn.pixel_at(now, index, PIXELS), &mut codes);
                if let Err(error) = channel.transmit(&codes).await {
                    warn!("guide light: {error:?}");
                }
            }
            Scene::Sunset(sunset) => {
                shown = None;
                encode(|index| sunset.pixel_at(now, index, PIXELS), &mut codes);
                if let Err(error) = channel.transmit(&codes).await {
                    warn!("guide light: {error:?}");
                }
            }
            Scene::Breathing(breathing) => {
                shown = None;
                encode(|index| breathing.pixel_at(now, index, PIXELS), &mut codes);
                if let Err(error) = channel.transmit(&codes).await {
                    warn!("guide light: {error:?}");
                }
            }
        }
        ticker.next().await;
    }
}
