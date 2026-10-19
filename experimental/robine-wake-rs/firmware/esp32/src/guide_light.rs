//! Breathing guide light: one Adafruit Flora RGB Smart NeoPixel (WS2812B)
//! driven by the RMT peripheral, so Wi-Fi interrupts cannot stretch a bit.
//!
//! The Raspberry Pi owns the 4/6 rhythm and sends `light.set` commands; this
//! task only renders the current transition at 50 Hz.

use core::cell::Cell;

use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::blocking_mutex::Mutex;
use embassy_time::{Duration, Ticker};
use esp_hal::gpio::Level;
use esp_hal::rmt::{Channel, PulseCode, Tx};
use esp_hal::Async;
use log::warn;
use robine_api::{LightFade, Rgb};

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

/// Transition published by the app after every command.
static FADE: Mutex<CriticalSectionRawMutex, Cell<Option<LightFade>>> = Mutex::new(Cell::new(None));

pub fn publish(fade: Option<LightFade>) {
    FADE.lock(|current| current.set(fade));
}

/// Pulse codes of one pixel, GRB order, most significant bit first, then the
/// end marker. The 20 ms between frames is the reset (latch) pulse.
fn encode(color: Rgb) -> [PulseCode; 25] {
    let zero = PulseCode::new(Level::High, T0H, Level::Low, T0L);
    let one = PulseCode::new(Level::High, T1H, Level::Low, T1L);
    let bits = (u32::from(color.g) << 16) | (u32::from(color.r) << 8) | u32::from(color.b);
    let mut codes = [PulseCode::end_marker(); 25];
    for (index, code) in codes[..24].iter_mut().enumerate() {
        *code = if bits & (1 << (23 - index)) != 0 { one } else { zero };
    }
    codes
}

#[embassy_executor::task]
pub async fn run(mut channel: Channel<'static, Async, Tx>) {
    let mut ticker = Ticker::every(FRAME);
    let mut shown = None;
    loop {
        let fade = FADE.lock(Cell::get);
        let color = fade.map_or(Rgb::OFF, |fade| fade.level_at(clock::monotonic_ms()).output());
        if shown != Some(color) {
            match channel.transmit(&encode(color)).await {
                Ok(()) => shown = Some(color),
                Err(error) => warn!("guide light: {error:?}"),
            }
        }
        ticker.next().await;
    }
}
