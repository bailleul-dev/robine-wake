//! Infineon MA12070P amplifier (InnoMaker HiFi AMP Pro Mini) on the ESP32-S3:
//! enable, mute and error lines, I2C presence probe, I2S output.
//!
//! The amplifier may be missing, unpowered or wired wrong; none of that may
//! take the firmware down. Every failure here is logged and retried, and the
//! alarm, Wi-Fi and AirPlay control keep running without sound.
//!
//! The amplifier is used with its power-up defaults (I2S, 32-bit slots, rate
//! detected from the clocks): the I2C bus only proves it is there. Volume is
//! applied to the samples (`audio::submit`).

use core::sync::atomic::Ordering;

use embassy_futures::select::{select, Either};
use embassy_time::{with_timeout, Duration, Timer};
use esp_hal::dma_tx_stream_buffer;
use esp_hal::gpio::{Input, InputConfig, Level, Output, OutputConfig, Pull};
use esp_hal::i2c::master::{Config as I2cConfig, I2c};
use esp_hal::i2s::master::{Channels, DataFormat, I2s, TdmConfig};
use esp_hal::peripherals::{DMA_CH1, GPIO17, GPIO18, GPIO21, GPIO38, GPIO41, GPIO6, GPIO7, GPIO8, I2C0, I2S0};
use esp_hal::time::Rate;
use esp_hal::Async;
use log::{info, warn};

use crate::app::RINGING;
use crate::audio::{self, Alarm, FRAME_BYTES, SAMPLE_RATE};

/// 7-bit I2C address of the MA12070P.
const ADDRESS: u8 = 0x20;
/// ENABLE is high to run; MUTE is low to mute (the HAT's own pull-ups leave
/// both lines in the running, unmuted state). Flip here if bench check 3
/// shows otherwise.
const ENABLE_ACTIVE: Level = Level::High;
const MUTE_ACTIVE: Level = Level::Low;

/// Retry period while the amplifier does not answer.
const ABSENT_RETRY: Duration = Duration::from_secs(10);
/// Time for the amplifier to start after ENABLE.
const STARTUP: Duration = Duration::from_millis(100);

/// DMA ring: 8 KiB, about 23 ms of stereo audio.
const DMA_BYTES: usize = 8 * 1024;
const DMA_CHUNK: usize = 2 * 1024;

/// Pins and peripherals of the amplifier, as wired on the bench and on
/// `robine_board`: I2S on IO6/IO7/IO8, I2C on IO17/IO18.
pub struct Peripherals {
    pub i2s: I2S0<'static>,
    pub dma: DMA_CH1<'static>,
    pub bclk: GPIO6<'static>,
    pub ws: GPIO7<'static>,
    pub dout: GPIO8<'static>,
    pub i2c: I2C0<'static>,
    pub sda: GPIO17<'static>,
    pub scl: GPIO18<'static>,
    pub enable: GPIO21<'static>,
    pub mute: GPIO41<'static>,
    pub error: GPIO38<'static>,
}

fn inactive(level: Level) -> Level {
    match level {
        Level::High => Level::Low,
        Level::Low => Level::High,
    }
}

#[embassy_executor::task]
pub async fn run(p: Peripherals) {
    let mut enable = Output::new(p.enable, inactive(ENABLE_ACTIVE), OutputConfig::default());
    let mut mute = Output::new(p.mute, MUTE_ACTIVE, OutputConfig::default());
    let error = Input::new(p.error, InputConfig::default().with_pull(Pull::Up));

    let mut i2c = match I2c::new(p.i2c, I2cConfig::default()) {
        Ok(i2c) => i2c.with_sda(p.sda).with_scl(p.scl).into_async(),
        Err(error) => {
            warn!("amplifier: I2C unavailable ({error:?}), no sound");
            return;
        }
    };

    let tdm = TdmConfig::new_tdm_philips()
        .with_sample_rate(Rate::from_hz(SAMPLE_RATE))
        .with_data_format(DataFormat::Data32Channel32)
        .with_channels(Channels::STEREO);
    let i2s = match I2s::new(p.i2s, p.dma, tdm) {
        Ok(i2s) => i2s.into_async(),
        Err(error) => {
            warn!("amplifier: I2S unavailable ({error:?}), no sound");
            return;
        }
    };
    let mut tx = i2s.i2s_tx.with_bclk(p.bclk).with_ws(p.ws).with_dout(p.dout).build();

    let mut reported_absent = false;
    let mut last_error = error.is_low();
    loop {
        enable.set_level(ENABLE_ACTIVE);
        Timer::after(STARTUP).await;
        if !probe(&mut i2c).await {
            enable.set_level(inactive(ENABLE_ACTIVE));
            if !reported_absent {
                reported_absent = true;
                warn!(
                    "amplifier: no answer at I2C 0x{ADDRESS:02x} (power, SDA/SCL wires, 4.7k pull-ups?): \
                     running without sound, retrying every {} s",
                    ABSENT_RETRY.as_secs()
                );
            }
            Timer::after(ABSENT_RETRY).await;
            continue;
        }
        reported_absent = false;
        info!("amplifier: MA12070P answers at I2C 0x{ADDRESS:02x}");

        // One output session: the ring runs until the DMA fails.
        let mut buffer = dma_tx_stream_buffer!(DMA_BYTES, DMA_CHUNK);
        let mut alarm = Alarm::new();
        loop {
            let mut transfer = match tx.write(buffer) {
                Ok(transfer) => transfer,
                Err((error, back, returned)) => {
                    warn!("amplifier: I2S start failed ({error:?})");
                    tx = back;
                    buffer = returned;
                    Timer::after(Duration::from_secs(1)).await;
                    continue;
                }
            };
            audio::set_ready(true);
            mute.set_level(inactive(MUTE_ACTIVE));
            info!("amplifier: I2S running at {SAMPLE_RATE} Hz, unmuted");

            loop {
                let free = transfer.available_bytes();
                if free < DMA_CHUNK / 2 {
                    match select(transfer.wait_for_available_async(), Timer::after(Duration::from_millis(200))).await {
                        Either::First(Ok(())) => {}
                        Either::First(Err(error)) => {
                            warn!("amplifier: DMA error ({error:?})");
                            break;
                        }
                        Either::Second(()) => break,
                    }
                    continue;
                }
                transfer.push_with(|out| {
                    let len = out.len().min(DMA_CHUNK) & !(FRAME_BYTES - 1);
                    let out = &mut out[..len];
                    if RINGING.load(Ordering::Relaxed) {
                        alarm.fill(out);
                    } else {
                        audio::fill(out);
                    }
                    len
                });

                let level = error.is_low();
                if level != last_error {
                    last_error = level;
                    if level {
                        warn!("amplifier: error line asserted");
                    } else {
                        info!("amplifier: error line released");
                    }
                }
            }

            // The DMA failed or stalled. Never stay silent: mute while
            // restarting, then start again.
            audio::set_ready(false);
            mute.set_level(MUTE_ACTIVE);
            let (back, returned) = transfer.stop();
            tx = back;
            buffer = returned;
            warn!("amplifier: output stalled, restarting");
            Timer::after(Duration::from_millis(100)).await;
            if !probe(&mut i2c).await {
                warn!("amplifier: lost, probing again");
                break;
            }
        }
        // Amplifier gone: power it down until it answers again.
        audio::set_ready(false);
        mute.set_level(MUTE_ACTIVE);
        enable.set_level(inactive(ENABLE_ACTIVE));
        Timer::after(ABSENT_RETRY).await;
    }
}

/// True if something acknowledges the amplifier's address.
async fn probe(i2c: &mut I2c<'static, Async>) -> bool {
    let mut byte = [0u8; 1];
    matches!(with_timeout(Duration::from_millis(100), i2c.read_async(ADDRESS, &mut byte)).await, Ok(Ok(())))
}
