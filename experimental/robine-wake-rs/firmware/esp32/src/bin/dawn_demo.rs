//! Bench demo of the artificial dawn on the guide light strip (GPIO 13),
//! compressed to 1 minute instead of 30: one faint orange pixel at the
//! centre that spreads, brightens and cools into a uniform daylight white,
//! held 10 s, then off.
//!
//! `cargo run --release --bin dawn_demo`

#![no_std]
#![no_main]

use embassy_executor::Spawner;
use embassy_time::Timer;
use esp_backtrace as _;
use esp_hal::clock::CpuClock;
use esp_hal::timer::timg::TimerGroup;
use log::info;
use robine_esp32::guide_light;

esp_bootloader_esp_idf::esp_app_desc!();

const DURATION_MS: u64 = 60_000;

#[esp_rtos::main]
async fn main(spawner: Spawner) -> ! {
    esp_println::logger::init_logger_from_env();
    let peripherals = esp_hal::init(esp_hal::Config::default().with_cpu_clock(CpuClock::max()));

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timg0.timer0, peripherals.FROM_CPU_INTR0);

    let guide = guide_light::strip(peripherals.SPI2, peripherals.DMA_SPI2, peripherals.GPIO13);
    spawner.spawn(guide_light::run(guide).unwrap());

    loop {
        info!("dawn: start ({} s)", DURATION_MS / 1_000);
        guide_light::start_dawn(DURATION_MS);
        for quarter in 1..=4 {
            Timer::after_millis(DURATION_MS / 4).await;
            info!("dawn: {} %", quarter * 25);
        }
        info!("dawn: daylight, held 10 s");
        Timer::after_millis(10_000).await;
        guide_light::publish(None);
        Timer::after_millis(5_000).await;
    }
}
