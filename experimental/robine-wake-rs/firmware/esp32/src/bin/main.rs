#![no_std]
#![no_main]
#![deny(
    clippy::mem_forget,
    reason = "mem::forget is generally not safe to do with esp_hal types, especially those \
    holding buffers for the duration of a data transfer."
)]
#![deny(clippy::large_stack_frames)]

use core::sync::atomic::Ordering;

use embassy_executor::Spawner;
use embassy_net::{Runner, Stack, StackResources};
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::signal::Signal;
use embassy_time::{Duration, Timer};
use esp_backtrace as _;
use esp_hal::clock::CpuClock;
use esp_hal::gpio::{Level, Output, OutputConfig};
use esp_hal::rng::Rng;
#[cfg(not(feature = "esp32s3"))]
use esp_hal::uart::{self, Uart};
use esp_hal::timer::timg::TimerGroup;
use esp_radio::wifi::sta::StationConfig;
use esp_radio::wifi::{AuthenticationMethodConfig, Config, Interface, WifiController};
use esp_storage::FlashStorage;
use log::{info, warn};
use robine_api::{Device, Platform, DEFAULT_HTTP_PORT};
use robine_esp32::airplay::{self, Airplay};
use robine_esp32::app::{App, RINGING};
use robine_esp32::store::Store;
#[cfg(not(feature = "esp32s3"))]
use robine_esp32::serial;
use robine_esp32::{clock, guide_light, http, ntp};
use static_cell::StaticCell;

extern crate alloc;

// This creates a default app-descriptor required by the esp-idf bootloader.
// For more information see: <https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/system/app_image_format.html#application-description>
esp_bootloader_esp_idf::esp_app_desc!();

/// Embedded at build time from `wifi.ini` by `build.rs`.
const WIFI_SSID: &str = env!("WIFI_SSID");
const WIFI_PASSWORD: &str = env!("WIFI_PASSWORD");

/// Concurrent HTTP connections: event streams hold one each.
const HTTP_WORKERS: usize = 3;
/// Sockets: HTTP workers, DHCP, DNS and NTP, then AirPlay (two control
/// connections, events, buffered and realtime audio, retransmissions, two
/// PTP ports, mDNS).
const SOCKETS: usize = HTTP_WORKERS + 3 + 9;
/// Re-synchronize the clock every six hours.
const NTP_INTERVAL: Duration = Duration::from_secs(6 * 3600);

static PLATFORM: Platform = Platform {
    target: if cfg!(feature = "esp32s3") { "esp32s3" } else { "esp32" },
    firmware_version: env!("CARGO_PKG_VERSION"),
    http_port: DEFAULT_HTTP_PORT,
    sounds: robine_api::sounds::BUNDLED,
    // Production rule: only the remote button stops a real alarm.
    remote_dismiss_enabled: false,
    audio_available: false,
    // On the S3 the lights belong to the companion ESP32 (UART, not wired yet).
    light: if cfg!(feature = "esp32s3") { None } else { Some("WS2812B strip") },
    light_pixels: if cfg!(feature = "esp32s3") { 0 } else { guide_light::PIXELS },
};

/// Raised by the NTP task when the wall clock is set.
static CLOCK_SET: Signal<CriticalSectionRawMutex, ()> = Signal::new();

fn fill_random(bytes: &mut [u8]) {
    let rng = Rng::new();
    for chunk in bytes.chunks_mut(4) {
        chunk.copy_from_slice(&rng.random().to_le_bytes()[..chunk.len()]);
    }
}

#[allow(
    clippy::large_stack_frames,
    reason = "it's not unusual to allocate larger buffers etc. in main"
)]
#[esp_rtos::main]
async fn main(spawner: Spawner) -> ! {
    esp_println::logger::init_logger_from_env();

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    // The S3's DRAM2 is smaller (73 KiB free), but its SRAM is bigger overall.
    #[cfg(not(feature = "esp32s3"))]
    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 98768);
    #[cfg(not(feature = "esp32s3"))]
    esp_alloc::heap_allocator!(size: 48 * 1024);
    #[cfg(feature = "esp32s3")]
    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 64 * 1024);
    #[cfg(feature = "esp32s3")]
    esp_alloc::heap_allocator!(size: 96 * 1024);
    // N16R8: the 8 MiB of PSRAM join the heap (buffered AAC needs 90 KiB at once).
    #[cfg(feature = "esp32s3")]
    esp_alloc::psram_allocator!(
        peripherals.PSRAM,
        esp_hal::psram,
        esp_hal::psram::PsramConfig {
            mode: esp_hal::psram::PsramMode::OctalSpi,
            ..Default::default()
        }
    );

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timg0.timer0, peripherals.FROM_CPU_INTR0);

    // Wi-Fi first: the hardware RNG is only truly random with the radio on.
    let controller = WifiController::new(peripherals.WIFI, Default::default())
        .expect("Failed to initialize Wi-Fi controller");
    robine_core::random::set_source(fill_random);

    let mut store = Store::open(FlashStorage::new(peripherals.FLASH));
    let device = match store.as_mut().and_then(Store::load) {
        Some(snapshot) => Device::restore(PLATFORM.clone(), &snapshot).unwrap_or_else(|_| {
            warn!("saved state unreadable, starting empty");
            Device::new(PLATFORM.clone())
        }),
        None => Device::new(PLATFORM.clone()),
    };
    match &store {
        Some(store) => info!("flash store ready ({} bytes per snapshot)", store.capacity()),
        None => warn!("no 'robine' partition: alarms will not survive a restart"),
    }

    let rng = Rng::new();
    let seed = (u64::from(rng.random()) << 32) | u64::from(rng.random());
    static RESOURCES: StaticCell<StackResources<SOCKETS>> = StaticCell::new();
    let (stack, runner) = embassy_net::new(
        Interface::station(),
        embassy_net::Config::dhcpv4(Default::default()),
        RESOURCES.init(StackResources::new()),
        seed,
    );

    static APP: StaticCell<App> = StaticCell::new();
    let app: &'static App = APP.init(App::new(device, store, Some(stack)));

    let mac: [u8; 6] = esp_hal::efuse::base_mac_address().as_bytes().try_into().expect("6-byte MAC");
    static AIRPLAY: StaticCell<Airplay> = StaticCell::new();
    let airplay: &'static Airplay = AIRPLAY.init(Airplay::new(mac, fill_random));

    // Heltec WiFi Kit 32 V1: white LED on GPIO 25. DevKitC-1: GPIO 48 (the
    // board's RGB LED, driven as a plain output).
    #[cfg(not(feature = "esp32s3"))]
    let led = Output::new(peripherals.GPIO25, Level::Low, OutputConfig::default());
    #[cfg(feature = "esp32s3")]
    let led = Output::new(peripherals.GPIO48, Level::Low, OutputConfig::default());

    // The ESP32 alone drives the WS2812B strip (GPIO 13) and talks to the
    // Raspberry Pi (UART2, GPIO 17/18). On the S3 both belong to the companion.
    #[cfg(not(feature = "esp32s3"))]
    let guide = guide_light::strip(peripherals.SPI2, peripherals.DMA_SPI2, peripherals.GPIO13);
    #[cfg(not(feature = "esp32s3"))]
    let pi_link = Uart::new(peripherals.UART2, uart::Config::default().with_baudrate(serial::BAUDRATE))
        .expect("UART2")
        .with_tx(peripherals.GPIO17)
        .with_rx(peripherals.GPIO18)
        .into_async();

    spawner.spawn(connection(controller).unwrap());
    spawner.spawn(net_task(runner).unwrap());
    spawner.spawn(ntp_task(stack).unwrap());
    spawner.spawn(led_task(led).unwrap());
    #[cfg(not(feature = "esp32s3"))]
    {
        spawner.spawn(guide_light::run(guide).unwrap());
        spawner.spawn(serial::run(pi_link, app).unwrap());
    }
    for _ in 0..HTTP_WORKERS {
        spawner.spawn(http_task(stack, app).unwrap());
    }
    for _ in 0..2 {
        spawner.spawn(airplay::control_task(stack, airplay).unwrap());
    }
    spawner.spawn(airplay::event_task(stack, airplay).unwrap());
    spawner.spawn(airplay::buffered_task(stack, airplay).unwrap());
    spawner.spawn(airplay::realtime_task(stack, airplay).unwrap());
    spawner.spawn(airplay::control_udp_task(stack, airplay).unwrap());
    spawner.spawn(airplay::ptp_task(stack, airplay, 319).unwrap());
    spawner.spawn(airplay::ptp_task(stack, airplay, 320).unwrap());
    spawner.spawn(airplay::player_task(airplay).unwrap());
    spawner.spawn(airplay::stats_task(airplay).unwrap());
    spawner.spawn(airplay::mdns_task(stack, airplay).unwrap());

    stack.wait_config_up().await;
    if let Some(config) = stack.config_v4() {
        info!(
            "Robine Wake ready: http://{}:{}/",
            config.address.address(),
            DEFAULT_HTTP_PORT
        );
    }

    // Scheduler loop.
    loop {
        if CLOCK_SET.signaled() {
            CLOCK_SET.reset();
            app.clock_changed().await;
        }
        app.tick().await;
        Timer::after(Duration::from_millis(500)).await;
    }
}

/// Keeps the station connected, retrying after any disconnection.
#[embassy_executor::task]
async fn connection(mut controller: WifiController<'static>) {
    let authentication = if WIFI_PASSWORD.is_empty() {
        AuthenticationMethodConfig::Open
    } else {
        AuthenticationMethodConfig::Wpa2Personal(
            WIFI_PASSWORD.try_into().expect("password checked by build.rs"),
        )
    };
    let station = StationConfig::default()
        .with_ssid(WIFI_SSID.try_into().expect("SSID checked by build.rs"))
        .with_authentication(authentication);
    controller
        .set_config(&Config::Station(station))
        .expect("Invalid Wi-Fi configuration");

    loop {
        info!("Connecting to \"{WIFI_SSID}\"...");
        match controller.connect_async().await {
            Ok(_) => {
                info!("Wi-Fi connected");
                let _ = controller.wait_for_disconnect_async().await;
                warn!("Wi-Fi disconnected");
            }
            Err(error) => warn!("Wi-Fi connection failed: {error:?}"),
        }
        Timer::after(Duration::from_secs(5)).await;
    }
}

#[embassy_executor::task]
async fn net_task(mut runner: Runner<'static, Interface>) {
    runner.run().await
}

#[embassy_executor::task]
async fn ntp_task(stack: Stack<'static>) {
    loop {
        stack.wait_config_up().await;
        match ntp::query(stack).await {
            Ok(unix_ms) => {
                clock::set_unix_ms(unix_ms);
                CLOCK_SET.signal(());
                info!("clock set from NTP: {}", clock::now());
                Timer::after(NTP_INTERVAL).await;
            }
            Err(error) => {
                warn!("NTP failed: {error:?}");
                Timer::after(Duration::from_secs(10)).await;
            }
        }
    }
}

#[embassy_executor::task(pool_size = HTTP_WORKERS)]
async fn http_task(stack: Stack<'static>, app: &'static App) {
    http::serve(stack, app, DEFAULT_HTTP_PORT).await
}

/// Stands in for the speaker until the amplifier is wired: blinks while an
/// alarm is audible.
#[embassy_executor::task]
async fn led_task(mut led: Output<'static>) {
    loop {
        if RINGING.load(Ordering::Relaxed) {
            led.toggle();
            Timer::after(Duration::from_millis(250)).await;
        } else {
            led.set_low();
            Timer::after(Duration::from_millis(200)).await;
        }
    }
}
