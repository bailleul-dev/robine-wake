//! AirPlay bench: runs the `robine-airplay` core on a PC, advertises it on
//! the local network and logs every exchange with the sender.
//!
//! ```sh
//! cargo run -p robine-airplay-bench -- "Robine Wake (PC)"
//! ```
//!
//! Development tool only: the product runs the same core on the ESP32.

use std::io::Write;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Instant;

use mdns_sd::{ServiceDaemon, ServiceInfo};
use robine_airplay::alac::{AlacConfig, AlacDecoder};
use robine_airplay::audio::{split_buffered, StreamCipher};
use robine_airplay::{Config, Connection, Event, Identity, Ports, Receiver, DEFAULT_PORT, STREAM_BUFFERED, STREAM_REALTIME};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream, UdpSocket};

fn random(bytes: &mut [u8]) {
    getrandom::fill(bytes).expect("operating system random source");
}

/// Bench files, outside the repository: identity and captures.
fn data_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_default()
        .join(".local/share/robine-airplay-bench")
}

/// AirPlay volume in dB (f32 bits), applied to the PCM before playback.
static VOLUME_DB: AtomicU32 = AtomicU32::new(0xC1A0_0000); // -20.0

/// Plays 44.1 kHz stereo PCM on the default output through PipeWire.
struct Speaker {
    child: Option<Child>,
}

impl Speaker {
    fn new() -> Self {
        let child = Command::new("pw-cat")
            .args(["--playback", "--raw", "--format", "s16", "--rate", "44100", "--channels", "2", "-"])
            .stdin(Stdio::piped())
            .spawn()
            .map_err(|error| eprintln!("no PipeWire playback (pw-cat): {error}"))
            .ok();
        Self { child }
    }

    fn play(&mut self, pcm: &[i16]) {
        let db = f32::from_bits(VOLUME_DB.load(Ordering::Relaxed));
        let gain = if db <= -144.0 { 0.0 } else { 10f32.powf(db / 20.0) };
        let mut bytes = Vec::with_capacity(pcm.len() * 2);
        for sample in pcm {
            bytes.extend_from_slice(&((f32::from(*sample) * gain) as i16).to_le_bytes());
        }
        if let Some(stdin) = self.child.as_mut().and_then(|child| child.stdin.as_mut()) {
            let _ = stdin.write_all(&bytes);
        }
    }
}

/// Stream type and cipher of the current stream, set by `SETUP`.
type CurrentStream = Arc<Mutex<Option<(i64, StreamCipher)>>>;

/// The identity must survive restarts, or the iPhone sees a new speaker.
fn load_identity() -> Identity {
    let path = data_dir().join("identity");
    if let Some(identity) = std::fs::read(&path).ok().and_then(|bytes| Identity::from_bytes(&bytes)) {
        return identity;
    }
    let identity = Identity::generate(random);
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    std::fs::write(&path, identity.to_bytes()).expect("cannot save the identity");
    eprintln!("new identity saved in {}", path.display());
    identity
}

#[tokio::main]
async fn main() {
    let name = std::env::args().nth(1).unwrap_or_else(|| "Robine Wake (PC)".into());
    let started = Instant::now();
    let mut config = Config::new(name.clone());
    // Capability experiments: ROBINE_FEATURES=0x... overrides the bitmask.
    if let Some(features) = std::env::var("ROBINE_FEATURES")
        .ok()
        .and_then(|value| u64::from_str_radix(value.trim_start_matches("0x"), 16).ok())
    {
        config.features = features;
    }
    eprintln!("features 0x{:X}", config.features);
    let receiver = Receiver::new(config, load_identity(), random);
    eprintln!(
        "receiver ready in {:?}: deviceid {}",
        started.elapsed(),
        receiver.identity.device_id_text()
    );

    let mdns = ServiceDaemon::new().expect("cannot start mDNS");
    let txt: Vec<(&str, String)> = receiver.txt_records();
    let properties: Vec<(&str, &str)> = txt.iter().map(|(key, value)| (*key, value.as_str())).collect();
    let service = ServiceInfo::new(
        "_airplay._tcp.local.",
        &name,
        "robine-airplay-bench.local.",
        "",
        DEFAULT_PORT,
        &properties[..],
    )
    .expect("invalid mDNS service")
    .enable_addr_auto();
    mdns.register(service).expect("cannot register the AirPlay service");
    eprintln!("advertising \"{name}\" on _airplay._tcp, port {DEFAULT_PORT}");

    let listener = TcpListener::bind(("0.0.0.0", DEFAULT_PORT))
        .await
        .expect("port 7000 is busy");
    let receiver = Arc::new(receiver);
    let current_stream: CurrentStream = Arc::default();
    spawn_session_listeners(receiver.ports, current_stream.clone());
    loop {
        tokio::select! {
            accepted = listener.accept() => {
                let Ok((stream, peer)) = accepted else { continue };
                let receiver = receiver.clone();
                let current = current_stream.clone();
                tokio::spawn(async move {
                    eprintln!("[{peer}] connected");
                    if let Err(error) = serve(stream, &receiver, &current).await {
                        eprintln!("[{peer}] closed: {error}");
                    } else {
                        eprintln!("[{peer}] closed");
                    }
                });
            }
            _ = tokio::signal::ctrl_c() => break,
        }
    }
    let _ = mdns.shutdown();
}

async fn serve(mut stream: TcpStream, receiver: &Receiver, current: &CurrentStream) -> std::io::Result<()> {
    let peer = stream.peer_addr()?;
    let local_ip = match stream.local_addr()?.ip() {
        std::net::IpAddr::V4(ip) => ip.octets(),
        std::net::IpAddr::V6(ip) => ip.to_ipv4_mapped().map_or([0; 4], |ip| ip.octets()),
    };
    let mut connection = Connection::new(local_ip);
    let mut buffer = vec![0u8; 16 * 1024];
    loop {
        let read = stream.read(&mut buffer).await?;
        if read == 0 {
            return Ok(());
        }
        let started = Instant::now();
        let output = connection
            .feed(receiver, &buffer[..read])
            .map_err(|error| std::io::Error::other(format!("{error:?}")))?;
        for event in &output.events {
            match event {
                Event::Request { method, target, encrypted, status } => {
                    let lock = if *encrypted { "🔒" } else { "  " };
                    eprintln!("[{peer}] {lock} {method} {target} -> {status} ({:?})", started.elapsed());
                }
                Event::Paired => eprintln!("[{peer}] ✅ transient pairing done, channel encrypted"),
                Event::PairingFailed => eprintln!("[{peer}] ❌ pairing failed"),
                Event::Body { method, summary } => eprintln!("[{peer}]      {method} {summary}"),
                Event::Stream(announced) => {
                    eprintln!(
                        "[{peer}] 🎵 stream type {} (ct {:?}, audioFormat {:?}, spf {:?})",
                        announced.kind, announced.compression, announced.audio_format, announced.samples_per_frame
                    );
                    *current.lock().unwrap() = Some((announced.kind, StreamCipher::new(&announced.key)));
                }
                Event::Volume { db } => {
                    VOLUME_DB.store(db.to_bits(), Ordering::Relaxed);
                    eprintln!("[{peer}] 🔊 volume {db} dB");
                }
                Event::RateAnchor { rate, rtp_time, .. } => {
                    eprintln!("[{peer}] {} rtpTime {rtp_time:?}", if *rate == 0 { "⏸ pause" } else { "▶ play" })
                }
                Event::Flush { until_seq } => eprintln!("[{peer}] ⏭ flush until {until_seq:?}"),
                Event::Teardown => eprintln!("[{peer}] ⏹ teardown"),
            }
        }
        stream.write_all(&output.reply).await?;
    }
}

/// Session channels: for now they only report what arrives, to watch the
/// audio flow before it is decrypted and decoded.
fn spawn_session_listeners(ports: Ports, current: CurrentStream) {
    tokio::spawn(async move {
        let listener = TcpListener::bind(("0.0.0.0", ports.event)).await.expect("event port busy");
        loop {
            if let Ok((mut stream, peer)) = listener.accept().await {
                eprintln!("[{peer}] event channel open");
                tokio::spawn(async move {
                    let mut buffer = [0u8; 1024];
                    while matches!(stream.read(&mut buffer).await, Ok(read) if read > 0) {}
                });
            }
        }
    });
    let buffered = current.clone();
    tokio::spawn(async move {
        let listener = TcpListener::bind(("0.0.0.0", ports.data)).await.expect("data port busy");
        loop {
            if let Ok((stream, peer)) = listener.accept().await {
                eprintln!("[{peer}] buffered audio channel open");
                tokio::spawn(buffered_audio(stream, buffered.clone()));
            }
        }
    });
    tokio::spawn(realtime_audio(ports.data, current));
    for (port, label) in [(ports.control, "control")] {
        tokio::spawn(async move {
            let socket = UdpSocket::bind(("0.0.0.0", port)).await.expect("UDP port busy");
            let (mut packets, mut buffer) = (0usize, vec![0u8; 2048]);
            let mut reported = Instant::now();
            while let Ok((_, peer)) = socket.recv_from(&mut buffer).await {
                packets += 1;
                if packets == 1 || reported.elapsed().as_secs() >= 2 {
                    eprintln!("[{peer}] {label}: {packets} UDP packets");
                    reported = Instant::now();
                }
            }
        });
    }
}

/// Packets kept in the capture (about 16 s).
const CAPTURE_PACKETS: usize = 2000;

/// Realtime audio: decrypt, decode, report levels, and keep a capture
/// (ALAC frames and a WAV file) for offline checks.
async fn realtime_audio(port: u16, current: CurrentStream) {
    let socket = UdpSocket::bind(("0.0.0.0", port)).await.expect("audio port busy");
    let mut decoder = AlacDecoder::new(AlacConfig::AIRPLAY);
    let mut speaker = Speaker::new();
    let (mut opened, mut failed, mut decoded, mut corrupt) = (0usize, 0usize, 0usize, 0usize);
    let mut peak = 0i16;
    let mut frames: Vec<Vec<u8>> = Vec::new();
    let mut pcm: Vec<i16> = Vec::new();
    let mut reported = Instant::now();
    let mut buffer = vec![0u8; 2048];
    while let Ok((read, peer)) = socket.recv_from(&mut buffer).await {
        let opened_packet = current
            .lock()
            .unwrap()
            .as_ref()
            .filter(|(kind, _)| *kind == STREAM_REALTIME)
            .map(|(_, cipher)| cipher.open(&buffer[..read]));
        match opened_packet {
            Some(Some((_, frame))) => {
                opened += 1;
                let start = pcm.len();
                match decoder.decode(&frame, &mut pcm) {
                    Ok(_) => decoded += 1,
                    Err(_) => corrupt += 1,
                }
                peak = pcm[start..].iter().fold(peak, |peak, sample| peak.max(sample.saturating_abs()));
                speaker.play(&pcm[start..]);
                if frames.len() < CAPTURE_PACKETS {
                    frames.push(frame);
                    if frames.len() == CAPTURE_PACKETS {
                        save_capture(&frames, &pcm);
                    }
                }
                if frames.len() >= CAPTURE_PACKETS {
                    pcm.clear();
                }
            }
            Some(None) => failed += 1,
            None => {}
        }
        if reported.elapsed().as_secs() >= 2 {
            eprintln!(
                "[{peer}] 🎧 audio: {opened} decrypted, {failed} rejected, {decoded} ALAC frames, {corrupt} corrupt, peak {:.1} dBFS",
                20.0 * (f64::from(peak.max(1)) / 32768.0).log10()
            );
            peak = 0;
            reported = Instant::now();
        }
    }
}

/// Raw ALAC frames (u16 length + bytes) and the decoded PCM as WAV.
fn save_capture(frames: &[Vec<u8>], pcm: &[i16]) {
    let directory = data_dir();
    let mut raw = Vec::new();
    for frame in frames {
        raw.extend_from_slice(&(frame.len() as u16).to_be_bytes());
        raw.extend_from_slice(frame);
    }
    let _ = std::fs::write(directory.join("capture.alac"), raw);

    let data_len = (pcm.len() * 2) as u32;
    let mut wav = Vec::with_capacity(44 + pcm.len() * 2);
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&(36 + data_len).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt ");
    wav.extend_from_slice(&16u32.to_le_bytes());
    wav.extend_from_slice(&1u16.to_le_bytes()); // PCM
    wav.extend_from_slice(&2u16.to_le_bytes()); // stereo
    wav.extend_from_slice(&44_100u32.to_le_bytes());
    wav.extend_from_slice(&(44_100u32 * 4).to_le_bytes());
    wav.extend_from_slice(&4u16.to_le_bytes());
    wav.extend_from_slice(&16u16.to_le_bytes());
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&data_len.to_le_bytes());
    for sample in pcm {
        wav.extend_from_slice(&sample.to_le_bytes());
    }
    match std::fs::File::create(directory.join("capture.wav")).and_then(|mut file| file.write_all(&wav)) {
        Ok(()) => eprintln!("💾 capture saved in {} ({} frames)", directory.display(), frames.len()),
        Err(error) => eprintln!("capture not saved: {error}"),
    }
}

/// AAC frames kept in the buffered capture (about 23 s).
const CAPTURE_AAC_FRAMES: usize = 1000;

/// Buffered audio: split the TCP blocks, decrypt, and keep the first AAC
/// frames as an ADTS file (playable, and decodable by ffmpeg for tests).
async fn buffered_audio(mut stream: TcpStream, current: CurrentStream) {
    let peer = stream.peer_addr().map(|peer| peer.to_string()).unwrap_or_default();
    let (mut pending, mut chunk) = (Vec::new(), vec![0u8; 64 * 1024]);
    let (mut opened, mut failed) = (0usize, 0usize);
    let mut sizes = (usize::MAX, 0usize);
    let mut adts = Vec::new();
    let mut reported = Instant::now();
    while let Ok(read) = stream.read(&mut chunk).await {
        if read == 0 {
            break;
        }
        pending.extend_from_slice(&chunk[..read]);
        let (packets, used) = split_buffered(&pending);
        for packet in packets {
            let guard = current.lock().unwrap();
            let Some((_, cipher)) = guard.as_ref().filter(|(kind, _)| *kind == STREAM_BUFFERED) else {
                continue;
            };
            match cipher.open_buffered(packet) {
                Some((_, frame)) => {
                    opened += 1;
                    sizes = (sizes.0.min(frame.len()), sizes.1.max(frame.len()));
                    if opened <= CAPTURE_AAC_FRAMES {
                        adts.extend_from_slice(&adts_header(frame.len()));
                        adts.extend_from_slice(&frame);
                        if opened == CAPTURE_AAC_FRAMES {
                            let path = data_dir().join("capture.aac");
                            match std::fs::write(&path, &adts) {
                                Ok(()) => eprintln!("💾 AAC capture saved in {} ({CAPTURE_AAC_FRAMES} frames)", path.display()),
                                Err(error) => eprintln!("AAC capture not saved: {error}"),
                            }
                        }
                    }
                }
                None => failed += 1,
            }
        }
        pending.drain(..used);
        if reported.elapsed().as_secs() >= 2 {
            eprintln!(
                "[{peer}] 🎧 buffered: {opened} AAC frames decrypted ({}-{} bytes), {failed} rejected",
                sizes.0.min(sizes.1),
                sizes.1
            );
            reported = Instant::now();
        }
    }
    eprintln!("[{peer}] buffered audio closed: {opened} frames, {failed} rejected");
}

/// ADTS header of an AAC-LC frame, 44.1 kHz stereo.
fn adts_header(payload: usize) -> [u8; 7] {
    let length = payload + 7;
    [
        0xFF,
        0xF1, // MPEG-4, no CRC
        0x50, // AAC LC, 44.1 kHz (index 4)
        0x80 | (length >> 11) as u8, // 2 channels
        (length >> 3) as u8,
        ((length & 7) << 5) as u8 | 0x1F,
        0xFC,
    ]
}
