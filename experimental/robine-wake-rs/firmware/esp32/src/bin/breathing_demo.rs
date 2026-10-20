//! Bench demo of guided breathing on the guide light strip (GPIO 13): a dim
//! red glow that widens from the centre on the inhale and shrinks back on
//! the exhale, at the cadence below, until the board is reset.
//!
//! `cargo run --release --bin breathing_demo`

#![no_std]
#![no_main]

use embassy_executor::Spawner;
use embassy_time::Timer;
use esp_backtrace as _;
use esp_hal::clock::CpuClock;
use esp_hal::timer::timg::TimerGroup;
use log::info;
use robine_api::Cadence;
use robine_esp32::guide_light;

esp_bootloader_esp_idf::esp_app_desc!();

/// Hold empty - inhale - hold full - exhale, in seconds: cardiac coherence.
const CADENCE: &str = "0-4-0-6";

#[esp_rtos::main]
async fn main(spawner: Spawner) -> ! {
    esp_println::logger::init_logger_from_env();
    let peripherals = esp_hal::init(esp_hal::Config::default().with_cpu_clock(CpuClock::max()));

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timg0.timer0, peripherals.FROM_CPU_INTR0);

    let guide = guide_light::strip(peripherals.SPI2, peripherals.DMA_SPI2, peripherals.GPIO13);
    spawner.spawn(guide_light::run(guide).unwrap());

    let cadence = Cadence::parse(CADENCE).expect("cadence");
    info!("breathing: {CADENCE}, {} breaths a minute", 60_000 / cadence.breath_ms());
    guide_light::start_breathing(cadence);
    loop {
        Timer::after_millis(cadence.breath_ms()).await;
        info!("breathing: next breath");
    }
}
