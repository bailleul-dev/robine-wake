//! Bench demo of the artificial sunset on the guide light strip (GPIO 13),
//! compressed to 1 minute: the whole strip amber at once, dimming and
//! reddening from the edges down to one red pixel that fades out, then 5 s
//! of dark before the next one.
//!
//! `cargo run --release --bin sunset_demo`

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
use robine_esp32::guide_light;

esp_bootloader_esp_idf::esp_app_desc!();

const DURATION_MS: u64 = 60_000;

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
        .configure_tx(
            &TxChannelConfig::default()
                .with_clk_divider(1)
                .with_memsize(guide_light::RMT_MEMSIZE),
        )
        .expect("RMT channel")
        .with_pin(peripherals.GPIO13);
    spawner.spawn(guide_light::run(guide).unwrap());

    loop {
        info!("sunset: start ({} s)", DURATION_MS / 1_000);
        guide_light::start_sunset(DURATION_MS);
        for quarter in 1..=4 {
            Timer::after_millis(DURATION_MS / 4).await;
            info!("sunset: {} %", quarter * 25);
        }
        Timer::after_millis(5_000).await;
    }
}
