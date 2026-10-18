#![no_std]
#![no_main]
#![deny(
    clippy::mem_forget,
    reason = "mem::forget is generally not safe to do with esp_hal types, especially those \
    holding buffers for the duration of a data transfer."
)]
#![deny(clippy::large_stack_frames)]

use embassy_executor::Spawner;
use embassy_net::tcp::TcpSocket;
use embassy_net::{Runner, Stack, StackResources};
use embassy_time::{Duration, Timer};
use embedded_io_async::Write;
use esp_backtrace as _;
use esp_hal::clock::CpuClock;
use esp_hal::rng::Rng;
use esp_hal::timer::timg::TimerGroup;
use esp_radio::wifi::sta::StationConfig;
use esp_radio::wifi::{AuthenticationMethodConfig, Config, Interface, WifiController};
use log::{info, warn};
use static_cell::StaticCell;

extern crate alloc;

// This creates a default app-descriptor required by the esp-idf bootloader.
// For more information see: <https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/system/app_image_format.html#application-description>
esp_bootloader_esp_idf::esp_app_desc!();

/// Embedded at build time from `wifi.ini` by `build.rs`.
const WIFI_SSID: &str = env!("WIFI_SSID");
const WIFI_PASSWORD: &str = env!("WIFI_PASSWORD");

const HTTP_PORT: u16 = 80;

#[allow(
    clippy::large_stack_frames,
    reason = "it's not unusual to allocate larger buffers etc. in main"
)]
#[esp_rtos::main]
async fn main(spawner: Spawner) -> ! {
    esp_println::logger::init_logger_from_env();

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 98768);

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timg0.timer0, peripherals.FROM_CPU_INTR0);

    let controller = WifiController::new(peripherals.WIFI, Default::default())
        .expect("Failed to initialize Wi-Fi controller");
    let interface = Interface::station();

    let rng = Rng::new();
    let seed = (u64::from(rng.random()) << 32) | u64::from(rng.random());

    static RESOURCES: StaticCell<StackResources<3>> = StaticCell::new();
    let (stack, runner) = embassy_net::new(
        interface,
        embassy_net::Config::dhcpv4(Default::default()),
        RESOURCES.init(StackResources::new()),
        seed,
    );

    spawner.spawn(connection(controller).unwrap());
    spawner.spawn(net_task(runner).unwrap());

    info!("Waiting for an IP address...");
    stack.wait_config_up().await;
    if let Some(config) = stack.config_v4() {
        info!("IP address: {}", config.address);
    }

    http_server(stack).await
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

/// Answers every HTTP request with a fixed body, one connection at a time.
async fn http_server(stack: Stack<'static>) -> ! {
    let mut rx_buffer = [0u8; 1024];
    let mut tx_buffer = [0u8; 1024];

    info!("HTTP server listening on port {HTTP_PORT}");
    loop {
        let mut socket = TcpSocket::new(stack, &mut rx_buffer, &mut tx_buffer);
        socket.set_timeout(Some(Duration::from_secs(10)));

        if let Err(error) = socket.accept(HTTP_PORT).await {
            warn!("accept failed: {error:?}");
            continue;
        }

        // The request content is ignored: read what arrived, then answer.
        let mut request = [0u8; 512];
        let _ = socket.read(&mut request).await;

        let body = "robine esp32\n";
        let response = http_response(body);
        if let Err(error) = socket.write_all(response.as_bytes()).await {
            warn!("write failed: {error:?}");
        }
        let _ = socket.flush().await;
        socket.close();
        Timer::after(Duration::from_millis(50)).await;
        socket.abort();
    }
}

fn http_response(body: &str) -> alloc::string::String {
    alloc::format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    )
}
