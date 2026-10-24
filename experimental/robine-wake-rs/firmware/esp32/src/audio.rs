//! Audio hand-off between the decoders and the amplifier.
//!
//! Decoders call [`submit`] with interleaved stereo PCM. It never blocks and
//! never fails: without an amplifier (or while an alarm rings) the samples
//! are simply dropped. The amplifier task (`amp`) drains the pipe.

use core::sync::atomic::{AtomicBool, AtomicU32, Ordering};

use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::pipe::Pipe;

use crate::app::RINGING;

/// Sample rate of AirPlay audio, in Hz.
pub const SAMPLE_RATE: u32 = 44_100;
/// Bytes of one stereo frame on the wire: two left-justified 32-bit slots.
pub const FRAME_BYTES: usize = 8;

/// 32-bit stereo frames, little endian, ready for the I2S DMA. About 90 ms.
static PIPE: Pipe<CriticalSectionRawMutex, 32_768> = Pipe::new();

/// Set by the amplifier task while it is driving the I2S output.
static READY: AtomicBool = AtomicBool::new(false);

/// AirPlay volume as a Q16 gain (`0x10000` = 0 dB), updated by volume events.
static GAIN: AtomicU32 = AtomicU32::new(0x10000);

pub fn set_ready(ready: bool) {
    READY.store(ready, Ordering::Relaxed);
    if !ready {
        // Drop what is queued: it must not play after a restart.
        let mut scratch = [0u8; 512];
        while PIPE.try_read(&mut scratch).is_ok_and(|read| read > 0) {}
    }
}

pub fn is_ready() -> bool {
    READY.load(Ordering::Relaxed)
}

/// Applies an AirPlay volume (−30 to 0 dB, −144 for mute).
pub fn set_volume_db(db: f32) {
    let gain = if db <= -60.0 { 0.0 } else { libm::powf(10.0, db.min(0.0) / 20.0) };
    GAIN.store((gain * 65_536.0) as u32, Ordering::Relaxed);
}

/// Queues interleaved stereo samples. Whole frames only: a frame that does
/// not fit is dropped, so the channels never swap.
pub fn submit(pcm: &[i16]) {
    if !is_ready() || RINGING.load(Ordering::Relaxed) {
        return;
    }
    let gain = i64::from(GAIN.load(Ordering::Relaxed));
    let mut chunk = [0u8; 512];
    for samples in pcm.chunks(chunk.len() / 4 & !1) {
        let samples = &samples[..samples.len() & !1];
        let bytes = samples.len() * 4;
        if PIPE.free_capacity() < bytes {
            return;
        }
        for (slot, sample) in chunk.chunks_exact_mut(4).zip(samples) {
            let scaled = (i64::from(*sample) * gain) >> 16;
            slot.copy_from_slice(&((scaled as i32) << 16).to_le_bytes());
        }
        let _ = PIPE.try_write(&chunk[..bytes]);
    }
}

/// Moves queued frames into `out`, a multiple of [`FRAME_BYTES`] long, and
/// pads the rest with silence. Returns how many bytes were real audio.
pub fn fill(out: &mut [u8]) -> usize {
    let len = out.len() & !(FRAME_BYTES - 1);
    let read = PIPE.try_read(&mut out[..len]).unwrap_or(0) & !(FRAME_BYTES - 1);
    out[read..].fill(0);
    read
}

/// A 880 Hz beep, one second on and one second off, written as I2S frames.
/// Fixed level: an alarm must be audible whatever AirPlay's volume says.
pub struct Alarm {
    phase: u32,
    elapsed: u32,
}

/// 1/8 of full scale: loud enough, no clipping, no surprise at 3 am.
const ALARM_PEAK: i32 = 0x1000;

impl Alarm {
    pub const fn new() -> Self {
        Self { phase: 0, elapsed: 0 }
    }

    pub fn fill(&mut self, out: &mut [u8]) {
        for frame in out.chunks_exact_mut(FRAME_BYTES) {
            let on = (self.elapsed / SAMPLE_RATE) % 2 == 0;
            let level = if on { libm::sinf(self.phase as f32 * (core::f32::consts::TAU / 65_536.0)) } else { 0.0 };
            let sample = ((level * ALARM_PEAK as f32) as i32) << 16;
            frame[..4].copy_from_slice(&sample.to_le_bytes());
            frame[4..].copy_from_slice(&sample.to_le_bytes());
            // 880 Hz of a 65536-step phase at 44.1 kHz.
            self.phase = self.phase.wrapping_add(1_308) & 0xFFFF;
            self.elapsed = (self.elapsed + 1) % (2 * SAMPLE_RATE);
        }
    }
}
