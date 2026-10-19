//! The single ALSA output: both streams feed it, since the HiFiBerry can be
//! opened only once.
//!
//! PCM goes to `aplay` in S32_LE, like Shairport Sync: the AirPlay volume is
//! applied in software with 16 bits of headroom below the 16-bit samples, and
//! the hardware mixer stays with the Elixir app. `aplay` keeps the binary free
//! of libasound, hence a static musl build.
//!
//! While open, the output is written continuously (silence when there is
//! nothing to play) through a pipe shrunk to one page, so each write blocks
//! until the DAC has made room: the writer runs at the DAC's pace and knows
//! how far ahead of the speaker it is (see [`Output::latency_frames`]).

use std::io::{BufRead, BufReader, Write};
use std::os::fd::AsRawFd;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::time::Duration;

use serde_json::json;

use crate::control::emit;

pub const SAMPLE_RATE: u32 = 44_100;
/// Frames per write, half the pipe.
pub const CHUNK: usize = 256;
const BYTES_PER_FRAME: usize = 8;
/// ALSA buffer and period requested from `aplay`.
const BUFFER_TIME: Duration = Duration::from_millis(100);
const PERIOD_TIME: Duration = Duration::from_millis(10);
const PIPE_SIZE: i32 = 4096;

/// AirPlay volume in dB (f32 bits).
pub static VOLUME_DB: AtomicU32 = AtomicU32::new(0xC0F0_0000); // -7.5
/// Set by `{"cmd":"suspend"}`: an alarm owns the speaker.
pub static SUSPENDED: AtomicBool = AtomicBool::new(false);

pub enum Message {
    Close,
    /// Close and acknowledge once the device is released.
    Release(Sender<()>),
}

/// Handle on the player thread, which owns the output.
#[derive(Clone)]
pub struct Speaker {
    sender: Sender<Message>,
}

impl Speaker {
    pub fn new() -> (Self, Receiver<Message>) {
        let (sender, receiver) = channel();
        (Self { sender }, receiver)
    }

    pub fn close(&self) {
        let _ = self.sender.send(Message::Close);
    }

    /// Releases the ALSA device and waits until it is closed, so an alarm
    /// can open it right after. Blocking.
    pub fn release(&self, timeout: Duration) -> bool {
        let (done, released) = channel();
        self.sender.send(Message::Release(done)).is_ok() && released.recv_timeout(timeout).is_ok()
    }
}

pub struct Output {
    child: Child,
    stdin: ChildStdin,
    /// Frames between the next write and the speaker once the pipeline is
    /// full: the ALSA buffer, the pipe and half the period `aplay` holds.
    pub latency_frames: u32,
}

impl Output {
    /// Starts `aplay` and fills its buffer with silence, so writes block
    /// from the first one on.
    pub fn open(device: &str) -> Option<Self> {
        let rate = SAMPLE_RATE.to_string();
        let buffer_time = format!("--buffer-time={}", BUFFER_TIME.as_micros());
        let period_time = format!("--period-time={}", PERIOD_TIME.as_micros());
        let args = ["-v", "-D", device, "-t", "raw", "-f", "S32_LE", "-r", &rate, "-c", "2", &buffer_time, &period_time, "-"];
        let spawned = Command::new("aplay").args(args).stdin(Stdio::piped()).stderr(Stdio::piped()).spawn();
        let mut child = match spawned {
            Ok(child) => child,
            Err(error) => {
                emit("error", json!({ "reason": "alsa_open_failed", "detail": error.to_string() }));
                return None;
            }
        };
        let stdin = child.stdin.take()?;
        // SAFETY: plain fcntl calls on a pipe this process owns.
        let pipe = unsafe {
            libc::fcntl(stdin.as_raw_fd(), libc::F_SETPIPE_SZ, PIPE_SIZE);
            libc::fcntl(stdin.as_raw_fd(), libc::F_GETPIPE_SZ)
        };
        let setup = watch_stderr(child.stderr.take()?);
        let frames = |time: Duration| (time.as_micros() * u128::from(SAMPLE_RATE) / 1_000_000) as u32;
        let pipe_frames = pipe.max(0) as u32 / BYTES_PER_FRAME as u32;
        let mut output = Self { child, stdin, latency_frames: frames(BUFFER_TIME) + pipe_frames };
        let prefill = vec![0; (frames(BUFFER_TIME) + pipe_frames) as usize * 2];
        if !output.write(&prefill) {
            output.close();
            return None;
        }
        let (buffer, period) = setup.recv_timeout(Duration::from_secs(1)).unwrap_or((frames(BUFFER_TIME), frames(PERIOD_TIME)));
        output.latency_frames = buffer + pipe_frames + period / 2;
        emit("output", json!({ "state": "open", "device": device, "latency_ms": output.latency_frames * 1000 / SAMPLE_RATE }));
        Some(output)
    }

    /// Writes interleaved samples with the volume applied; blocks while the
    /// pipeline is full. False if `aplay` is gone.
    pub fn write(&mut self, pcm: &[i16]) -> bool {
        match self.stdin.write_all(&encode(pcm)) {
            Ok(()) => true,
            Err(error) => {
                emit("error", json!({ "reason": "alsa_write_failed", "detail": error.to_string() }));
                false
            }
        }
    }

    /// Lets `aplay` drain and exit.
    pub fn close(self) {
        let Self { mut child, stdin, .. } = self;
        drop(stdin);
        let _ = child.wait();
        emit("output", json!({ "state": "closed" }));
    }
}

/// Forwards `aplay`'s messages to our log, and sends the buffer and period
/// sizes it prints with `-v`.
fn watch_stderr(stderr: std::process::ChildStderr) -> Receiver<(u32, u32)> {
    let (sender, receiver) = channel();
    std::thread::spawn(move || {
        // The first setup printed is the one `aplay` writes to (plug layer).
        let (mut buffer, mut period) = (None, None);
        for line in BufReader::new(stderr).lines().map_while(Result::ok) {
            let field = line.split_once(':').map(|(name, value)| (name.trim(), value.trim().parse::<u32>()));
            match field {
                Some(("buffer_size", Ok(size))) if buffer.is_none() => buffer = Some(size),
                Some(("period_size", Ok(size))) if period.is_none() => {
                    period = Some(size);
                    if let Some(buffer) = buffer {
                        let _ = sender.send((buffer, size));
                    }
                }
                _ if line.contains("underrun") => eprintln!("aplay: {line}"),
                _ => {}
            }
        }
    });
    receiver
}

/// 16-bit samples to S32_LE with the volume applied.
fn encode(pcm: &[i16]) -> Vec<u8> {
    let db = f32::from_bits(VOLUME_DB.load(Ordering::Relaxed));
    let gain = if db <= -144.0 { 0.0 } else { 10f32.powf(db / 20.0) * 65_536.0 };
    let mut bytes = Vec::with_capacity(pcm.len() * 4);
    for sample in pcm {
        let scaled = (f32::from(*sample) * gain).clamp(i32::MIN as f32, i32::MAX as f32) as i32;
        bytes.extend_from_slice(&scaled.to_le_bytes());
    }
    bytes
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn full_volume_keeps_the_samples_in_the_upper_bits() {
        VOLUME_DB.store(0f32.to_bits(), Ordering::Relaxed);
        let bytes = encode(&[1, -32768, 32767]);
        let samples: Vec<i32> = bytes.chunks(4).map(|b| i32::from_le_bytes(b.try_into().unwrap())).collect();
        assert_eq!(samples, [1 << 16, i32::MIN, 32767 << 16]);

        VOLUME_DB.store((-144.0f32).to_bits(), Ordering::Relaxed);
        assert!(encode(&[1000]).iter().all(|byte| *byte == 0));

        // -6.02 dB halves the amplitude, without losing the low bits.
        VOLUME_DB.store((-20.0 * 2f32.log10()).to_bits(), Ordering::Relaxed);
        let half = i32::from_le_bytes(encode(&[3])[..4].try_into().unwrap());
        assert!((half - (3 << 15)).abs() <= 1, "{half}");
    }
}
