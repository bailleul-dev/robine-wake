//! Inverse MDCT of the AAC filterbank, through a DCT-IV computed with a
//! complex FFT of a quarter of the output length.

use alloc::vec;
use alloc::vec::Vec;
use core::f32::consts::PI;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Complex {
    re: f32,
    im: f32,
}

impl Complex {
    fn mul(self, other: Self) -> Self {
        Self {
            re: self.re * other.re - self.im * other.im,
            im: self.re * other.im + self.im * other.re,
        }
    }

    fn add(self, other: Self) -> Self {
        Self { re: self.re + other.re, im: self.im + other.im }
    }

    fn sub(self, other: Self) -> Self {
        Self { re: self.re - other.re, im: self.im - other.im }
    }

    /// `e^(-i angle)`.
    fn rotation(angle: f32) -> Self {
        Self { re: libm::cosf(angle), im: -libm::sinf(angle) }
    }
}

/// In-place radix-2 FFT of a power-of-two size.
struct Fft {
    twiddles: Vec<Complex>,
    reversed: Vec<u32>,
}

impl Fft {
    fn new(size: usize) -> Self {
        assert!(size.is_power_of_two());
        let bits = size.trailing_zeros();
        Self {
            twiddles: (0..size / 2).map(|k| Complex::rotation(2.0 * PI * k as f32 / size as f32)).collect(),
            reversed: (0..size as u32).map(|index| index.reverse_bits() >> (32 - bits.max(1))).collect(),
        }
    }

    fn run(&self, data: &mut [Complex]) {
        let size = data.len();
        if size <= 1 {
            return;
        }
        for (index, &reversed) in self.reversed.iter().enumerate() {
            let reversed = reversed as usize;
            if index < reversed {
                data.swap(index, reversed);
            }
        }
        let mut half = 1;
        while half < size {
            let stride = size / (half * 2);
            for start in (0..size).step_by(half * 2) {
                for k in 0..half {
                    let twiddled = data[start + k + half].mul(self.twiddles[k * stride]);
                    let even = data[start + k];
                    data[start + k] = even.add(twiddled);
                    data[start + k + half] = even.sub(twiddled);
                }
            }
            half *= 2;
        }
    }
}

/// IMDCT producing `2 * m` samples from `m` coefficients, scaled as in
/// ISO/IEC 14496-3: `x[n] = 2/N * sum X[k] cos(2pi/N (n + n0)(k + 1/2))`.
pub struct Imdct {
    m: usize,
    fft: Fft,
    /// `e^(-i pi (8n + 1) / 8m)`, applied before and after the FFT.
    rotations: Vec<Complex>,
    scratch: Vec<Complex>,
    dct: Vec<f32>,
}

impl Imdct {
    /// `m`: number of coefficients (1024 long, 128 short).
    pub fn new(m: usize) -> Self {
        Self {
            m,
            fft: Fft::new(m / 2),
            rotations: (0..m / 2)
                .map(|n| Complex::rotation(PI * (8 * n + 1) as f32 / (8 * m) as f32))
                .collect(),
            scratch: vec![Complex::default(); m / 2],
            dct: vec![0.0; m],
        }
    }

    /// DCT-IV: `X[k] = sum x[n] cos(pi/m (n + 1/2)(k + 1/2))`.
    fn dct4(&mut self, input: &[f32]) {
        let m = self.m;
        for (n, value) in self.scratch.iter_mut().enumerate() {
            let folded = Complex { re: input[2 * n], im: input[m - 1 - 2 * n] };
            *value = folded.mul(self.rotations[n]);
        }
        self.fft.run(&mut self.scratch);
        for (k, value) in self.scratch.iter().enumerate() {
            let rotated = value.mul(self.rotations[k]);
            self.dct[2 * k] = rotated.re;
            self.dct[m - 1 - 2 * k] = -rotated.im;
        }
    }

    pub fn run(&mut self, input: &[f32], output: &mut [f32]) {
        let m = self.m;
        self.dct4(&input[..m]);
        let scale = 1.0 / m as f32; // 2/N with N = 2m
        let half = m / 2;
        for n in 0..half {
            output[n] = self.dct[n + half] * scale;
        }
        for n in half..3 * half {
            output[n] = -self.dct[3 * half - 1 - n] * scale;
        }
        for n in 3 * half..2 * m {
            output[n] = -self.dct[n - 3 * half] * scale;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::vec::Vec;

    /// Formula of the standard, O(N^2).
    fn imdct_reference(input: &[f32]) -> Vec<f32> {
        let m = input.len();
        let n_total = 2 * m;
        let n0 = (n_total as f64 / 2.0 + 1.0) / 2.0;
        (0..n_total)
            .map(|n| {
                let sum: f64 = input
                    .iter()
                    .enumerate()
                    .map(|(k, &x)| {
                        f64::from(x)
                            * (2.0 * core::f64::consts::PI / n_total as f64 * (n as f64 + n0) * (k as f64 + 0.5)).cos()
                    })
                    .sum();
                (2.0 / n_total as f64 * sum) as f32
            })
            .collect()
    }

    #[test]
    fn fast_imdct_matches_the_standard_formula() {
        for m in [128usize, 1024] {
            let input: Vec<f32> = (0..m).map(|k| ((k * 7919) % 1000) as f32 - 500.0).collect();
            let mut fast = vec![0.0; 2 * m];
            Imdct::new(m).run(&input, &mut fast);
            let reference = imdct_reference(&input);
            let peak = reference.iter().fold(0f32, |acc, x| acc.max(x.abs()));
            for (n, (a, b)) in fast.iter().zip(&reference).enumerate() {
                assert!((a - b).abs() <= peak * 1e-4, "m={m} n={n}: {a} vs {b}");
            }
        }
    }
}
