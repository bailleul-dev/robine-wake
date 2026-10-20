//! Bench probe for an unknown 3-wire LED strip on GPIO 13: cycles through
//! the common protocols, 4 s each, and logs which one is on the wire.
//! The variant that lights the first LEDs names the chip family.
//!
//! `cargo run --release --bin strip_probe`

#![no_std]
#![no_main]

use embassy_executor::Spawner;
use embassy_time::Timer;
use esp_backtrace as _;
use esp_hal::clock::CpuClock;
use esp_hal::gpio::Level;
use esp_hal::rmt::{PulseCode, Rmt, TxChannelConfig, TxChannelCreator};
use esp_hal::time::Rate;
use esp_hal::timer::timg::TimerGroup;
use log::{info, warn};

esp_bootloader_esp_idf::esp_app_desc!();

/// 48 bits: two RGB pixels, or one full RGBW pixel plus a partial one.
const BITS: usize = 48;

struct Variant {
    name: &'static str,
    /// High and low durations of a 0 and a 1, in 12.5 ns ticks.
    zero: (u16, u16),
    one: (u16, u16),
    /// Every byte of the frame; the same value on all channels gives white.
    byte: u8,
}

const VARIANTS: [Variant; 4] = [
    Variant { name: "800 kHz (WS2812B, SK6812 RGB/RGBW), dim white", zero: (32, 68), one: (64, 36), byte: 0x20 },
    Variant { name: "800 kHz, red only (GRB order)", zero: (32, 68), one: (64, 36), byte: 0x00 },
    Variant { name: "400 kHz (WS2811 slow), dim white", zero: (40, 160), one: (96, 104), byte: 0x20 },
    Variant { name: "800 kHz short pulses (SK6812, GS8208), dim white", zero: (24, 72), one: (48, 52), byte: 0x20 },
];

fn encode(variant: &Variant) -> [PulseCode; BITS + 1] {
    let zero = PulseCode::new(Level::High, variant.zero.0, Level::Low, variant.zero.1);
    let one = PulseCode::new(Level::High, variant.one.0, Level::Low, variant.one.1);
    let mut codes = [PulseCode::end_marker(); BITS + 1];
    for (index, code) in codes[..BITS].iter_mut().enumerate() {
        let byte = if variant.byte == 0 {
            // GRB: green 0, red 0x20, blue 0 for each pixel.
            if index % 24 / 8 == 1 { 0x20 } else { 0 }
        } else {
            variant.byte
        };
        *code = if byte & (0x80 >> (index % 8)) != 0 { one } else { zero };
    }
    codes
}

#[esp_rtos::main]
async fn main(_spawner: Spawner) -> ! {
    esp_println::logger::init_logger_from_env();
    let peripherals = esp_hal::init(esp_hal::Config::default().with_cpu_clock(CpuClock::max()));

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timg0.timer0, peripherals.FROM_CPU_INTR0);

    let rmt = Rmt::new(peripherals.RMT, Rate::from_mhz(80)).expect("RMT").into_async();
    let mut channel = rmt
        .channel0
        .configure_tx(&TxChannelConfig::default().with_clk_divider(1))
        .expect("RMT channel")
        .with_pin(peripherals.GPIO13);

    let mut off_codes = [PulseCode::end_marker(); BITS + 1];
    off_codes[..BITS].fill(PulseCode::new(Level::High, 32, Level::Low, 68));

    loop {
        for (index, variant) in VARIANTS.iter().enumerate() {
            info!("probe {}: {}", index + 1, variant.name);
            let codes = encode(variant);
            // Resent every 100 ms so a strip plugged in late still latches.
            for _ in 0..40 {
                if let Err(error) = channel.transmit(&codes).await {
                    warn!("probe: {error:?}");
                }
                Timer::after_millis(100).await;
            }
            let _ = channel.transmit(&off_codes).await;
            Timer::after_millis(1_000).await;
        }
    }
}
