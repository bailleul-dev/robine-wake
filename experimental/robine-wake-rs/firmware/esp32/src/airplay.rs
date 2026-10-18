//! AirPlay 2 receiver: embassy-net sockets and timing around the
//! `robine-airplay` core.
//!
//! Until the amplifier is wired, the decoded audio is only measured: peak
//! level, decoding time and frames played on time.

use alloc::collections::VecDeque;
use alloc::string::String;
use alloc::vec::Vec;
use core::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};

use edge_mdns::buf::VecBufAccess;
use edge_mdns::domain::base::Ttl;
use edge_mdns::host::{Host, Service, ServiceAnswers};
use edge_mdns::{io, HostAnswersMdnsHandler};
use edge_nal::UdpSplit;
use edge_nal_embassy::{Udp, UdpBuffers};
use embassy_net::tcp::TcpSocket;
use embassy_net::udp::{PacketMetadata, UdpSocket};
use embassy_net::{IpAddress, Stack};
use embassy_sync::blocking_mutex::raw::{CriticalSectionRawMutex, NoopRawMutex};
use embassy_sync::mutex::Mutex;
use embassy_sync::signal::Signal;
use embassy_time::{Duration, Instant, Timer};
use embedded_io_async::Write;
use log::{info, warn};
use static_cell::StaticCell;
use robine_airplay::aac::AacDecoder;
use robine_airplay::alac::{AlacConfig, AlacDecoder};
use robine_airplay::audio::{split_buffered, StreamCipher};
use robine_airplay::ptp::{Anchor, PtpFollower};
use robine_airplay::{Config, Connection, Event, Identity, Receiver, DEFAULT_PORT, STREAM_BUFFERED, STREAM_REALTIME};

/// Name shown in the AirPlay picker.
pub const NAME: &str = "Robine Wake";
/// Buffered stream bytes held ahead of playback: the Heltec V1 has no PSRAM.
const QUEUE_BYTES: usize = 48 * 1024;
/// Request bodies above this (cover art) are skipped.
const MAX_BODY: usize = 16 * 1024;
/// Heap a buffered-stream AAC decoder needs, with margin.
const AAC_HEAP: usize = 90 * 1024;
/// Frames this late are dropped.
const LATE_NS: i64 = 30_000_000;

struct Frame {
    sequence: u32,
    timestamp: u32,
    data: Vec<u8>,
}

#[derive(Default)]
struct Stats {
    realtime_frames: u32,
    buffered_played: u32,
    late: u32,
    corrupt: u32,
    rejected: u32,
    decode_us: u64,
    decoded: u32,
    peak: i16,
}

impl Stats {
    fn decoded(&mut self, started: Instant, pcm: &[i16]) {
        self.decode_us += started.elapsed().as_micros();
        self.decoded += 1;
        self.peak = pcm.iter().fold(self.peak, |peak, sample| peak.max(sample.saturating_abs()));
    }
}

#[derive(Default)]
struct State {
    stream: Option<(i64, StreamCipher)>,
    ptp: PtpFollower,
    anchor: Option<Anchor>,
    playing: bool,
    volume_db: f32,
    flush_until: Option<u32>,
    queue: VecDeque<Frame>,
    queued_bytes: usize,
    stats: Stats,
}

impl State {
    fn reset_stream(&mut self) {
        self.queue.clear();
        self.queued_bytes = 0;
        (self.anchor, self.playing, self.flush_until) = (None, false, None);
    }
}

pub struct Airplay {
    receiver: Receiver,
    state: Mutex<CriticalSectionRawMutex, State>,
}

/// Local monotonic time in nanoseconds, shared by PTP and playback.
fn local_ns() -> i64 {
    Instant::now().as_micros() as i64 * 1_000
}

impl Airplay {
    /// Computes the pairing verifier (one 3072-bit exponentiation).
    pub fn new(mac: [u8; 6], random: robine_airplay::RandomSource) -> Self {
        let started = Instant::now();
        let mut config = Config::new(NAME);
        config.audio_buffer_size = QUEUE_BYTES as u32;
        let receiver = Receiver::new(config, Identity::derive(mac, b"robine-wake"), random);
        info!(
            "AirPlay receiver ready in {} ms (deviceid {})",
            started.elapsed().as_millis(),
            receiver.identity.device_id_text()
        );
        Self { receiver, state: Mutex::new(State::default()) }
    }

    async fn handle(&self, events: &[Event], started: Instant) {
        let mut state = self.state.lock().await;
        for event in events {
            match event {
                Event::Request { method, target, encrypted, status } => info!(
                    "airplay {}{method} {target} -> {status} ({} ms)",
                    if *encrypted { "[enc] " } else { "" },
                    started.elapsed().as_millis()
                ),
                Event::Paired => info!("airplay: paired, channel encrypted"),
                Event::PairingFailed => warn!("airplay: pairing failed"),
                Event::Body { method, summary } => {
                    let end = summary.char_indices().nth(240).map_or(summary.len(), |(index, _)| index);
                    info!("airplay   {method} {}", &summary[..end]);
                }
                Event::Stream(stream) => {
                    info!("airplay: stream type {} (ct {:?})", stream.kind, stream.compression);
                    state.reset_stream();
                    state.stream = Some((stream.kind, StreamCipher::new(&stream.key)));
                }
                Event::Volume { db } => state.volume_db = *db,
                Event::RateAnchor { rate, anchor, timeline } => {
                    if let Some(timeline) = timeline {
                        state.ptp.set_timeline(*timeline);
                    }
                    if anchor.is_some() {
                        state.anchor = *anchor;
                    }
                    state.playing = *rate != 0;
                    info!("airplay: {} (PTP {})", if *rate == 0 { "pause" } else { "play" }, state.ptp.offset().is_some());
                }
                Event::Flush { until_seq } => {
                    if let Some(until) = until_seq.map(|until| until as u32) {
                        state.queue.retain(|frame| frame.sequence >= until);
                        state.queued_bytes = state.queue.iter().map(|frame| frame.data.len()).sum();
                        state.flush_until = Some(until);
                    }
                }
                Event::Teardown => {
                    state.reset_stream();
                    state.stream = None;
                }
            }
        }
    }
}

fn ipv4(address: Option<IpAddress>) -> [u8; 4] {
    match address {
        Some(IpAddress::Ipv4(ip)) => ip.octets(),
        _ => [0; 4],
    }
}

/// Control connections (TCP 7000).
#[embassy_executor::task(pool_size = 2)]
pub async fn control_task(stack: Stack<'static>, airplay: &'static Airplay) {
    let (mut rx, mut tx, mut buffer) = ([0u8; 4096], [0u8; 4096], [0u8; 1536]);
    loop {
        let mut socket = TcpSocket::new(stack, &mut rx, &mut tx);
        if socket.accept(DEFAULT_PORT).await.is_err() {
            continue;
        }
        let local = ipv4(socket.local_endpoint().map(|endpoint| endpoint.addr));
        let mut connection = Connection::new(local).with_max_body(MAX_BODY);
        loop {
            let read = match socket.read(&mut buffer).await {
                Ok(0) | Err(_) => break,
                Ok(read) => read,
            };
            let started = Instant::now();
            let output = match connection.feed(&airplay.receiver, &buffer[..read]) {
                Ok(output) => output,
                Err(error) => {
                    warn!("airplay: control connection closed: {error:?}");
                    break;
                }
            };
            airplay.handle(&output.events, started).await;
            if socket.write_all(&output.reply).await.is_err() {
                break;
            }
        }
        socket.abort();
        let _ = socket.flush().await;
    }
}

/// Event channel (TCP 7001): kept open, nothing is sent on it.
#[embassy_executor::task]
pub async fn event_task(stack: Stack<'static>, airplay: &'static Airplay) {
    let (mut rx, mut tx, mut buffer) = ([0u8; 512], [0u8; 256], [0u8; 256]);
    loop {
        let mut socket = TcpSocket::new(stack, &mut rx, &mut tx);
        if socket.accept(airplay.receiver.ports.event).await.is_err() {
            continue;
        }
        while matches!(socket.read(&mut buffer).await, Ok(read) if read > 0) {}
        socket.abort();
    }
}

/// Buffered audio (TCP 7002): queued with their timestamps, up to
/// `QUEUE_BYTES`; reading pauses when the queue is full.
#[embassy_executor::task]
pub async fn buffered_task(stack: Stack<'static>, airplay: &'static Airplay) {
    let (mut rx, mut tx, mut chunk) = ([0u8; 8192], [0u8; 128], [0u8; 1460]);
    loop {
        let mut socket = TcpSocket::new(stack, &mut rx, &mut tx);
        if socket.accept(airplay.receiver.ports.data).await.is_err() {
            continue;
        }
        info!("airplay: buffered audio connected");
        let mut pending: Vec<u8> = Vec::with_capacity(4096);
        loop {
            if airplay.state.lock().await.queued_bytes >= QUEUE_BYTES {
                Timer::after(Duration::from_millis(10)).await;
                continue;
            }
            let read = match socket.read(&mut chunk).await {
                Ok(0) | Err(_) => break,
                Ok(read) => read,
            };
            pending.extend_from_slice(&chunk[..read]);
            let (packets, used) = split_buffered(&pending);
            let mut state = airplay.state.lock().await;
            for packet in packets {
                let opened = match &state.stream {
                    Some((STREAM_BUFFERED, cipher)) => cipher.open_buffered(packet),
                    _ => continue,
                };
                match opened {
                    Some((header, data)) => {
                        if state.flush_until.is_none_or(|until| header.sequence >= until) {
                            state.queued_bytes += data.len();
                            state.queue.push_back(Frame { sequence: header.sequence, timestamp: header.timestamp, data });
                        }
                    }
                    None => state.stats.rejected += 1,
                }
            }
            drop(state);
            pending.drain(..used);
        }
        socket.abort();
        info!("airplay: buffered audio closed");
    }
}

/// Realtime audio (UDP 7002): ALAC decoded on arrival.
#[embassy_executor::task]
pub async fn realtime_task(stack: Stack<'static>, airplay: &'static Airplay) {
    let (mut rx_meta, mut tx_meta) = ([PacketMetadata::EMPTY; 8], [PacketMetadata::EMPTY; 1]);
    let (mut rx, mut tx, mut buffer) = ([0u8; 8192], [0u8; 64], [0u8; 1600]);
    let mut socket = UdpSocket::new(stack, &mut rx_meta, &mut rx, &mut tx_meta, &mut tx);
    socket.bind(airplay.receiver.ports.data).expect("audio port");
    let mut decoder = AlacDecoder::new(AlacConfig::AIRPLAY);
    let mut pcm = Vec::with_capacity(704);
    while let Ok((read, _)) = socket.recv_from(&mut buffer).await {
        let mut state = airplay.state.lock().await;
        let opened = match &state.stream {
            Some((STREAM_REALTIME, cipher)) => cipher.open(&buffer[..read]),
            _ => continue,
        };
        let Some((_, frame)) = opened else {
            state.stats.rejected += 1;
            continue;
        };
        pcm.clear();
        let started = Instant::now();
        match decoder.decode(&frame, &mut pcm) {
            Ok(_) => {
                state.stats.decoded(started, &pcm);
                state.stats.realtime_frames += 1;
            }
            Err(_) => state.stats.corrupt += 1,
        }
    }
}

/// Retransmission channel (UDP 7003): drained.
#[embassy_executor::task]
pub async fn control_udp_task(stack: Stack<'static>, airplay: &'static Airplay) {
    let (mut rx_meta, mut tx_meta) = ([PacketMetadata::EMPTY; 2], [PacketMetadata::EMPTY; 1]);
    let (mut rx, mut tx, mut buffer) = ([0u8; 1024], [0u8; 64], [0u8; 512]);
    let mut socket = UdpSocket::new(stack, &mut rx_meta, &mut rx, &mut tx_meta, &mut tx);
    socket.bind(airplay.receiver.ports.control).expect("control port");
    while socket.recv_from(&mut buffer).await.is_ok() {}
}

/// PTP event (319) and general (320) messages: the sender's clock.
#[embassy_executor::task(pool_size = 2)]
pub async fn ptp_task(stack: Stack<'static>, airplay: &'static Airplay, port: u16) {
    let (mut rx_meta, mut tx_meta) = ([PacketMetadata::EMPTY; 4], [PacketMetadata::EMPTY; 1]);
    let (mut rx, mut tx, mut buffer) = ([0u8; 1024], [0u8; 64], [0u8; 256]);
    let mut socket = UdpSocket::new(stack, &mut rx_meta, &mut rx, &mut tx_meta, &mut tx);
    socket.bind(port).expect("PTP port");
    let mut announced = false;
    while let Ok((read, peer)) = socket.recv_from(&mut buffer).await {
        let arrival = local_ns();
        let mut state = airplay.state.lock().await;
        if state.ptp.receive(&buffer[..read], arrival) && !announced {
            announced = true;
            info!("airplay: following the PTP clock of {}", peer.endpoint.addr);
        }
    }
}

/// Plays queued buffered frames when the sender's clock reaches their time.
/// Without an amplifier, playing means decoding and measuring.
#[embassy_executor::task]
pub async fn player_task(airplay: &'static Airplay) {
    let mut decoder: Option<AacDecoder> = None;
    let mut warned = false;
    let mut pcm = Vec::with_capacity(2048);
    loop {
        let frame = {
            let mut state = airplay.state.lock().await;
            let (Some(anchor), true) = (state.anchor, state.playing) else {
                drop(state);
                Timer::after(Duration::from_millis(10)).await;
                continue;
            };
            let Some(front) = state.queue.front() else {
                drop(state);
                Timer::after(Duration::from_millis(5)).await;
                continue;
            };
            let Some(target) = state.ptp.to_local(anchor.master_time(front.timestamp, 44_100)) else {
                drop(state);
                Timer::after(Duration::from_millis(10)).await;
                continue;
            };
            let lead = target - local_ns();
            if lead > 0 {
                drop(state);
                Timer::after(Duration::from_micros((lead / 1_000).min(20_000) as u64)).await;
                continue;
            }
            let frame = state.queue.pop_front().expect("front exists");
            state.queued_bytes -= frame.data.len();
            if lead < -LATE_NS {
                state.stats.late += 1;
                continue;
            }
            frame
        };

        if decoder.is_none() {
            if esp_alloc::HEAP.free() < AAC_HEAP {
                if !warned {
                    warned = true;
                    warn!("airplay: {} bytes free, not enough for the AAC decoder", esp_alloc::HEAP.free());
                }
                continue;
            }
            decoder = AacDecoder::new(2).ok();
        }
        let Some(aac) = decoder.as_mut() else {
            continue;
        };
        pcm.clear();
        let started = Instant::now();
        let result = aac.decode(&frame.data, &mut pcm);
        let mut state = airplay.state.lock().await;
        match result {
            Ok(_) => {
                state.stats.decoded(started, &pcm);
                state.stats.buffered_played += 1;
            }
            Err(_) => state.stats.corrupt += 1,
        }
    }
}

/// Logs audio statistics every 5 s while audio flows.
#[embassy_executor::task]
pub async fn stats_task(airplay: &'static Airplay) {
    loop {
        Timer::after(Duration::from_secs(5)).await;
        let mut state = airplay.state.lock().await;
        let stats = core::mem::take(&mut state.stats);
        if stats.decoded + stats.late + stats.rejected + stats.corrupt == 0 {
            continue;
        }
        let peak_db = 20.0 * libm::log10f(f32::from(stats.peak.max(1)) / 32_768.0);
        info!(
            "airplay audio/5 s: {} realtime, {} buffered on time, {} late, {} rejected, {} corrupt; decode {} us/frame; peak {:.1} dBFS; volume {:.1} dB; queue {} B; heap free {} B",
            stats.realtime_frames,
            stats.buffered_played,
            stats.late,
            stats.rejected,
            stats.corrupt,
            stats.decode_us / u64::from(stats.decoded.max(1)),
            peak_db,
            state.volume_db,
            state.queued_bytes,
            esp_alloc::HEAP.free()
        );
    }
}

/// Hardware random numbers for the mDNS responder.
struct HardwareRng;

impl rand_core::TryRng for HardwareRng {
    type Error = core::convert::Infallible;

    fn try_next_u32(&mut self) -> Result<u32, Self::Error> {
        Ok(esp_hal::rng::Rng::new().random())
    }

    fn try_next_u64(&mut self) -> Result<u64, Self::Error> {
        let rng = esp_hal::rng::Rng::new();
        Ok((u64::from(rng.random()) << 32) | u64::from(rng.random()))
    }

    fn try_fill_bytes(&mut self, destination: &mut [u8]) -> Result<(), Self::Error> {
        let rng = esp_hal::rng::Rng::new();
        for chunk in destination.chunks_mut(4) {
            chunk.copy_from_slice(&rng.random().to_le_bytes()[..chunk.len()]);
        }
        Ok(())
    }
}

/// Announces `_airplay._tcp` and the host name on mDNS.
#[embassy_executor::task]
pub async fn mdns_task(stack: Stack<'static>, airplay: &'static Airplay) {
    static BUFFERS: StaticCell<UdpBuffers<1, 1500, 1500, 2>> = StaticCell::new();
    let buffers = BUFFERS.init(UdpBuffers::new());
    stack.wait_config_up().await;
    let Some(config) = stack.config_v4() else {
        return;
    };
    let udp = Udp::new(stack, buffers);
    let address = SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), io::PORT);
    let mut socket = match io::bind(&udp, address, Some(Ipv4Addr::UNSPECIFIED), None).await {
        Ok(socket) => socket,
        Err(error) => {
            warn!("mDNS: cannot bind: {error:?}");
            return;
        }
    };
    let (recv, send) = socket.split();

    let host = Host {
        hostname: "robine-wake",
        ipv4: config.address.address(),
        ipv6: Ipv6Addr::UNSPECIFIED,
        ttl: Ttl::from_secs(120),
    };
    let txt: Vec<(&'static str, String)> = airplay.receiver.txt_records();
    let txt_kvs: Vec<(&str, &str)> = txt.iter().map(|(key, value)| (*key, value.as_str())).collect();
    let service = Service {
        name: NAME,
        priority: 1,
        weight: 5,
        service: "_airplay",
        protocol: "_tcp",
        port: DEFAULT_PORT,
        service_subtypes: &[],
        txt_kvs: &txt_kvs,
    };
    let (recv_buf, send_buf) = (VecBufAccess::<NoopRawMutex, 1500>::new(), VecBufAccess::<NoopRawMutex, 1500>::new());
    let signal = Signal::<NoopRawMutex, ()>::new();
    let mdns = io::Mdns::new(Some(Ipv4Addr::UNSPECIFIED), None, recv, send, &recv_buf, &send_buf, HardwareRng, &signal);
    info!("mDNS: announcing \"{NAME}\" (_airplay._tcp) on {}", config.address.address());
    if let Err(error) = mdns.run(HostAnswersMdnsHandler::new(ServiceAnswers::new(&host, &service))).await {
        warn!("mDNS stopped: {error:?}");
    }
}
