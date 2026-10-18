//! AAC-LC decoding of `fixtures/signal.aac`, encoded by ffmpeg with TNS,
//! M/S, intensity stereo and PNS enabled, short windows forced by bursts.
//!
//! `signal_ffmpeg_every16.raw` holds every 16th sample of ffmpeg's own
//! decoding: ours must agree within rounding. The decoded audio must also
//! resemble the source signal, regenerated here.

use robine_airplay::aac::AacDecoder;

/// The fixture's source, integer math only (same formula as its generator).
fn source(n: i64) -> (i16, i16) {
    let t = n % 44_100;
    if (17_640..22_050).contains(&t) {
        return (0, 0);
    }
    let mut left = (((n * 400) % 65_536 - 32_768).abs() - 16_384).div_euclid(2);
    let mut right = (((n * 251) % 50_000 - 25_000).abs() - 12_500).div_euclid(2);
    if t >= 22_050 && (t - 22_050) % 4_410 < 300 {
        let burst = ((n * 1_103_515_245 + 12_345) >> 16).rem_euclid(20_001) - 10_000;
        left += burst;
        right -= burst;
    }
    (left.clamp(-32_768, 32_767) as i16, right.clamp(-32_768, 32_767) as i16)
}

fn decode_fixture() -> Vec<i16> {
    let data = include_bytes!("fixtures/signal.aac");
    let mut decoder = AacDecoder::new(2).unwrap();
    let (mut pcm, mut position) = (Vec::new(), 0);
    while position < data.len() {
        let header = &data[position..position + 7];
        assert_eq!((header[0], header[1] & 0xF6), (0xFF, 0xF0), "ADTS sync");
        let header_len = if header[1] & 1 == 1 { 7 } else { 9 };
        let length = (usize::from(header[3] & 3) << 11) | (usize::from(header[4]) << 3) | usize::from(header[5] >> 5);
        decoder
            .decode(&data[position + header_len..position + length], &mut pcm)
            .unwrap_or_else(|error| panic!("frame at {position}: {error:?}"));
        position += length;
    }
    pcm
}

#[test]
fn matches_ffmpeg_within_rounding() {
    let pcm = decode_fixture();
    let reference: Vec<i16> = include_bytes!("fixtures/signal_ffmpeg_every16.raw")
        .chunks(2)
        .map(|pair| i16::from_le_bytes([pair[0], pair[1]]))
        .collect();
    assert_eq!(pcm.len(), 45 * 2048);
    for (index, expected) in reference.iter().enumerate() {
        let ours = pcm[index * 16];
        assert!((i32::from(ours) - i32::from(*expected)).abs() <= 1, "sample {}: {ours} vs {expected}", index * 16);
    }
}

#[test]
fn resembles_the_source_signal() {
    let pcm = decode_fixture();
    // AAC encoders delay the signal by one frame.
    let delayed = &pcm[2 * 1024..];
    let (mut signal, mut error) = (0f64, 0f64);
    for (n, frame) in delayed.chunks(2).take(44_100).enumerate() {
        let (left, right) = source(n as i64);
        signal += f64::from(left).powi(2) + f64::from(right).powi(2);
        error += (f64::from(frame[0]) - f64::from(left)).powi(2) + (f64::from(frame[1]) - f64::from(right)).powi(2);
    }
    let snr = 10.0 * (signal / error).log10();
    assert!(snr > 12.0, "SNR against the source: {snr:.1} dB");
}

#[test]
fn garbage_frames_are_errors_not_panics() {
    let mut decoder = AacDecoder::new(2).unwrap();
    let mut seed = 1u32;
    for length in [0usize, 1, 7, 64, 400] {
        for _ in 0..50 {
            let frame: Vec<u8> = (0..length)
                .map(|_| {
                    seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                    (seed >> 24) as u8
                })
                .collect();
            let _ = decoder.decode(&frame, &mut Vec::new());
        }
    }
}

#[test]
fn fill_element_with_zero_escape_count_is_handled() {
    // FIL (110), count 15 (1111), escape 0: 14 bytes of fill, then END (111).
    let mut bits = String::from("110111100000000");
    bits.push_str(&"0".repeat(14 * 8));
    bits.push_str("111");
    while bits.len() % 8 != 0 {
        bits.push('0');
    }
    let frame: Vec<u8> = bits
        .as_bytes()
        .chunks(8)
        .map(|byte| byte.iter().fold(0u8, |acc, bit| (acc << 1) | (bit - b'0')))
        .collect();
    let mut decoder = AacDecoder::new(2).unwrap();
    // No audio element: an error, not an overflow panic.
    assert!(decoder.decode(&frame, &mut Vec::new()).is_err());
}
