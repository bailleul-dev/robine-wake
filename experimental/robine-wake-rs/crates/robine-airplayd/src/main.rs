//! AirPlay 2 receiver for the Raspberry Pi, on the project's own
//! `robine-airplay` core (the one the ESP32 runs), as a lighter alternative
//! to Shairport Sync + NQPTP + Avahi.
//!
//! ```sh
//! robine-airplayd --name "Robine Wake Bedroom" --device plughw:0 --data-dir /data/airplay
//! ```
//!
//! The Elixir app starts it through a port and talks to it as described in
//! [`control`]. It advertises itself over mDNS, follows the sender's PTP clock
//! on ports 319/320 (NQPTP must not run) and plays on one ALSA device, in
//! sync with the sender's clock ([`player`]).

mod control;
mod player;
mod queue;
mod speaker;

use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use mdns_sd::{ServiceDaemon, ServiceInfo};
use robine_airplay::audio::{split_buffered, StreamCipher};
use robine_airplay::ptp::{Anchor, PtpFollower};
use robine_airplay::realtime::{resend_request, resent_packet, Sync};
use robine_airplay::{Config, Connection, Event, Identity, Ports, Receiver, DEFAULT_PORT, STREAM_BUFFERED, STREAM_REALTIME};
use serde_json::json;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream, UdpSocket};

use control::emit;
use queue::{Frame, FrameQueue, Insert};
use speaker::{Speaker, VOLUME_DB};

/// Volume proposed to senders, and restored after a long idle time at a high
/// volume, so the alarm clock does not blast the next morning (the values of
/// the Shairport Sync configuration).
const DEFAULT_VOLUME_DB: f32 = -7.5;
const HIGH_VOLUME_DB: f32 = -3.0;
const HIGH_VOLUME_IDLE: Duration = Duration::from_secs(60 * 60);

struct Options {
    name: String,
    device: String,
    data_dir: PathBuf,
    /// mDNS host name, distinct from the Pi's own (`robine-wake.local`).
    host: String,
}

impl Options {
    fn parse() -> Self {
        let mut options = Self {
            name: "Robine Wake Bedroom".into(),
            device: "plughw:0".into(),
            data_dir: PathBuf::from("/data/airplay"),
            host: "robine-wake-airplay".into(),
        };
        let mut args = std::env::args().skip(1);
        while let Some(flag) = args.next() {
            let value = args.next().unwrap_or_else(|| usage(&format!("{flag} needs a value")));
            match flag.as_str() {
                "--name" => options.name = value,
                "--device" => options.device = value,
                "--data-dir" => options.data_dir = value.into(),
                "--host" => options.host = value,
                _ => usage(&format!("unknown option {flag}")),
            }
        }
        options
    }
}

fn usage(error: &str) -> ! {
    eprintln!("{error}\nusage: robine-airplayd [--name NAME] [--device ALSA_DEVICE] [--data-dir DIR] [--host MDNS_HOST]");
    std::process::exit(2);
}

fn random(bytes: &mut [u8]) {
    getrandom::fill(bytes).expect("operating system random source");
}

/// Local monotonic clock, in nanoseconds, shared by PTP and playback.
pub fn local_ns() -> i64 {
    static EPOCH: OnceLock<Instant> = OnceLock::new();
    EPOCH.get_or_init(Instant::now).elapsed().as_nanos() as i64
}

/// The identity must survive restarts, or senders see a new speaker.
fn load_identity(data_dir: &std::path::Path) -> Identity {
    let path = data_dir.join("identity");
    if let Some(identity) = std::fs::read(&path).ok().and_then(|bytes| Identity::from_bytes(&bytes)) {
        return identity;
    }
    let identity = Identity::generate(random);
    let saved = std::fs::create_dir_all(data_dir).and_then(|()| std::fs::write(&path, identity.to_bytes()));
    if let Err(error) = saved {
        eprintln!("identity not saved in {}: {error}", path.display());
    }
    identity
}

#[derive(Default, PartialEq)]
pub struct Stats {
    /// Frames received.
    realtime_frames: u64,
    buffered_frames: u64,
    /// Frames dropped because they came too late to play.
    late_frames: u64,
    /// Sync errors beyond the stuffing range, corrected at once.
    resyncs: u64,
    /// Frames dropped or repeated to follow the sender's clock.
    stuffed: u64,
    /// Writes padded with silence while playing.
    underruns: u64,
    resend_requested: u64,
    resent: u64,
    corrupt: u64,
    /// Packets failing authentication.
    rejected: u64,
    peak: i16,
}

impl Stats {
    fn peak(&mut self, pcm: &[i16]) {
        self.peak = pcm.iter().fold(self.peak, |peak, sample| peak.max(sample.saturating_abs()));
    }
}

/// Current stream, the sender's clock and anchor, and the frames waiting
/// for their play time.
#[derive(Default)]
pub struct State {
    stream: Option<(i64, StreamCipher)>,
    ptp: PtpFollower,
    anchor: Option<Anchor>,
    playing: bool,
    flush_until: Option<u32>,
    queue: FrameQueue,
    /// Bumped when queued audio is discarded, so the player drops its own.
    generation: u64,
    /// Where realtime sync packets come from, for resend requests.
    control_peer: Option<SocketAddr>,
    /// Last time audio was played.
    active_at: Option<Instant>,
    stats: Stats,
}

impl State {
    fn reset_stream(&mut self) {
        self.queue = FrameQueue::default();
        self.generation += 1;
        (self.anchor, self.playing, self.flush_until, self.control_peer) = (None, false, None, None);
    }
}

pub type Shared = Arc<Mutex<State>>;

#[tokio::main]
async fn main() {
    let options = Options::parse();
    let started = Instant::now();
    let receiver = Arc::new(Receiver::new(Config::new(options.name.clone()), load_identity(&options.data_dir), random));
    let device_id = receiver.identity.device_id_text();
    eprintln!("receiver ready in {:?}: deviceid {device_id}", started.elapsed());

    let mdns = ServiceDaemon::new().expect("cannot start mDNS");
    let txt = receiver.txt_records();
    let properties: Vec<(&str, &str)> = txt.iter().map(|(key, value)| (*key, value.as_str())).collect();
    let service = ServiceInfo::new(
        "_airplay._tcp.local.",
        &options.name,
        &format!("{}.local.", options.host),
        "",
        DEFAULT_PORT,
        &properties[..],
    )
    .expect("invalid mDNS service")
    .enable_addr_auto();
    mdns.register(service).expect("cannot register the AirPlay service");

    let listener = TcpListener::bind(("0.0.0.0", DEFAULT_PORT)).await.expect("port 7000 is busy");
    let state: Shared = Arc::default();
    let (speaker, messages) = Speaker::new();
    let player = (options.device.clone(), state.clone());
    std::thread::spawn(move || player::run(player.0, player.1, messages));
    spawn_session_listeners(receiver.ports, state.clone()).await;
    spawn_ptp_listeners(state.clone());
    receiver.set_initial_volume(Some(DEFAULT_VOLUME_DB));
    tokio::spawn(reset_high_volume(receiver.clone(), state.clone()));
    tokio::spawn(control::read_commands(speaker.clone()));
    emit("ready", json!({ "name": options.name, "device_id": device_id, "port": DEFAULT_PORT }));

    loop {
        let Ok((stream, peer)) = listener.accept().await else { continue };
        let (receiver, state, speaker) = (receiver.clone(), state.clone(), speaker.clone());
        tokio::spawn(async move {
            emit("client", json!({ "state": "connected", "peer": peer.to_string() }));
            let result = serve(stream, &receiver, &state, &speaker).await;
            let reason = result.err().map(|error| error.to_string());
            emit("client", json!({ "state": "disconnected", "peer": peer.to_string(), "reason": reason }));
        });
    }
}

async fn serve(mut stream: TcpStream, receiver: &Receiver, state: &Shared, speaker: &Speaker) -> std::io::Result<()> {
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
        let output = connection
            .feed(receiver, &buffer[..read])
            .map_err(|error| std::io::Error::other(format!("{error:?}")))?;
        for event in &output.events {
            handle(event, receiver, state, speaker);
        }
        stream.write_all(&output.reply).await?;
    }
}

fn handle(event: &Event, receiver: &Receiver, state: &Shared, speaker: &Speaker) {
    match event {
        Event::Request { method, target, status, .. } => eprintln!("{method} {target} -> {status}"),
        Event::Paired => eprintln!("transient pairing done"),
        Event::PairingFailed => emit("error", json!({ "reason": "pairing_failed" })),
        Event::Body { .. } => {}
        Event::Stream(stream) => {
            let mut state = state.lock().unwrap();
            state.reset_stream();
            state.stream = Some((stream.kind, StreamCipher::new(&stream.key)));
            // A realtime stream plays once its first sync packet anchors it.
            state.playing = stream.kind == STREAM_REALTIME;
            let kind = if stream.kind == STREAM_BUFFERED { "buffered" } else { "realtime" };
            emit("stream", json!({ "kind": kind, "compression": stream.compression }));
        }
        Event::Volume { db } => {
            VOLUME_DB.store(db.to_bits(), Ordering::Relaxed);
            receiver.set_initial_volume(Some(*db));
            emit("volume", json!({ "db": db }));
        }
        Event::RateAnchor { rate, anchor, timeline } => {
            let mut state = state.lock().unwrap();
            if let Some(timeline) = timeline {
                state.ptp.set_timeline(*timeline);
            }
            if anchor.is_some() {
                state.anchor = *anchor;
            }
            state.playing = *rate != 0;
            emit("session", json!({ "state": if state.playing { "playing" } else { "paused" } }));
        }
        Event::Flush { until_seq } => {
            let mut state = state.lock().unwrap();
            if let Some(until) = until_seq.map(|until| until as u32) {
                state.queue.flush(until);
                state.flush_until = Some(until);
                state.generation += 1;
            }
        }
        Event::Teardown => {
            state.lock().unwrap().reset_stream();
            speaker.close();
            emit("session", json!({ "state": "stopped" }));
        }
    }
}

async fn spawn_session_listeners(ports: Ports, state: Shared) {
    // The event channel only has to stay open.
    tokio::spawn(async move {
        let listener = TcpListener::bind(("0.0.0.0", ports.event)).await.expect("event port busy");
        loop {
            if let Ok((mut stream, _)) = listener.accept().await {
                tokio::spawn(async move {
                    let mut buffer = [0u8; 1024];
                    while matches!(stream.read(&mut buffer).await, Ok(read) if read > 0) {}
                });
            }
        }
    });
    let buffered = state.clone();
    tokio::spawn(async move {
        let listener = TcpListener::bind(("0.0.0.0", ports.data)).await.expect("data port busy");
        loop {
            if let Ok((stream, _)) = listener.accept().await {
                tokio::spawn(buffered_audio(stream, buffered.clone()));
            }
        }
    });
    let control = Arc::new(UdpSocket::bind(("0.0.0.0", ports.control)).await.expect("control port busy"));
    tokio::spawn(realtime_audio(ports.data, state.clone(), control.clone()));
    tokio::spawn(realtime_control(control, state));
}

/// Opens a realtime packet and queues its frame; returns the resend request
/// for the packets a gap shows lost.
fn queue_realtime(state: &mut State, packet: &[u8]) -> Option<[u8; 8]> {
    let opened = state
        .stream
        .as_ref()
        .filter(|(kind, _)| *kind == STREAM_REALTIME)
        .map(|(_, cipher)| cipher.open(packet))?;
    let Some((header, data)) = opened else {
        state.stats.rejected += 1;
        return None;
    };
    state.stats.realtime_frames += 1;
    let frame = Frame { sequence: u32::from(header.sequence), timestamp: header.timestamp, data };
    match state.queue.insert(frame) {
        Insert::Missing { first, count } => {
            state.stats.resend_requested += u64::from(count);
            Some(resend_request(first, count))
        }
        Insert::Late => {
            state.stats.late_frames += 1;
            None
        }
        Insert::Queued | Insert::Duplicate => None,
    }
}

/// Realtime stream: one ALAC frame per datagram, possibly out of order.
async fn realtime_audio(port: u16, state: Shared, control: Arc<UdpSocket>) {
    let socket = UdpSocket::bind(("0.0.0.0", port)).await.expect("audio port busy");
    let mut buffer = vec![0u8; 2048];
    while let Ok((read, _)) = socket.recv_from(&mut buffer).await {
        let request = {
            let mut state = state.lock().unwrap();
            queue_realtime(&mut state, &buffer[..read]).zip(state.control_peer)
        };
        if let Some((request, peer)) = request {
            let _ = control.send_to(&request, peer).await;
        }
    }
}

/// Realtime control port: sync packets anchor the stream on the sender's
/// clock; resent packets fill the gaps.
async fn realtime_control(socket: Arc<UdpSocket>, state: Shared) {
    let mut buffer = vec![0u8; 2048];
    while let Ok((read, peer)) = socket.recv_from(&mut buffer).await {
        let packet = &buffer[..read];
        let mut state = state.lock().unwrap();
        if !matches!(state.stream, Some((STREAM_REALTIME, _))) {
            continue;
        }
        if let Some(sync) = Sync::parse(packet) {
            state.ptp.set_timeline(sync.clock);
            state.anchor = Some(sync.anchor());
            state.control_peer = Some(peer);
        } else if let Some(audio) = resent_packet(packet) {
            state.stats.resent += 1;
            // A resent packet that shows another gap is not chased.
            let _ = queue_realtime(&mut state, audio);
        }
    }
}

/// Buffered stream: split the TCP blocks, decrypt and queue the AAC frames
/// with their RTP timestamp for the player.
async fn buffered_audio(mut stream: TcpStream, state: Shared) {
    let (mut pending, mut chunk) = (Vec::new(), vec![0u8; 64 * 1024]);
    while let Ok(read) = stream.read(&mut chunk).await {
        if read == 0 {
            break;
        }
        pending.extend_from_slice(&chunk[..read]);
        let (packets, used) = split_buffered(&pending);
        let mut state = state.lock().unwrap();
        for packet in packets {
            let opened = state
                .stream
                .as_ref()
                .filter(|(kind, _)| *kind == STREAM_BUFFERED)
                .map(|(_, cipher)| cipher.open_buffered(packet));
            match opened {
                Some(Some((header, data))) => {
                    state.stats.buffered_frames += 1;
                    if state.flush_until.is_none_or(|until| header.sequence >= until) {
                        state.queue.push(Frame { sequence: header.sequence, timestamp: header.timestamp, data });
                    }
                }
                Some(None) => state.stats.rejected += 1,
                None => {}
            }
        }
        drop(state);
        pending.drain(..used);
    }
}

/// Proposes the default volume to the next session after a long idle time
/// at a high one, as Shairport Sync's `high_volume_idle_timeout_in_minutes`
/// does. The volume of a paused session stays the sender's.
async fn reset_high_volume(receiver: Arc<Receiver>, state: Shared) {
    let started = Instant::now();
    loop {
        tokio::time::sleep(Duration::from_secs(60)).await;
        let idle = state.lock().unwrap().active_at.unwrap_or(started).elapsed();
        if receiver.initial_volume().is_some_and(|db| db >= HIGH_VOLUME_DB) && idle >= HIGH_VOLUME_IDLE {
            receiver.set_initial_volume(Some(DEFAULT_VOLUME_DB));
            emit("volume", json!({ "initial_db": DEFAULT_VOLUME_DB, "reason": "idle_reset" }));
        }
    }
}

/// PTP event (319) and general (320) ports: the sender's clock.
fn spawn_ptp_listeners(state: Shared) {
    for port in [319u16, 320] {
        let state = state.clone();
        tokio::spawn(async move {
            let socket = match UdpSocket::bind(("0.0.0.0", port)).await {
                Ok(socket) => socket,
                Err(error) => {
                    emit("error", json!({ "reason": "ptp_port_unavailable", "port": port, "detail": error.to_string() }));
                    return;
                }
            };
            let mut buffer = [0u8; 512];
            while let Ok((read, _)) = socket.recv_from(&mut buffer).await {
                let arrival = local_ns();
                state.lock().unwrap().ptp.receive(&buffer[..read], arrival);
            }
        });
    }
}
