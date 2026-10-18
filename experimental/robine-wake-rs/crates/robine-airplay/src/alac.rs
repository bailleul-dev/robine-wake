//! Apple Lossless (ALAC) decoder, 16-bit mono or stereo.
//!
//! Follows Apple's open-source reference decoder (Apache 2.0): adaptive
//! Golomb-Rice residuals, adaptive LPC, then stereo unmixing. AirPlay uses
//! 352-sample stereo frames at 44.1 kHz.

use alloc::vec;
use alloc::vec::Vec;

use crate::bits::{BitReader, Truncated};

/// `ALACSpecificConfig` (the codec "magic cookie").
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct AlacConfig {
    pub frame_length: u32,
    pub bit_depth: u8,
    /// Rice history multiplier (`pb`), usually 40.
    pub pb: u8,
    /// Initial rice history (`mb`), usually 10.
    pub mb: u8,
    /// Rice parameter limit (`kb`), usually 14.
    pub kb: u8,
    pub channels: u8,
    pub sample_rate: u32,
}

impl AlacConfig {
    /// Parameters of AirPlay audio (`96 352 0 16 40 10 14 2 255 0 0 44100`).
    pub const AIRPLAY: Self = Self {
        frame_length: 352,
        bit_depth: 16,
        pb: 40,
        mb: 10,
        kb: 14,
        channels: 2,
        sample_rate: 44_100,
    };

    /// Parses the 24-byte `ALACSpecificConfig` at the end of `cookie`
    /// (container cookies may prefix it with atoms).
    pub fn from_cookie(cookie: &[u8]) -> Option<Self> {
        let raw = cookie.get(cookie.len().checked_sub(24)?..)?;
        let config = Self {
            frame_length: u32::from_be_bytes(raw[0..4].try_into().ok()?),
            bit_depth: raw[5],
            pb: raw[6],
            mb: raw[7],
            kb: raw[8],
            channels: raw[9],
            sample_rate: u32::from_be_bytes(raw[20..24].try_into().ok()?),
        };
        config.supported().then_some(config)
    }

    fn supported(&self) -> bool {
        self.bit_depth == 16 && (1..=2).contains(&self.channels) && (1..=16_384).contains(&self.frame_length)
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum AlacError {
    /// Truncated or inconsistent bitstream.
    Corrupt,
    /// Valid ALAC this decoder does not handle (shifted bytes, more channels).
    Unsupported,
}

impl From<Truncated> for AlacError {
    fn from(_: Truncated) -> Self {
        AlacError::Corrupt
    }
}

pub struct AlacDecoder {
    config: AlacConfig,
    residuals: Vec<i32>,
    channels: [Vec<i32>; 2],
}

const ID_SCE: u32 = 0;
const ID_CPE: u32 = 1;
const ID_LFE: u32 = 3;
const ID_DSE: u32 = 4;
const ID_FIL: u32 = 6;
const ID_END: u32 = 7;

impl AlacDecoder {
    pub fn new(config: AlacConfig) -> Self {
        let len = config.frame_length as usize;
        Self {
            config,
            residuals: vec![0; len],
            channels: [vec![0; len], vec![0; len]],
        }
    }

    pub fn config(&self) -> &AlacConfig {
        &self.config
    }

    /// Decodes one packet, appending interleaved 16-bit samples to `out`.
    /// Returns the number of samples per channel.
    pub fn decode(&mut self, packet: &[u8], out: &mut Vec<i16>) -> Result<usize, AlacError> {
        let mut bits = BitReader::new(packet);
        let mut decoded = None;
        loop {
            if bits.remaining() < 3 {
                break;
            }
            match bits.read(3)? {
                ID_END => break,
                tag @ (ID_SCE | ID_LFE | ID_CPE) => {
                    let stereo = tag == ID_CPE;
                    if decoded.is_some() || (stereo && self.config.channels != 2) {
                        return Err(AlacError::Unsupported);
                    }
                    decoded = Some(self.element(&mut bits, stereo)?);
                }
                ID_DSE => skip_data_element(&mut bits)?,
                ID_FIL => {
                    let mut count = bits.read(4)? as usize;
                    if count == 15 {
                        // 15 means 14 plus an escape count.
                        count = 14 + bits.read(8)? as usize;
                    }
                    bits.skip(count * 8)?;
                }
                _ => return Err(AlacError::Corrupt),
            }
        }
        let (samples, stereo) = decoded.ok_or(AlacError::Corrupt)?;

        out.reserve(samples * usize::from(self.config.channels));
        if stereo {
            for index in 0..samples {
                out.push(self.channels[0][index] as i16);
                out.push(self.channels[1][index] as i16);
            }
        } else {
            out.extend(self.channels[0][..samples].iter().map(|&sample| sample as i16));
        }
        Ok(samples)
    }

    /// Decodes a mono (SCE) or stereo (CPE) element into `self.channels`.
    fn element(&mut self, bits: &mut BitReader, stereo: bool) -> Result<(usize, bool), AlacError> {
        bits.skip(4)?; // element instance tag
        if bits.read(12)? != 0 {
            return Err(AlacError::Corrupt);
        }
        let partial = bits.read(1)? == 1;
        let bytes_shifted = bits.read(2)?;
        let escape = bits.read(1)? == 1;
        if bytes_shifted != 0 {
            return Err(AlacError::Unsupported);
        }
        let samples = if partial { bits.read(32)? as usize } else { self.config.frame_length as usize };
        if samples == 0 || samples > self.config.frame_length as usize {
            return Err(AlacError::Corrupt);
        }
        let channel_count = if stereo { 2 } else { 1 };
        let depth = u32::from(self.config.bit_depth);

        if escape {
            // Uncompressed: interleaved samples at the stream bit depth.
            for index in 0..samples {
                for channel in 0..channel_count {
                    self.channels[channel][index] = sign_extend(bits.read(depth)?, depth);
                }
            }
            return Ok((samples, stereo));
        }

        let mix_bits = bits.read(8)?;
        let mix_res = bits.read(8)? as u8 as i8 as i32;
        let mut predictors = [Predictor::default(); 2];
        for predictor in predictors.iter_mut().take(channel_count) {
            predictor.mode = bits.read(4)?;
            predictor.den_shift = bits.read(4)?;
            predictor.pb_factor = bits.read(3)?;
            predictor.order = bits.read(5)? as usize;
            for coef in predictor.coefs.iter_mut().take(predictor.order) {
                *coef = bits.read(16)? as u16 as i16;
            }
        }

        // Stereo channels carry one extra bit after mid/side mixing.
        let chan_bits = depth + u32::from(stereo);
        for (channel, predictor) in predictors.iter_mut().enumerate().take(channel_count) {
            let pb = u32::from(self.config.pb) * predictor.pb_factor / 4;
            decode_residuals(bits, &self.config, pb, chan_bits, &mut self.residuals[..samples])?;
            let output = &mut self.channels[channel][..samples];
            match predictor.mode {
                0 => predict(&self.residuals[..samples], output, &mut predictor.coefs, predictor.order, chan_bits, predictor.den_shift),
                15 => {
                    // First-order pass in place, then the adaptive filter.
                    let mut first = vec![0i32; samples];
                    predict(&self.residuals[..samples], &mut first, &mut [], 31, chan_bits, 0);
                    predict(&first, output, &mut predictor.coefs, predictor.order, chan_bits, predictor.den_shift);
                }
                _ => return Err(AlacError::Unsupported),
            }
        }

        if stereo && mix_res != 0 {
            let [left, right] = &mut self.channels;
            for index in 0..samples {
                let (u, v) = (left[index], right[index]);
                let l = u.wrapping_add(v).wrapping_sub(mix_res.wrapping_mul(v) >> mix_bits);
                left[index] = l;
                right[index] = l.wrapping_sub(v);
            }
        }
        Ok((samples, stereo))
    }
}

#[derive(Clone, Copy, Default)]
struct Predictor {
    mode: u32,
    den_shift: u32,
    pb_factor: u32,
    order: usize,
    coefs: [i16; 32],
}

fn skip_data_element(bits: &mut BitReader) -> Result<(), AlacError> {
    bits.skip(4)?; // element instance tag
    let aligned = bits.read(1)? == 1;
    let mut count = bits.read(8)? as usize;
    if count == 255 {
        count += bits.read(8)? as usize;
    }
    if aligned {
        bits.align();
    }
    Ok(bits.skip(count * 8)?)
}

// ----- Adaptive Golomb-Rice residuals (Apple `ag_dec.c`) ---------------------

const QBSHIFT: u32 = 9;
const QB: u32 = 1 << QBSHIFT;
const MMULSHIFT: u32 = 2;
const MDENSHIFT: u32 = QBSHIFT - MMULSHIFT - 1;
const MOFF: u32 = 1 << (MDENSHIFT - 2);
const BITOFF: u32 = 24;
const MAX_PREFIX: u32 = 9;
const N_MAX_MEAN_CLAMP: u32 = 0xFFFF;

fn decode_residuals(
    bits: &mut BitReader,
    config: &AlacConfig,
    pb: u32,
    chan_bits: u32,
    out: &mut [i32],
) -> Result<(), AlacError> {
    let kb = u32::from(config.kb);
    let wb = (1u32 << kb) - 1;
    let mut mb = u32::from(config.mb);
    let mut zero_mode = 0u32;
    let mut index = 0;
    while index < out.len() {
        let k = (31 - (mb >> QBSHIFT).wrapping_add(3).leading_zeros()).min(kb);
        let m = ((1u32 << k) - 1) & wb;
        let n = read_value(bits, m, k, chan_bits, true)?;
        let decoded = n.wrapping_add(zero_mode);
        // Zigzag: even -> positive, odd -> negative.
        out[index] = ((decoded.wrapping_add(1) >> 1) as i32).wrapping_mul(if decoded & 1 == 1 { -1 } else { 1 });
        index += 1;

        mb = pb.wrapping_mul(decoded).wrapping_add(mb).wrapping_sub(pb.wrapping_mul(mb) >> QBSHIFT);
        if n > N_MAX_MEAN_CLAMP {
            mb = N_MAX_MEAN_CLAMP;
        }
        zero_mode = 0;

        if (mb << MMULSHIFT) < QB && index < out.len() {
            // A run of zeros follows.
            zero_mode = 1;
            let k = (mb.leading_zeros() + ((mb + MOFF) >> MDENSHIFT)).wrapping_sub(BITOFF);
            let m = ((1u32 << k) - 1) & wb;
            let run = read_value(bits, m, k, 16, false)? as usize;
            if index + run > out.len() {
                return Err(AlacError::Corrupt);
            }
            out[index..index + run].fill(0);
            index += run;
            if run >= 65_535 {
                zero_mode = 0;
            }
            mb = 0;
        }
    }
    Ok(())
}

/// One Rice-coded value: a unary prefix (escape after [`MAX_PREFIX`] ones,
/// then `escape_bits` raw bits), then `k` bits whose two smallest values
/// share one code.
fn read_value(bits: &mut BitReader, m: u32, k: u32, escape_bits: u32, sample: bool) -> Result<u32, AlacError> {
    let mut prefix = 0;
    while prefix < MAX_PREFIX && bits.read(1)? == 1 {
        prefix += 1;
    }
    if prefix >= MAX_PREFIX {
        return Ok(bits.read(escape_bits)?);
    }
    // `sample` with k == 1: the value is the prefix alone.
    if sample && k == 1 {
        return Ok(prefix);
    }
    if k == 0 {
        return Ok(0);
    }
    let v = bits.peek(k)?;
    let mut result = prefix.wrapping_mul(m);
    if v >= 2 {
        result = result.wrapping_add(v - 1);
        bits.skip(k as usize)?;
    } else {
        bits.skip(k as usize - 1)?;
    }
    Ok(result)
}

// ----- Adaptive LPC (Apple `dp_dec.c`) ---------------------------------------

fn predict(residuals: &[i32], out: &mut [i32], coefs: &mut [i16], order: usize, chan_bits: u32, den_shift: u32) {
    let shift = 32 - chan_bits;
    let wrap = |value: i32| value.wrapping_shl(shift) >> shift;
    let Some(first) = residuals.first() else {
        return;
    };
    out[0] = *first;
    if order == 0 {
        out[1..].copy_from_slice(&residuals[1..]);
        return;
    }
    if order == 31 {
        for index in 1..residuals.len() {
            out[index] = wrap(residuals[index].wrapping_add(out[index - 1]));
        }
        return;
    }

    let warm_up = (order + 1).min(residuals.len());
    for index in 1..warm_up {
        out[index] = wrap(residuals[index].wrapping_add(out[index - 1]));
    }
    let half = if den_shift > 0 { 1i32 << (den_shift - 1) } else { 0 };
    for index in warm_up..residuals.len() {
        let top = out[index - order - 1];
        let mut sum = 0i32;
        for (k, coef) in coefs.iter().take(order).enumerate() {
            sum = sum.wrapping_add(i32::from(*coef).wrapping_mul(out[index - 1 - k].wrapping_sub(top)));
        }
        let residual = residuals[index];
        out[index] = wrap(residual.wrapping_add(top).wrapping_add(sum.wrapping_add(half) >> den_shift));

        // Adapt the coefficients toward the sign of the error.
        let mut remaining = residual;
        let sign = residual.signum();
        if sign != 0 {
            for k in (0..order).rev() {
                let delta = top.wrapping_sub(out[index - 1 - k]);
                let delta_sign = delta.signum();
                coefs[k] = coefs[k].wrapping_sub((delta_sign * sign) as i16);
                remaining = remaining.wrapping_sub(((order - k) as i32).wrapping_mul((delta_sign * sign).wrapping_mul(delta) >> den_shift));
                if (sign > 0 && remaining <= 0) || (sign < 0 && remaining >= 0) {
                    break;
                }
            }
        }
    }
}

fn sign_extend(value: u32, bits: u32) -> i32 {
    let shift = 32 - bits;
    ((value << shift) as i32) >> shift
}
