//! ALAC is lossless: decoding `fixtures/signal.caf` (encoded by ffmpeg, which
//! uses 4096-sample frames; AirPlay's 352 are checked on captured streams)
//! must give back the exact input.

use robine_airplay::alac::{AlacConfig, AlacDecoder};

/// The fixture's source signal, integer math only (same formula as the
/// Python generator): triangles, silence, a quiet section and noise.
fn sample(n: i64) -> (i16, i16) {
    let segment = n / 4410;
    match segment % 4 {
        1 => (0, 0),
        3 => {
            let x = (n * 1_103_515_245 + 12_345) & 0x7FFF_FFFF;
            let y = (n * 2_654_435_761 + 97) & 0x7FFF_FFFF;
            (((x >> 15) - 32_768) as i16, ((y >> 15) - 32_768) as i16)
        }
        quiet => {
            let mut left = ((n * 512) % 65_536 - 32_768).abs() - 16_384;
            let mut right = ((n * 300) % 40_000 - 20_000).abs() - 10_000;
            if quiet == 2 {
                // Python's floor division.
                left = left.div_euclid(64);
                right = right.div_euclid(64);
            }
            (left as i16, right as i16)
        }
    }
}

struct Caf {
    cookie: Vec<u8>,
    packets: Vec<Vec<u8>>,
    valid_frames: usize,
}

fn parse_caf(bytes: &[u8]) -> Caf {
    assert_eq!(&bytes[..4], b"caff");
    let (mut cookie, mut sizes, mut data, mut valid_frames) = (Vec::new(), Vec::new(), &[][..], 0);
    let mut position = 8;
    while position + 12 <= bytes.len() {
        let kind = &bytes[position..position + 4];
        let size = i64::from_be_bytes(bytes[position + 4..position + 12].try_into().unwrap());
        let start = position + 12;
        let end = if size < 0 { bytes.len() } else { start + size as usize };
        let chunk = &bytes[start..end];
        match kind {
            b"kuki" => cookie = chunk.to_vec(),
            b"pakt" => {
                let count = i64::from_be_bytes(chunk[..8].try_into().unwrap()) as usize;
                valid_frames = i64::from_be_bytes(chunk[8..16].try_into().unwrap()) as usize;
                let mut cursor = 24;
                for _ in 0..count {
                    // BER variable-length integer.
                    let mut size = 0usize;
                    loop {
                        let byte = chunk[cursor];
                        cursor += 1;
                        size = (size << 7) | usize::from(byte & 0x7F);
                        if byte & 0x80 == 0 {
                            break;
                        }
                    }
                    sizes.push(size);
                }
            }
            b"data" => data = &chunk[4..], // skip the edit count
            _ => {}
        }
        position = end;
    }
    let mut packets = Vec::new();
    let mut offset = 0;
    for size in sizes {
        packets.push(data[offset..offset + size].to_vec());
        offset += size;
    }
    Caf { cookie, packets, valid_frames }
}

#[test]
fn decodes_ffmpeg_alac_bit_exactly() {
    let caf = parse_caf(include_bytes!("fixtures/signal.caf"));
    let config = AlacConfig::from_cookie(&caf.cookie).expect("supported cookie");
    assert_eq!(config, AlacConfig { frame_length: 4096, ..AlacConfig::AIRPLAY });
    // The container counts the last packet whole; its own header is shorter.
    assert!(caf.valid_frames >= 44_100);

    let mut decoder = AlacDecoder::new(config);
    let mut pcm = Vec::new();
    for (index, packet) in caf.packets.iter().enumerate() {
        let samples = decoder.decode(packet, &mut pcm).unwrap_or_else(|error| panic!("packet {index}: {error:?}"));
        assert!(samples <= 4096);
    }
    assert_eq!(pcm.len(), 2 * 44_100);

    for (n, frame) in pcm.chunks(2).take(44_100).enumerate() {
        let expected = sample(n as i64);
        assert_eq!((frame[0], frame[1]), expected, "sample {n} (segment {})", n / 4410);
    }
}

#[test]
fn truncated_packets_are_reported_not_panicking() {
    let caf = parse_caf(include_bytes!("fixtures/signal.caf"));
    let mut decoder = AlacDecoder::new(AlacConfig::from_cookie(&caf.cookie).unwrap());
    for packet in caf.packets.iter().take(40) {
        for cut in [1, packet.len() / 2, packet.len() - 1] {
            let _ = decoder.decode(&packet[..cut], &mut Vec::new());
        }
    }
}
