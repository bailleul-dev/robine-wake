//! The ESP32 as the Raspberry Pi's light co-processor: the LED strip on
//! GPIO 13 and the API-002 link to the Pi on UART2, nothing else. No Wi-Fi,
//! no HTTP, no AirPlay: the Pi relays the web app's commands.
//!
//! `cargo run --release --bin pi_light`

#![no_std]
#![no_main]

use embassy_executor::Spawner;
use embassy_time::{Duration, Timer};
use esp_backtrace as _;
use esp_hal::clock::CpuClock;
use esp_hal::rng::Rng;
use esp_hal::timer::timg::TimerGroup;
use esp_hal::uart::{self, Uart};
use log::info;
use robine_api::{Device, Platform, DEFAULT_HTTP_PORT};
use robine_esp32::app::App;
use robine_esp32::{guide_light, serial};
use static_cell::StaticCell;

extern crate alloc;

esp_bootloader_esp_idf::esp_app_desc!();

static PLATFORM: Platform = Platform {
    target: "esp32",
    firmware_version: env!("CARGO_PKG_VERSION"),
    http_port: DEFAULT_HTTP_PORT,
    sounds: robine_api::sounds::BUNDLED,
    remote_dismiss_enabled: false,
    audio_available: false,
    light: Some("WS2812B strip"),
};

/// Pseudo-random without the radio: only command ids depend on it.
fn fill_random(bytes: &mut [u8]) {
    let rng = Rng::new();
    for chunk in bytes.chunks_mut(4) {
        chunk.copy_from_slice(&rng.random().to_le_bytes()[..chunk.len()]);
    }
}

#[esp_rtos::main]
async fn main(spawner: Spawner) -> ! {
    esp_println::logger::init_logger_from_env();
    let peripherals = esp_hal::init(esp_hal::Config::default().with_cpu_clock(CpuClock::max()));

    esp_alloc::heap_allocator!(size: 48 * 1024);

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timg0.timer0, peripherals.FROM_CPU_INTR0);
    robine_core::random::set_source(fill_random);

    static APP: StaticCell<App> = StaticCell::new();
    let app: &'static App = APP.init(App::new(Device::new(PLATFORM.clone()), None, None));

    let guide = guide_light::strip(peripherals.SPI2, peripherals.DMA_SPI2, peripherals.GPIO13);

    // Link to the Raspberry Pi: UART2, TX on GPIO 17, RX on GPIO 18.
    let pi_link = Uart::new(peripherals.UART2, uart::Config::default().with_baudrate(serial::BAUDRATE))
        .expect("UART2")
        .with_tx(peripherals.GPIO17)
        .with_rx(peripherals.GPIO18)
        .into_async();

    spawner.spawn(guide_light::run(guide).unwrap());
    spawner.spawn(serial::run(pi_link, app).unwrap());
    info!("Robine light ready: strip on GPIO 13, Pi on UART2");

    loop {
        Timer::after(Duration::from_secs(3600)).await;
    }
}
