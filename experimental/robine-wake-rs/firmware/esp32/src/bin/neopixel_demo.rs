//! Bench demo of the guide light: no Wi-Fi, no Pi, just the Flora NeoPixel on
//! GPIO 13 looping through a few fades, ending with the 4/6 breathing rhythm.
//!
//! `cargo run --release --bin neopixel_demo`

#![no_std]
#![no_main]

use embassy_executor::Spawner;
use embassy_time::Timer;
use esp_backtrace as _;
use esp_hal::clock::CpuClock;
use esp_hal::rmt::{Rmt, TxChannelConfig, TxChannelCreator};
use esp_hal::time::Rate;
use esp_hal::timer::timg::TimerGroup;
use log::info;
use robine_api::{Easing, LightFade, LightLevel, Rgb};
use robine_esp32::{clock, guide_light};

esp_bootloader_esp_idf::esp_app_desc!();

const OFF: LightLevel = LightLevel { color: Rgb::OFF, brightness: 0.0 };

const fn level(r: u8, g: u8, b: u8, brightness: f32) -> LightLevel {
    LightLevel { color: Rgb { r, g, b }, brightness }
}

/// Fades from `from` to `to`, then waits for the end of the transition.
async fn fade(from: LightLevel, to: LightLevel, duration_ms: u64, easing: Easing) -> LightLevel {
    guide_light::publish(Some(LightFade {
        from,
        to,
        started_ms: clock::monotonic_ms(),
        duration_ms,
        easing,
    }));
    Timer::after_millis(duration_ms).await;
    to
}

#[esp_rtos::main]
async fn main(spawner: Spawner) -> ! {
    esp_println::logger::init_logger_from_env();
    let peripherals = esp_hal::init(esp_hal::Config::default().with_cpu_clock(CpuClock::max()));

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timg0.timer0, peripherals.FROM_CPU_INTR0);

    let rmt = Rmt::new(peripherals.RMT, Rate::from_mhz(guide_light::RMT_FREQUENCY_MHZ))
        .expect("RMT")
        .into_async();
    let guide = rmt
        .channel0
        .configure_tx(&TxChannelConfig::default().with_clk_divider(1))
        .expect("RMT channel")
        .with_pin(peripherals.GPIO13);
    spawner.spawn(guide_light::run(guide).unwrap());

    let amber = level(255, 120, 12, 30.0);
    let dusk = level(255, 40, 70, 2.0);
    let palette = [
        ("red", level(255, 0, 0, 20.0)),
        ("green", level(0, 255, 0, 20.0)),
        ("blue", level(0, 0, 255, 20.0)),
        ("white", level(255, 255, 255, 15.0)),
    ];

    loop {
        let mut current = OFF;
        for (name, target) in palette {
            info!("demo: {name}");
            current = fade(current, target, 800, Easing::Linear).await;
            Timer::after_millis(700).await;
        }
        current = fade(current, OFF, 800, Easing::Linear).await;

        info!("demo: breathing 4/6 x3");
        for _ in 0..3 {
            current = fade(current, amber, 4_000, Easing::Smoothstep).await;
            current = fade(current, dusk, 6_000, Easing::Smoothstep).await;
        }
        fade(current, OFF, 1_500, Easing::Smoothstep).await;
        Timer::after_millis(1_000).await;
    }
}
