//! Guide light: a WS2812B strip (or a single Flora NeoPixel) driven by SPI
//! with DMA: the whole frame leaves memory without the CPU, so neither
//! Wi-Fi interrupts nor a busy executor can stretch or replay a bit. (The
//! RMT is refilled by the async task, which a busy executor starves: the
//! strip then flashed with stale bits.)
//!
//! The Raspberry Pi owns the 4/6 rhythm and sends `light.set` commands; this
//! task only renders the current transition at 50 Hz, the same colour on
//! every pixel. A program (`light.program`: dawn, sunset, breathing) is
//! rendered pixel by pixel instead.

use alloc::vec;
use core::cell::Cell;

use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::blocking_mutex::Mutex;
use embassy_time::{Duration, Ticker};
use esp_hal::gpio::interconnect::PeripheralOutput;
#[cfg(not(feature = "esp32s3"))]
use esp_hal::peripherals::DMA_SPI2 as DmaChannel;
#[cfg(feature = "esp32s3")]
use esp_hal::peripherals::DMA_CH0 as DmaChannel;
use esp_hal::peripherals::SPI2;
use esp_hal::spi::master::{Config, Spi, SpiDma};
use esp_hal::time::Rate;
use esp_hal::Async;
use log::warn;
use robine_api::{Breathing, Cadence, Dawn, LightScene, Rgb, Sunset, PROGRAM_MAX_BRIGHTNESS};

use crate::clock;

/// Three SPI bits per WS2812B bit at 2.5 MHz (80 MHz / 32), 0.4 µs each:
/// 0 = `100` (0.4 µs high, 0.8 µs low), 1 = `110` (0.8 µs high, 0.4 µs low).
const SPI_FREQUENCY_KHZ: u32 = 2_500;
const ZERO: u32 = 0b100;
const ONE: u32 = 0b110;
/// SPI bytes of one pixel: 24 bits of 3.
const PIXEL_BYTES: usize = 9;

const FRAME: Duration = Duration::from_millis(20);

/// Pixels sent per frame. Extra pixels fall off the end of a shorter strip.
pub const PIXELS: usize = 60;

/// The strip's SPI bus: data on `pin`, no clock pin.
pub fn strip<'d>(
    spi: SPI2<'d>,
    dma: DmaChannel<'d>,
    pin: impl PeripheralOutput<'d>,
) -> SpiDma<'d, Async> {
    Spi::new(spi, Config::default().with_frequency(Rate::from_khz(SPI_FREQUENCY_KHZ)))
        .expect("SPI2")
        .with_mosi(pin)
        .with_dma(dma)
        .into_async()
}

/// What the strip shows, published by the app after every command.
static SCENE: Mutex<CriticalSectionRawMutex, Cell<Option<LightScene>>> = Mutex::new(Cell::new(None));

pub fn publish(scene: Option<LightScene>) {
    SCENE.lock(|current| current.set(scene));
}

/// Starts a dawn now, lasting `duration_ms` (30 minutes for an alarm), then
/// held at daylight until the next command.
pub fn start_dawn(duration_ms: u64) {
    publish(Some(LightScene::Dawn(Dawn {
        started_ms: clock::monotonic_ms(),
        duration_ms,
        max_brightness: PROGRAM_MAX_BRIGHTNESS,
    })));
}

/// Starts a sunset now, lasting `duration_ms`, from a warm amber over the
/// whole strip down to dark.
pub fn start_sunset(duration_ms: u64) {
    publish(Some(LightScene::Sunset(Sunset {
        started_ms: clock::monotonic_ms(),
        duration_ms,
        max_brightness: PROGRAM_MAX_BRIGHTNESS,
    })));
}

/// Starts breathing now at `cadence` (`Cadence::parse("0-4-0-6")` for
/// cardiac coherence) for about `duration_ms`, ending on a full breath.
pub fn start_breathing(cadence: Cadence, duration_ms: u64) {
    publish(Some(LightScene::Breathing(Breathing {
        started_ms: clock::monotonic_ms(),
        duration_ms,
        cadence,
    })));
}

/// SPI bytes of every pixel, GRB order, most significant bit first. The
/// 20 ms between frames is the reset (latch) pulse.
fn encode(pixel: impl Fn(usize) -> Rgb, bytes: &mut [u8]) {
    for (index, pixel_bytes) in bytes.chunks_exact_mut(PIXEL_BYTES).enumerate() {
        let color = pixel(index);
        let bits = (u32::from(color.g) << 16) | (u32::from(color.r) << 8) | u32::from(color.b);
        // 72 bits: the first 9 bytes of a u128 shifted to the top.
        let mut wave: u128 = 0;
        for bit in (0..24).rev() {
            wave = (wave << 3) | u128::from(if bits & (1 << bit) != 0 { ONE } else { ZERO });
        }
        pixel_bytes.copy_from_slice(&(wave << 56).to_be_bytes()[..PIXEL_BYTES]);
    }
}

#[embassy_executor::task]
pub async fn run(mut spi: SpiDma<'static, Async>) {
    let mut ticker = Ticker::every(FRAME);
    // Last uniform colour sent, so a held transition is not resent.
    let mut shown = None;
    // Words, so the DMA reads the frame in place: on the ESP32 it needs a
    // 4-byte aligned buffer (540 bytes for 60 pixels).
    let mut words = vec![0u32; (PIXELS * PIXEL_BYTES).div_ceil(4)];
    loop {
        let now = clock::monotonic_ms();
        let scene = SCENE.lock(Cell::get);
        let uniform = match scene {
            None => Some(Rgb::OFF),
            Some(LightScene::Fade(fade)) => Some(fade.level_at(now).output()),
            Some(_) => None,
        };
        if uniform.is_none() || uniform != shown {
            let bytes: &mut [u8] = bytemuck_bytes(&mut words);
            match scene {
                Some(scene) => encode(|index| scene.pixel_at(now, index, PIXELS), bytes),
                None => encode(|_| Rgb::OFF, bytes),
            }
            match spi.write_async(bytes).await {
                Ok(()) => shown = uniform,
                Err(error) => warn!("guide light: {error:?}"),
            }
        }
        ticker.next().await;
    }
}

fn bytemuck_bytes(words: &mut [u32]) -> &mut [u8] {
    // SAFETY: u8 has no alignment or validity requirement, and the slice
    // covers exactly the words' memory.
    unsafe { core::slice::from_raw_parts_mut(words.as_mut_ptr().cast(), words.len() * 4) }
}
