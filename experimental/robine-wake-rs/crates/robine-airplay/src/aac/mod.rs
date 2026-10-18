//! AAC-LC decoder (ISO/IEC 14496-3), for the buffered AirPlay stream.
//!
//! Scope: Low Complexity profile, 44.1 or 48 kHz, mono or stereo raw
//! data blocks (no ADTS, no SBR/PS). Covers M/S and intensity stereo,
//! perceptual noise substitution, pulses, TNS and both window shapes.

mod imdct;
mod tables;

use alloc::vec;
use alloc::vec::Vec;

use crate::bits::{BitReader, Truncated};
use imdct::Imdct;

#[derive(Debug, PartialEq, Eq)]
pub enum AacError {
    Corrupt,
    /// Valid AAC outside this decoder's scope (other profiles, channel
    /// layouts, gain control).
    Unsupported,
}

impl From<Truncated> for AacError {
    fn from(_: Truncated) -> Self {
        AacError::Corrupt
    }
}

type Result<T> = core::result::Result<T, AacError>;

const SWB_LONG: [u16; 50] = [
    0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 80, 88, 96, 108, 120, 132, 144, 160, 176, 196, 216,
    240, 264, 292, 320, 352, 384, 416, 448, 480, 512, 544, 576, 608, 640, 672, 704, 736, 768, 800, 832, 864, 896,
    928, 1024,
];
const SWB_SHORT: [u16; 15] = [0, 4, 8, 12, 16, 20, 28, 36, 44, 56, 68, 80, 96, 112, 128];
const TNS_MAX_BANDS_LONG: usize = 42;
const TNS_MAX_BANDS_SHORT: usize = 14;
const TNS_MAX_ORDER_LONG: usize = 12;
const TNS_MAX_ORDER_SHORT: usize = 7;

const LONG_START: u32 = 1;
const EIGHT_SHORT: u32 = 2;
const LONG_STOP: u32 = 3;

const ZERO_HCB: u8 = 0;
const ESCAPE_HCB: u8 = 11;
const NOISE_HCB: u8 = 13;
const INTENSITY_HCB2: u8 = 14;
const INTENSITY_HCB: u8 = 15;

// ----- Huffman ------------------------------------------------------------

/// Binary decoding tree: `[left, right]` per node; a negative entry is a
/// leaf holding `-(value + 1)`.
struct Huffman {
    nodes: Vec<[i16; 2]>,
}

impl Huffman {
    fn new(lens: &[u8], codes: &[u32]) -> Self {
        let mut nodes = vec![[0i16; 2]];
        for (value, (&len, &code)) in lens.iter().zip(codes).enumerate() {
            let mut node = 0usize;
            for position in (0..u32::from(len)).rev() {
                let bit = ((code >> position) & 1) as usize;
                if position == 0 {
                    nodes[node][bit] = -(value as i16) - 1;
                } else {
                    if nodes[node][bit] == 0 {
                        nodes.push([0, 0]);
                        nodes[node][bit] = (nodes.len() - 1) as i16;
                    }
                    node = nodes[node][bit] as usize;
                }
            }
        }
        Self { nodes }
    }

    fn decode(&self, bits: &mut BitReader) -> Result<u32> {
        let mut node = 0usize;
        loop {
            let next = self.nodes[node][bits.read(1)? as usize];
            if next < 0 {
                return Ok((-next - 1) as u32);
            }
            if next == 0 {
                return Err(AacError::Corrupt);
            }
            node = next as usize;
        }
    }
}

// ----- Channel stream ----------------------------------------------------

#[derive(Clone, Copy, Default)]
struct IcsInfo {
    window_sequence: u32,
    window_shape: u32,
    max_sfb: usize,
    num_windows: usize,
    group_lengths: [usize; 8],
    num_groups: usize,
}

impl IcsInfo {
    fn short(&self) -> bool {
        self.window_sequence == EIGHT_SHORT
    }

    fn swb(&self) -> &'static [u16] {
        if self.short() { &SWB_SHORT } else { &SWB_LONG }
    }

    fn read(bits: &mut BitReader) -> Result<Self> {
        if bits.read_bool()? {
            return Err(AacError::Corrupt); // ics_reserved_bit
        }
        let mut info = IcsInfo { window_sequence: bits.read(2)?, window_shape: bits.read(1)?, ..Default::default() };
        if info.short() {
            info.max_sfb = bits.read(4)? as usize;
            let grouping = bits.read(7)?;
            info.num_windows = 8;
            info.num_groups = 1;
            info.group_lengths[0] = 1;
            for window in 1..8 {
                if grouping & (1 << (7 - window)) != 0 {
                    info.group_lengths[info.num_groups - 1] += 1;
                } else {
                    info.num_groups += 1;
                    info.group_lengths[info.num_groups - 1] = 1;
                }
            }
        } else {
            info.max_sfb = bits.read(6)? as usize;
            if bits.read_bool()? {
                // predictor_data_present: Main profile only.
                return Err(AacError::Unsupported);
            }
            info.num_windows = 1;
            info.num_groups = 1;
            info.group_lengths[0] = 1;
        }
        if info.max_sfb > info.swb().len() - 1 {
            return Err(AacError::Corrupt);
        }
        Ok(info)
    }
}

#[derive(Clone, Copy, Default)]
struct TnsFilter {
    length: usize,
    order: usize,
    downward: bool,
    lpc: [f32; TNS_MAX_ORDER_LONG],
}

/// One decoded individual channel stream, before the filterbank.
struct Ics {
    info: IcsInfo,
    band_types: [[u8; 64]; 8],
    /// Scale factor, noise energy or intensity position, per band.
    factors: [[i32; 64]; 8],
    tns: Option<[[TnsFilter; 4]; 8]>,
    tns_filters: [usize; 8],
    /// Dequantized coefficients; short windows are 8 blocks of 128.
    spectrum: [f32; 1024],
}

impl Default for Ics {
    fn default() -> Self {
        Self {
            info: IcsInfo::default(),
            band_types: [[0; 64]; 8],
            factors: [[0; 64]; 8],
            tns: None,
            tns_filters: [0; 8],
            spectrum: [0.0; 1024],
        }
    }
}

/// Per-channel filterbank memory.
#[derive(Clone)]
struct ChannelState {
    overlap: Vec<f32>,
    /// Samples of the last decoded frame.
    output: Vec<f32>,
    previous_shape: u32,
}

pub struct AacDecoder {
    channels: usize,
    spectra: Vec<Huffman>,
    scale_factors: Huffman,
    long: Imdct,
    short: Imdct,
    sine_long: Vec<f32>,
    kbd_long: Vec<f32>,
    sine_short: Vec<f32>,
    kbd_short: Vec<f32>,
    states: [ChannelState; 2],
    ics: [Ics; 2],
    time: Vec<f32>,
    short_time: Vec<f32>,
    noise_seed: u32,
}

impl AacDecoder {
    /// `channels`: 1 or 2, from the stream's audio format.
    pub fn new(channels: usize) -> Result<Self> {
        if !(1..=2).contains(&channels) {
            return Err(AacError::Unsupported);
        }
        use tables::*;
        let spectra = vec![
            Huffman::new(&SPECTRUM1_LENS, &SPECTRUM1_CODES),
            Huffman::new(&SPECTRUM2_LENS, &SPECTRUM2_CODES),
            Huffman::new(&SPECTRUM3_LENS, &SPECTRUM3_CODES),
            Huffman::new(&SPECTRUM4_LENS, &SPECTRUM4_CODES),
            Huffman::new(&SPECTRUM5_LENS, &SPECTRUM5_CODES),
            Huffman::new(&SPECTRUM6_LENS, &SPECTRUM6_CODES),
            Huffman::new(&SPECTRUM7_LENS, &SPECTRUM7_CODES),
            Huffman::new(&SPECTRUM8_LENS, &SPECTRUM8_CODES),
            Huffman::new(&SPECTRUM9_LENS, &SPECTRUM9_CODES),
            Huffman::new(&SPECTRUM10_LENS, &SPECTRUM10_CODES),
            Huffman::new(&SPECTRUM11_LENS, &SPECTRUM11_CODES),
        ];
        let state = ChannelState { overlap: vec![0.0; 1024], output: vec![0.0; 1024], previous_shape: 0 };
        Ok(Self {
            channels,
            spectra,
            scale_factors: Huffman::new(&SCALEFACTOR_LENS, &SCALEFACTOR_CODES),
            long: Imdct::new(1024),
            short: Imdct::new(128),
            sine_long: sine_window(1024),
            kbd_long: kbd_window(1024, 4.0),
            sine_short: sine_window(128),
            kbd_short: kbd_window(128, 6.0),
            states: [state.clone(), state],
            ics: [Ics::default(), Ics::default()],
            time: vec![0.0; 2048],
            short_time: vec![0.0; 256],
            noise_seed: 0x1F2E_3D4C,
        })
    }

    /// Decodes one raw data block (1024 samples per channel), appending
    /// interleaved 16-bit samples to `out`.
    pub fn decode(&mut self, frame: &[u8], out: &mut Vec<i16>) -> Result<usize> {
        let mut bits = BitReader::new(frame);
        let mut decoded = 0usize;
        loop {
            match bits.read(3)? {
                // SCE, LFE
                0 | 3 => {
                    bits.skip(4)?;
                    if decoded != 0 || self.channels != 1 {
                        return Err(AacError::Unsupported);
                    }
                    self.read_ics(&mut bits, 0, None)?;
                    decoded = 1;
                }
                // CPE
                1 => {
                    bits.skip(4)?;
                    if decoded != 0 || self.channels != 2 {
                        return Err(AacError::Unsupported);
                    }
                    self.read_pair(&mut bits)?;
                    decoded = 2;
                }
                // DSE
                4 => {
                    bits.skip(4)?;
                    let aligned = bits.read_bool()?;
                    let mut count = bits.read(8)? as usize;
                    if count == 255 {
                        count += bits.read(8)? as usize;
                    }
                    if aligned {
                        bits.align();
                    }
                    bits.skip(count * 8)?;
                }
                // FIL
                6 => {
                    let mut count = bits.read(4)? as usize;
                    if count == 15 {
                        // 15 means 14 plus an escape count.
                        count = 14 + bits.read(8)? as usize;
                    }
                    bits.skip(count * 8)?;
                }
                7 => break,
                // CCE, PCE
                _ => return Err(AacError::Unsupported),
            }
        }
        if decoded == 0 {
            return Err(AacError::Corrupt);
        }

        for channel in 0..decoded {
            self.apply_tns(channel);
            self.filterbank(channel);
        }
        out.reserve(1024 * decoded);
        for index in 0..1024 {
            for channel in 0..decoded {
                let sample = self.states[channel].output[index];
                out.push(libm::roundf(sample).clamp(-32768.0, 32767.0) as i16);
            }
        }
        Ok(1024)
    }

    fn read_pair(&mut self, bits: &mut BitReader) -> Result<()> {
        let common = bits.read_bool()?;
        let mut ms_used = [[false; 64]; 8];
        let mut ms_present = 0;
        let mut info = None;
        if common {
            let shared = IcsInfo::read(bits)?;
            ms_present = bits.read(2)?;
            match ms_present {
                1 => {
                    for group in ms_used.iter_mut().take(shared.num_groups) {
                        for used in group.iter_mut().take(shared.max_sfb) {
                            *used = bits.read_bool()?;
                        }
                    }
                }
                2 => ms_used.iter_mut().for_each(|group| group.fill(true)),
                3 => return Err(AacError::Corrupt),
                _ => {}
            }
            info = Some(shared);
        }
        self.read_ics(bits, 0, info)?;
        self.read_ics(bits, 1, info)?;
        if common {
            self.stereo(ms_present, &ms_used);
        }
        Ok(())
    }

    fn read_ics(&mut self, bits: &mut BitReader, channel: usize, common: Option<IcsInfo>) -> Result<()> {
        let global_gain = bits.read(8)? as i32;
        let info = match common {
            Some(info) => info,
            None => IcsInfo::read(bits)?,
        };
        let Self { ics, scale_factors, spectra, noise_seed, .. } = self;
        let ics = &mut ics[channel];
        ics.info = info;

        // Section data: a codebook per band.
        let (section_bits, escape) = if info.short() { (3, 7) } else { (5, 31) };
        for group in 0..info.num_groups {
            let mut band = 0;
            while band < info.max_sfb {
                let codebook = bits.read(4)? as u8;
                if codebook == 12 {
                    return Err(AacError::Corrupt);
                }
                let mut length = 0;
                loop {
                    let increment = bits.read(section_bits)? as usize;
                    length += increment;
                    if increment != escape {
                        break;
                    }
                }
                if band + length > info.max_sfb {
                    return Err(AacError::Corrupt);
                }
                ics.band_types[group][band..band + length].fill(codebook);
                band += length;
            }
            ics.band_types[group][info.max_sfb..].fill(ZERO_HCB);
        }

        // Scale factors, noise energies and intensity positions.
        let (mut scale, mut noise, mut position) = (global_gain, global_gain - 90, 0);
        let mut first_noise = true;
        for group in 0..info.num_groups {
            for band in 0..info.max_sfb {
                ics.factors[group][band] = match ics.band_types[group][band] {
                    ZERO_HCB => 0,
                    INTENSITY_HCB | INTENSITY_HCB2 => {
                        position += scale_factors.decode(bits)? as i32 - 60;
                        position
                    }
                    NOISE_HCB => {
                        if first_noise {
                            first_noise = false;
                            noise += bits.read(9)? as i32 - 256;
                        } else {
                            noise += scale_factors.decode(bits)? as i32 - 60;
                        }
                        noise
                    }
                    _ => {
                        scale += scale_factors.decode(bits)? as i32 - 60;
                        if !(0..256).contains(&scale) {
                            return Err(AacError::Corrupt);
                        }
                        scale
                    }
                };
            }
        }

        // Pulses (long windows only).
        let mut pulses = [(0usize, 0i32); 4];
        let mut pulse_count = 0;
        if bits.read_bool()? {
            if info.short() {
                return Err(AacError::Corrupt);
            }
            pulse_count = bits.read(2)? as usize + 1;
            let start_band = bits.read(6)? as usize;
            if start_band >= SWB_LONG.len() - 1 {
                return Err(AacError::Corrupt);
            }
            let mut offset = usize::from(SWB_LONG[start_band]);
            for pulse in pulses.iter_mut().take(pulse_count) {
                offset += bits.read(5)? as usize;
                *pulse = (offset, bits.read(4)? as i32);
            }
        }

        // Temporal noise shaping.
        ics.tns = None;
        if bits.read_bool()? {
            let mut filters = [[TnsFilter::default(); 4]; 8];
            let (length_bits, order_bits, max_order) =
                if info.short() { (4, 3, TNS_MAX_ORDER_SHORT) } else { (6, 5, TNS_MAX_ORDER_LONG) };
            for window in 0..info.num_windows {
                let count = bits.read(if info.short() { 1 } else { 2 })? as usize;
                ics.tns_filters[window] = count;
                if count == 0 {
                    continue;
                }
                let resolution = bits.read(1)?;
                for filter in filters[window].iter_mut().take(count) {
                    filter.length = bits.read(length_bits)? as usize;
                    filter.order = bits.read(order_bits)? as usize;
                    if filter.order > max_order {
                        return Err(AacError::Corrupt);
                    }
                    if filter.order == 0 {
                        continue;
                    }
                    filter.downward = bits.read_bool()?;
                    let compress = bits.read(1)?;
                    filter.lpc = tns_coefficients(bits, resolution, compress, filter.order)?;
                }
            }
            ics.tns = Some(filters);
        }

        if bits.read_bool()? {
            // gain_control_data: SSR profile only.
            return Err(AacError::Unsupported);
        }

        // Spectral data.
        let mut quantized = [0i32; 1024];
        let swb = info.swb();
        let mut window_start = 0;
        for group in 0..info.num_groups {
            let windows = info.group_lengths[group];
            for band in 0..info.max_sfb {
                let codebook = ics.band_types[group][band];
                let (start, end) = (usize::from(swb[band]), usize::from(swb[band + 1]));
                for window in window_start..window_start + windows {
                    let base = window * 128;
                    if !(1..=ESCAPE_HCB).contains(&codebook) {
                        continue;
                    }
                    let mut index = start;
                    while index < end {
                        let values = read_codeword(&spectra[usize::from(codebook) - 1], codebook, bits)?;
                        for value in values.into_iter().flatten() {
                            quantized[base + index] = value;
                            index += 1;
                        }
                    }
                }
            }
            window_start += windows;
        }
        for &(offset, amplitude) in pulses.iter().take(pulse_count) {
            let value = quantized.get_mut(offset).ok_or(AacError::Corrupt)?;
            *value += if *value > 0 { amplitude } else { -amplitude };
        }

        // Dequantization and noise substitution.
        ics.spectrum = [0.0; 1024];
        let mut window_start = 0;
        for group in 0..info.num_groups {
            let windows = info.group_lengths[group];
            for band in 0..info.max_sfb {
                let (start, end) = (usize::from(swb[band]), usize::from(swb[band + 1]));
                let codebook = ics.band_types[group][band];
                let factor = ics.factors[group][band];
                for window in window_start..window_start + windows {
                    let range = window * 128 + start..window * 128 + end;
                    match codebook {
                        1..=ESCAPE_HCB => {
                            let gain = libm::exp2f(0.25 * (factor - 100) as f32);
                            for index in range {
                                ics.spectrum[index] = dequantize(quantized[index]) * gain;
                            }
                        }
                        NOISE_HCB => {
                            let mut energy = 0.0f32;
                            for index in range.clone() {
                                *noise_seed = noise_seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                                let value = *noise_seed as i32 as f32;
                                ics.spectrum[index] = value;
                                energy += value * value;
                            }
                            let scale = libm::exp2f(0.25 * factor as f32) / libm::sqrtf(energy.max(1.0));
                            for index in range {
                                ics.spectrum[index] *= scale;
                            }
                        }
                        _ => {}
                    }
                }
            }
            window_start += windows;
        }
        Ok(())
    }

    /// M/S then intensity stereo, on the dequantized spectra.
    fn stereo(&mut self, ms_present: u32, ms_used: &[[bool; 64]; 8]) {
        let [left, right] = &mut self.ics;
        let info = left.info;
        let swb = info.swb();
        let mut window_start = 0;
        for group in 0..info.num_groups {
            let windows = info.group_lengths[group];
            for band in 0..info.max_sfb {
                let (start, end) = (usize::from(swb[band]), usize::from(swb[band + 1]));
                let right_type = right.band_types[group][band];
                let intensity = matches!(right_type, INTENSITY_HCB | INTENSITY_HCB2);
                for window in window_start..window_start + windows {
                    let range = window * 128 + start..window * 128 + end;
                    if intensity {
                        let mut sign = if right_type == INTENSITY_HCB { 1.0 } else { -1.0 };
                        // ms_used is all set when ms_mask_present is 2.
                        if ms_present != 0 && ms_used[group][band] {
                            sign = -sign;
                        }
                        let scale = sign * libm::exp2f(-0.25 * right.factors[group][band] as f32);
                        for index in range {
                            right.spectrum[index] = left.spectrum[index] * scale;
                        }
                    } else if ms_present != 0
                        && ms_used[group][band]
                        && left.band_types[group][band] != NOISE_HCB
                        && right_type != NOISE_HCB
                    {
                        for index in range {
                            let (mid, side) = (left.spectrum[index], right.spectrum[index]);
                            left.spectrum[index] = mid + side;
                            right.spectrum[index] = mid - side;
                        }
                    }
                }
            }
            window_start += windows;
        }
    }

    fn apply_tns(&mut self, channel: usize) {
        let ics = &mut self.ics[channel];
        let Some(filters) = ics.tns else {
            return;
        };
        let info = ics.info;
        let swb = info.swb();
        let max_bands = if info.short() { TNS_MAX_BANDS_SHORT } else { TNS_MAX_BANDS_LONG }.min(info.max_sfb);
        for window in 0..info.num_windows {
            let mut top = swb.len() - 1;
            for filter in filters[window].iter().take(ics.tns_filters[window]) {
                let bottom = top.saturating_sub(filter.length);
                let (start, end) = (usize::from(swb[bottom.min(max_bands)]), usize::from(swb[top.min(max_bands)]));
                top = bottom;
                if filter.order == 0 || start >= end {
                    continue;
                }
                let length = if info.short() { 128 } else { 1024 };
                let spectrum = &mut ics.spectrum[window * length..(window + 1) * length];
                // All-pole filter: y[n] = x[n] - sum lpc[j] y[n - 1 - j].
                if filter.downward {
                    for (step, index) in (start..end).rev().enumerate() {
                        for j in 0..filter.order.min(step) {
                            spectrum[index] -= spectrum[index + j + 1] * filter.lpc[j];
                        }
                    }
                } else {
                    for (step, index) in (start..end).enumerate() {
                        for j in 0..filter.order.min(step) {
                            spectrum[index] -= spectrum[index - j - 1] * filter.lpc[j];
                        }
                    }
                }
            }
        }
    }

    /// IMDCT, windowing and overlap-add into `states[channel]`.
    fn filterbank(&mut self, channel: usize) {
        let Self { long, short, time, short_time, sine_long, kbd_long, sine_short, kbd_short, states, ics, .. } = self;
        let (info, spectrum, state) = (ics[channel].info, &ics[channel].spectrum, &mut states[channel]);
        let long_window = |shape: u32| if shape == 1 { &kbd_long[..] } else { &sine_long[..] };
        let short_window = |shape: u32| if shape == 1 { &kbd_short[..] } else { &sine_short[..] };
        let (long_left, long_right) = (long_window(state.previous_shape), long_window(info.window_shape));
        let (short_left, short_right) = (short_window(state.previous_shape), short_window(info.window_shape));

        if info.short() {
            time.fill(0.0);
            for window in 0..8 {
                short.run(&spectrum[window * 128..window * 128 + 128], short_time);
                let left = if window == 0 { short_left } else { short_right };
                let offset = 448 + window * 128;
                for n in 0..128 {
                    time[offset + n] += short_time[n] * left[n];
                    time[offset + 128 + n] += short_time[128 + n] * short_right[127 - n];
                }
            }
        } else {
            long.run(spectrum, time);
            if info.window_sequence == LONG_STOP {
                time[..448].fill(0.0);
                for n in 0..128 {
                    time[448 + n] *= short_left[n];
                }
            } else {
                for n in 0..1024 {
                    time[n] *= long_left[n];
                }
            }
            if info.window_sequence == LONG_START {
                for n in 0..128 {
                    time[1024 + 448 + n] *= short_right[127 - n];
                }
                time[1024 + 576..].fill(0.0);
            } else {
                for n in 0..1024 {
                    time[1024 + n] *= long_right[1023 - n];
                }
            }
        }

        for n in 0..1024 {
            state.output[n] = time[n] + state.overlap[n];
        }
        state.overlap.copy_from_slice(&time[1024..]);
        state.previous_shape = info.window_shape;
    }
}

/// One Huffman codeword: 4 or 2 values, with sign bits and escapes.
fn read_codeword(huffman: &Huffman, codebook: u8, bits: &mut BitReader) -> Result<[Option<i32>; 4]> {
    let index = huffman.decode(bits)? as i32;
    let (unsigned, modulo, offset) = match codebook {
        1 | 2 => (false, 3, 1),
        3 | 4 => (true, 3, 0),
        5 | 6 => (false, 9, 4),
        7 | 8 => (true, 8, 0),
        9 | 10 => (true, 13, 0),
        _ => (true, 17, 0),
    };
    let mut values = if codebook <= 4 {
        [
            Some(index / 27 - offset),
            Some(index / 9 % 3 - offset),
            Some(index / 3 % 3 - offset),
            Some(index % 3 - offset),
        ]
    } else {
        [Some(index / modulo - offset), Some(index % modulo - offset), None, None]
    };
    if unsigned {
        for value in values.iter_mut().flatten() {
            if *value != 0 && bits.read_bool()? {
                *value = -*value;
            }
        }
    }
    if codebook == ESCAPE_HCB {
        for value in values.iter_mut().flatten() {
            if value.abs() == 16 {
                let mut prefix = 0;
                while bits.read_bool()? {
                    prefix += 1;
                    if prefix > 8 {
                        return Err(AacError::Corrupt);
                    }
                }
                let magnitude = (1 << (prefix + 4)) + bits.read(prefix + 4)? as i32;
                *value = value.signum() * magnitude;
            }
        }
    }
    Ok(values)
}

fn dequantize(value: i32) -> f32 {
    let magnitude = value.unsigned_abs() as f32;
    let result = magnitude * libm::cbrtf(magnitude);
    if value < 0 { -result } else { result }
}

/// Inverse-quantized reflection coefficients, converted to LPC.
fn tns_coefficients(bits: &mut BitReader, resolution: u32, compress: u32, order: usize) -> Result<[f32; TNS_MAX_ORDER_LONG]> {
    let width = resolution + 3 - compress;
    let base = if resolution == 1 { 8.0 } else { 4.0 };
    let positive = (base - 0.5) / core::f32::consts::FRAC_PI_2;
    let negative = (base + 0.5) / core::f32::consts::FRAC_PI_2;
    let mut reflection = [0f32; TNS_MAX_ORDER_LONG];
    for value in reflection.iter_mut().take(order) {
        let raw = bits.read(width)?;
        let signed = ((raw << (32 - width)) as i32 >> (32 - width)) as f32;
        *value = libm::sinf(signed / if signed >= 0.0 { positive } else { negative });
    }
    let mut lpc = [0f32; TNS_MAX_ORDER_LONG];
    let mut previous = [0f32; TNS_MAX_ORDER_LONG];
    for m in 1..=order {
        previous[..m - 1].copy_from_slice(&lpc[..m - 1]);
        for i in 1..m {
            lpc[i - 1] = previous[i - 1] + reflection[m - 1] * previous[m - i - 1];
        }
        lpc[m - 1] = reflection[m - 1];
    }
    Ok(lpc)
}

/// Rising half of a sine window of `2 * length` samples.
fn sine_window(length: usize) -> Vec<f32> {
    (0..length)
        .map(|n| libm::sinf(core::f32::consts::PI / (2 * length) as f32 * (n as f32 + 0.5)))
        .collect()
}

/// Rising half of a Kaiser-Bessel-derived window of `2 * length` samples.
fn kbd_window(length: usize, alpha: f64) -> Vec<f32> {
    let factor = (alpha * core::f64::consts::PI / length as f64) * (alpha * core::f64::consts::PI / length as f64);
    let mut cumulative = Vec::with_capacity(length);
    let mut sum = 0.0;
    for n in 0..length {
        sum += bessel_i0(((n * (length - n)) as f64) * factor);
        cumulative.push(sum);
    }
    sum += 1.0;
    cumulative.iter().map(|value| libm::sqrt(value / sum) as f32).collect()
}

/// `I0(2 sqrt(x))`: modified Bessel function of the first kind, series form.
fn bessel_i0(x: f64) -> f64 {
    let mut value = 1.0;
    for n in (1..64).rev() {
        value = value * x / f64::from(n * n) + 1.0;
    }
    value
}
