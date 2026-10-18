//! Decodes an ADTS AAC-LC file to raw 16-bit little-endian PCM, to compare
//! the decoder with ffmpeg:
//!
//! ```sh
//! cargo run --release -p robine-airplay --example aac_decode -- in.aac out.raw
//! ```

use robine_airplay::aac::AacDecoder;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let [_, input, output] = args.as_slice() else {
        eprintln!("usage: aac_decode <in.aac> <out.raw>");
        std::process::exit(2);
    };
    let data = std::fs::read(input).expect("cannot read input");
    let mut decoder = AacDecoder::new(2).expect("stereo decoder");
    let (mut pcm, mut frames, mut errors) = (Vec::new(), 0, 0);
    let mut position = 0;
    while position + 7 <= data.len() {
        let header = &data[position..position + 7];
        assert!(header[0] == 0xFF && header[1] & 0xF0 == 0xF0, "lost ADTS sync at {position}");
        let header_len = if header[1] & 1 == 1 { 7 } else { 9 };
        let length = (usize::from(header[3] & 3) << 11) | (usize::from(header[4]) << 3) | usize::from(header[5] >> 5);
        match decoder.decode(&data[position + header_len..position + length], &mut pcm) {
            Ok(_) => frames += 1,
            Err(error) => {
                errors += 1;
                eprintln!("frame {frames}: {error:?}");
                pcm.extend(std::iter::repeat_n(0, 2048));
            }
        }
        position += length;
    }
    let bytes: Vec<u8> = pcm.iter().flat_map(|sample| sample.to_le_bytes()).collect();
    std::fs::write(output, bytes).expect("cannot write output");
    eprintln!("{frames} frames decoded, {errors} errors");
}
