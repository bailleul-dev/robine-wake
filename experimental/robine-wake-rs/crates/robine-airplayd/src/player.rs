//! The player thread: feeds the output at the DAC's pace and plays each
//! sample when the sender's clock says so, for both stream types.
//!
//! Before each write, the first sample written will be heard
//! [`Output::latency_frames`] from now. The difference with the anchored time
//! of the next decoded sample is the sync error. Beyond [`HARD_SYNC`] it is
//! corrected at once, by dropping frames or inserting silence. Below, the
//! smoothed error drives sample stuffing: now and then one frame of a write
//! is dropped or repeated (at most one per write, 0.4 %), which absorbs the
//! drift between the sender's clock and the DAC crystal. Realtime streams
//! are re-anchored by the sender every second, buffered ones follow the PTP
//! clock from their single anchor.

use std::collections::VecDeque;
use std::sync::atomic::Ordering;
use std::sync::mpsc::Receiver;
use std::time::{Duration, Instant};

use robine_airplay::aac::AacDecoder;
use robine_airplay::alac::{AlacConfig, AlacDecoder};
use robine_airplay::STREAM_REALTIME;
use serde_json::json;

use crate::control::emit;
use crate::queue::FrameQueue;
use crate::speaker::{Message, Output, CHUNK, SAMPLE_RATE, SUSPENDED};
use crate::{local_ns, Shared, State, Stats};

/// Larger sync errors are corrected at once rather than by stuffing.
const HARD_SYNC: Duration = Duration::from_millis(50);
/// The output opens this long before the first sample is due, at most.
const OPEN_AHEAD: Duration = Duration::from_millis(500);
/// Device released after this long without audio.
const IDLE: Duration = Duration::from_secs(2);
const STATS_INTERVAL: Duration = Duration::from_secs(5);
/// Smoothing of the sync error per write (time constant about 0.3 s).
const SMOOTHING: f64 = 0.02;
/// Share of the smoothed error corrected per write: an error is absorbed
/// in about 2 s, and a 100 ppm drift settles below 0.2 ms.
const GAIN: f64 = 1.0 / 345.0;

fn frames(duration: Duration) -> i64 {
    (duration.as_nanos() * u128::from(SAMPLE_RATE) / 1_000_000_000) as i64
}

/// Decoded samples (interleaved stereo) in RTP time order.
#[derive(Default)]
pub struct Pcm {
    samples: VecDeque<i16>,
    /// RTP time of the first sample, or of the next one expected.
    rtp: Option<u32>,
}

impl Pcm {
    pub fn frames(&self) -> usize {
        self.samples.len() / 2
    }

    /// Appends a decoded frame; a gap since the previous one (lost packet)
    /// becomes silence, an overlap is skipped.
    pub fn append(&mut self, timestamp: u32, decoded: &[i16]) {
        let end = self.rtp.map(|rtp| rtp.wrapping_add(self.frames() as u32));
        let mut skip = 0;
        match end.map(|end| timestamp.wrapping_sub(end) as i32) {
            Some(gap) if gap < 0 => skip = gap.unsigned_abs() as usize,
            Some(gap) if (gap as u32) < SAMPLE_RATE => self.samples.extend(std::iter::repeat_n(0, gap as usize * 2)),
            _ => {
                self.samples.clear();
                self.rtp = Some(timestamp);
            }
        }
        self.samples.extend(decoded.iter().skip(skip * 2));
    }

    /// Removes up to `frames` frames from the head; returns how many.
    pub fn skip(&mut self, frames: usize) -> usize {
        let frames = frames.min(self.frames());
        self.samples.drain(..frames * 2);
        self.rtp = self.rtp.map(|rtp| rtp.wrapping_add(frames as u32));
        frames
    }

    /// Moves `frames` frames to `out`, consuming one more and dropping the
    /// middle one (`correction` 1), or one less and repeating it (-1).
    pub fn take(&mut self, frames: usize, correction: i32, out: &mut Vec<i16>) {
        let consumed = (frames as i64 + i64::from(correction)).clamp(0, self.frames() as i64) as usize;
        let mut taken: Vec<i16> = self.samples.drain(..consumed * 2).collect();
        self.rtp = self.rtp.map(|rtp| rtp.wrapping_add(consumed as u32));
        let middle = consumed / 2 * 2;
        match correction {
            1 if consumed > frames => drop(taken.drain(middle..middle + 2)),
            -1 if consumed > 0 => {
                let frame = [taken[middle], taken[middle + 1]];
                taken.splice(middle..middle, frame);
            }
            _ => {}
        }
        out.extend_from_slice(&taken);
    }
}

/// Sample stuffing decisions from the sync error.
#[derive(Default)]
pub struct Drift {
    average: Option<f64>,
    credit: f64,
}

impl Drift {
    /// `error`: frames the output is late (negative: early). Returns 1 to
    /// drop a frame in the next write, -1 to repeat one, 0 for neither.
    pub fn update(&mut self, error: f64) -> i32 {
        let average = self.average.map_or(error, |average| average + SMOOTHING * (error - average));
        self.average = Some(average);
        self.credit += (average * GAIN).clamp(-1.0, 1.0);
        if self.credit >= 1.0 {
            self.credit -= 1.0;
            1
        } else if self.credit <= -1.0 {
            self.credit += 1.0;
            -1
        } else {
            0
        }
    }
}

enum Plan {
    /// Nothing due: silence if the output is open.
    Idle,
    Open,
    Play(Vec<i16>),
}

struct Player {
    pcm: Pcm,
    drift: Drift,
    alac: AlacDecoder,
    aac: AacDecoder,
    /// Stream generation the decoded samples belong to.
    generation: u64,
    latency_frames: u32,
}

impl Player {
    fn reset(&mut self) {
        self.pcm = Pcm::default();
        self.drift = Drift::default();
        self.aac = AacDecoder::new(2).expect("stereo AAC decoder");
    }

    /// Decodes queued frames until a write's worth (plus one) is ready.
    fn refill(&mut self, state: &mut State, realtime: bool) {
        let mut decoded = Vec::new();
        while self.pcm.frames() <= CHUNK {
            let Some(frame) = state.queue.pop() else { return };
            decoded.clear();
            let result = if realtime {
                self.alac.decode(&frame.data, &mut decoded).is_ok()
            } else {
                self.aac.decode(&frame.data, &mut decoded).is_ok()
            };
            if result {
                state.stats.peak(&decoded);
                self.pcm.append(frame.timestamp, &decoded);
            } else {
                state.stats.corrupt += 1;
            }
        }
    }

    fn plan(&mut self, state: &mut State, open: bool) -> Plan {
        if state.generation != self.generation {
            self.generation = state.generation;
            self.reset();
        }
        let (Some((kind, _)), Some(anchor), true) = (&state.stream, state.anchor, state.playing) else {
            return Plan::Idle;
        };
        let realtime = *kind == STREAM_REALTIME;
        self.refill(state, realtime);
        // Frames the next sample written is late by.
        let play_at = local_ns() + i64::from(self.latency_frames) * 1_000_000_000 / i64::from(SAMPLE_RATE);
        let error = |pcm: &Pcm, state: &State| {
            let due = state.ptp.to_local(anchor.master_time(pcm.rtp?, SAMPLE_RATE))?;
            Some((play_at - due) * i64::from(SAMPLE_RATE) / 1_000_000_000)
        };
        let Some(mut late) = error(&self.pcm, state).filter(|_| self.pcm.frames() > 0) else {
            if open {
                state.stats.underruns += 1;
            }
            return Plan::Idle;
        };
        if !open {
            return if late > -frames(OPEN_AHEAD) { Plan::Open } else { Plan::Idle };
        }
        let mut chunk = Vec::with_capacity(CHUNK * 2);
        if late > frames(HARD_SYNC) {
            while late > 0 && self.pcm.frames() > 0 {
                state.stats.late_frames += self.pcm.skip(late as usize) as u64;
                self.refill(state, realtime);
                late = error(&self.pcm, state).unwrap_or(0);
            }
            self.drift = Drift::default();
            state.stats.resyncs += 1;
        } else if late < -frames(HARD_SYNC) {
            let silence = late.unsigned_abs().min(CHUNK as u64) as usize;
            chunk.resize(silence * 2, 0);
            self.drift = Drift::default();
        }
        let correction = if chunk.is_empty() { self.drift.update(late as f64) } else { 0 };
        state.stats.stuffed += u64::from(correction != 0);
        self.pcm.take(CHUNK - chunk.len() / 2, correction, &mut chunk);
        if chunk.len() < CHUNK * 2 {
            state.stats.underruns += 1;
            chunk.resize(CHUNK * 2, 0);
        }
        Plan::Play(chunk)
    }
}

pub fn run(device: String, state: Shared, messages: Receiver<Message>) {
    let mut player = Player {
        pcm: Pcm::default(),
        drift: Drift::default(),
        alac: AlacDecoder::new(AlacConfig::AIRPLAY),
        aac: AacDecoder::new(2).expect("stereo AAC decoder"),
        generation: 0,
        // Until the output tells: 100 ms of ALSA buffer and a page of pipe.
        latency_frames: 4_410 + 512,
    };
    let silence = vec![0i16; CHUNK * 2];
    let mut output: Option<Output> = None;
    let (mut audible_at, mut reported) = (Instant::now(), Instant::now());
    loop {
        for message in messages.try_iter() {
            if let Some(output) = output.take() {
                output.close();
            }
            if let Message::Release(done) = message {
                let _ = done.send(());
            }
        }
        if reported.elapsed() >= STATS_INTERVAL {
            reported = Instant::now();
            report(&state);
        }
        if SUSPENDED.load(Ordering::Relaxed) {
            if let Some(output) = output.take() {
                output.close();
            }
            // The audio of the suspension is dropped, not delayed.
            state.lock().unwrap().queue = FrameQueue::default();
            player.reset();
            std::thread::sleep(Duration::from_millis(10));
            continue;
        }
        let plan = player.plan(&mut state.lock().unwrap(), output.is_some());
        let written = match (plan, output.as_mut()) {
            (Plan::Play(chunk), Some(out)) => {
                audible_at = Instant::now();
                state.lock().unwrap().active_at = Some(audible_at);
                out.write(&chunk)
            }
            (Plan::Open, None) => {
                output = Output::open(&device);
                match &output {
                    Some(out) => player.latency_frames = out.latency_frames,
                    None => std::thread::sleep(Duration::from_secs(1)),
                }
                true
            }
            (_, Some(_)) if audible_at.elapsed() >= IDLE => false,
            (_, Some(out)) => out.write(&silence),
            (_, None) => {
                std::thread::sleep(Duration::from_millis(5));
                true
            }
        };
        if !written {
            if let Some(output) = output.take() {
                output.close();
            }
        }
    }
}

fn report(state: &Shared) {
    let stats = std::mem::take(&mut state.lock().unwrap().stats);
    // Buffered audio arrives in bursts: a window without packets still
    // counts the corrections and underruns of the playback.
    if stats == Stats::default() {
        return;
    }
    emit(
        "stats",
        json!({
            "realtime_frames": stats.realtime_frames,
            "buffered_frames": stats.buffered_frames,
            "late_frames": stats.late_frames,
            "resyncs": stats.resyncs,
            "stuffed": stats.stuffed,
            "underruns": stats.underruns,
            "resend_requested": stats.resend_requested,
            "resent": stats.resent,
            "corrupt": stats.corrupt,
            "rejected": stats.rejected,
            "peak_dbfs": (20.0 * (f64::from(stats.peak.max(1)) / 32768.0).log10() * 10.0).round() / 10.0,
        }),
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(value: i16, frames: usize) -> Vec<i16> {
        vec![value; frames * 2]
    }

    #[test]
    fn gaps_become_silence_and_overlaps_are_skipped() {
        let mut pcm = Pcm::default();
        pcm.append(1000, &frame(1, 4));
        pcm.append(1006, &frame(2, 2)); // two frames lost
        pcm.append(1007, &frame(3, 2)); // one frame repeated
        let mut out = Vec::new();
        pcm.take(9, 0, &mut out);
        assert_eq!(out.iter().step_by(2).copied().collect::<Vec<_>>(), [1, 1, 1, 1, 0, 0, 2, 2, 3]);
        assert_eq!(pcm.rtp, Some(1009));

        // A jump of a second or more restarts the timeline.
        pcm.append(1009 + SAMPLE_RATE, &frame(4, 1));
        assert_eq!((pcm.rtp, pcm.frames()), (Some(1009 + SAMPLE_RATE), 1));
    }

    #[test]
    fn stuffing_drops_or_repeats_the_middle_frame() {
        let samples: Vec<i16> = (0..10).flat_map(|n| [n, -n]).collect();
        let mut pcm = Pcm::default();
        pcm.append(0, &samples);

        let mut out = Vec::new();
        pcm.take(4, 1, &mut out);
        assert_eq!(out, [0, 0, 1, -1, 3, -3, 4, -4]);
        assert_eq!(pcm.rtp, Some(5));

        out.clear();
        pcm.take(4, -1, &mut out);
        assert_eq!(out, [5, -5, 6, -6, 6, -6, 7, -7]);
        assert_eq!(pcm.rtp, Some(8));
        assert_eq!(pcm.skip(5), 2);
    }

    #[test]
    fn stuffing_absorbs_a_clock_drift() {
        // The DAC runs 100 ppm slow: the output falls behind by 0.0256
        // frames per write, plus a sawtooth from the period reads.
        let mut drift = Drift::default();
        let (mut late, mut dropped) = (0.0, 0);
        for write in 0..100_000 {
            let jitter = f64::from(write % 8) * 30.0 - 105.0;
            let correction = drift.update(late + jitter);
            late += CHUNK as f64 * 100e-6 - f64::from(correction);
            dropped += correction;
        }
        assert!(late.abs() < 10.0, "{late}");
        assert!((dropped - 2_560).abs() < 20, "{dropped}");
    }
}
