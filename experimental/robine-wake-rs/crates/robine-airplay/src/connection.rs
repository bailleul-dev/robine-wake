//! One control connection from a sender, driven by the bytes it sends.

use alloc::string::String;
use alloc::vec::Vec;
use core::sync::atomic::{AtomicU32, Ordering};

use crate::cipher::{self, Opener, Sealer};
use crate::info;
use crate::pairing::{PairSetup, Step, TRANSIENT_PIN};
use crate::rtsp::{ParseError, Request, Response};
use crate::session::{Ports, Session, Stream};
use crate::srp::Verifier;
use crate::{Config, Identity, RandomSource};

const PLIST: &str = "application/x-apple-binary-plist";
const OCTETS: &str = "application/octet-stream";

/// What happened on the connection, for logs and the platform.
#[derive(Debug, PartialEq)]
pub enum Event {
    Request {
        method: String,
        target: String,
        encrypted: bool,
        status: u16,
    },
    /// Transient pairing succeeded; the channel is now encrypted.
    Paired,
    PairingFailed,
    /// Decoded plist body of a session request, for logs (no keys).
    Body { method: String, summary: String },
    /// `SETUP` phase 2: audio will arrive on the data port.
    Stream(Stream),
    /// Volume in dB (0 = maximum, -144 = muted).
    Volume { db: f32 },
    /// Play (`rate` 1) or pause (0). With an anchor, RTP sample
    /// `anchor.rtp_time` plays at `anchor.network_ns` on the PTP clock
    /// `timeline`.
    RateAnchor {
        rate: i64,
        anchor: Option<crate::ptp::Anchor>,
        timeline: Option<u64>,
    },
    /// Drop buffered audio up to this sequence number (seek, skip).
    Flush { until_seq: Option<i64> },
    Teardown,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Error {
    /// Not an HTTP/RTSP request.
    Malformed,
    TooLarge,
    /// An encrypted block failed authentication.
    Authentication,
}

/// Receiver-wide state shared by all connections.
pub struct Receiver {
    pub config: Config,
    /// Where the platform listens for session channels.
    pub ports: Ports,
    pub identity: Identity,
    random: RandomSource,
    verifier: Verifier,
    /// Volume proposed to senders in `GET /info` (f32 bits, NaN for none).
    initial_volume: AtomicU32,
}

impl Receiver {
    /// Computes the pairing verifier: slow on a microcontroller, done once.
    pub fn new(config: Config, identity: Identity, random: RandomSource) -> Self {
        let verifier = Verifier::new(TRANSIENT_PIN, random);
        let initial_volume = AtomicU32::new(f32::NAN.to_bits());
        Self { config, ports: Ports::default(), identity, random, verifier, initial_volume }
    }

    /// Volume in dB a sender starts a session at (`initialVolume`), or none
    /// to let it choose. Settable while connections run.
    pub fn set_initial_volume(&self, db: Option<f32>) {
        self.initial_volume.store(db.unwrap_or(f32::NAN).to_bits(), Ordering::Relaxed);
    }

    pub fn initial_volume(&self) -> Option<f32> {
        Some(f32::from_bits(self.initial_volume.load(Ordering::Relaxed))).filter(|db| !db.is_nan())
    }

    /// TXT records to publish on `_airplay._tcp`.
    pub fn txt_records(&self) -> Vec<(&'static str, String)> {
        info::txt_records(&self.config, &self.identity)
    }
}

pub struct Connection {
    /// Bytes as received (ciphertext once encrypted).
    received: Vec<u8>,
    /// Decrypted bytes waiting to form a request.
    plain: Vec<u8>,
    channel: Option<(Sealer, Opener)>,
    pairing: PairSetup,
    session: Session,
    max_body: usize,
    /// Bytes of an oversized body still to drop.
    skipping: usize,
}

/// Bytes to send back and what happened.
#[derive(Debug, Default, PartialEq)]
pub struct Output {
    pub reply: Vec<u8>,
    pub events: Vec<Event>,
}

impl Connection {
    /// `local_ip`: address the sender reached us on, announced as our
    /// timing peer.
    pub fn new(local_ip: [u8; 4]) -> Self {
        Self {
            received: Vec::new(),
            plain: Vec::new(),
            channel: None,
            pairing: PairSetup::default(),
            session: Session::new(local_ip),
            max_body: crate::rtsp::MAX_BODY,
            skipping: 0,
        }
    }

    /// Limits the request bodies kept in memory; larger ones (cover art) are
    /// skipped while their request is still answered.
    pub fn with_max_body(mut self, max_body: usize) -> Self {
        self.max_body = max_body;
        self
    }

    pub fn is_encrypted(&self) -> bool {
        self.channel.is_some()
    }

    /// Processes bytes read from the socket.
    pub fn feed(&mut self, receiver: &Receiver, input: &[u8]) -> Result<Output, Error> {
        self.received.extend_from_slice(input);
        let mut output = Output::default();
        loop {
            self.decrypt()?;
            let skipped = self.skipping.min(self.plain.len());
            self.plain.drain(..skipped);
            self.skipping -= skipped;
            if self.skipping > 0 {
                return Ok(output);
            }
            let request = match Request::parse(&mut self.plain, self.max_body) {
                Ok(Some((request, remaining))) => {
                    self.skipping = remaining;
                    request
                }
                Ok(None) => return Ok(output),
                Err(ParseError::Malformed) => return Err(Error::Malformed),
                Err(ParseError::TooLarge) => return Err(Error::TooLarge),
            };
            let encrypted = self.is_encrypted();
            let (response, secret) = self.dispatch(receiver, &request, &mut output.events);
            output.events.push(Event::Request {
                method: request.method.clone(),
                target: request.target.clone(),
                encrypted,
                status: response.code(),
            });
            let bytes = response.encode(&request);
            match self.channel.as_mut() {
                Some((sealer, _)) => output.reply.extend(sealer.seal(&bytes)),
                None => output.reply.extend(bytes),
            }
            if let Some(secret) = secret {
                // The pairing answer went out in clear; whatever the sender
                // sent after it is already encrypted.
                self.channel = Some(cipher::receiver(&secret));
                let pending = core::mem::take(&mut self.plain);
                self.received.splice(..0, pending);
                output.events.push(Event::Paired);
            }
        }
    }

    fn decrypt(&mut self) -> Result<(), Error> {
        match self.channel.as_mut() {
            Some((_, opener)) => {
                let used = opener.open(&self.received, &mut self.plain).ok_or(Error::Authentication)?;
                self.received.drain(..used);
            }
            None => self.plain.append(&mut self.received),
        }
        Ok(())
    }

    /// The response, and the pairing secret when pairing just completed.
    fn dispatch(&mut self, receiver: &Receiver, request: &Request, events: &mut Vec<Event>) -> (Response, Option<[u8; 64]>) {
        if let Some(response) = self.session.handle(receiver.ports, receiver.config.audio_buffer_size, request, events) {
            return (response, None);
        }
        let path = request.target.split('?').next().unwrap_or("");
        match (request.method.as_str(), path) {
            ("GET", "/info") => (
                Response::ok().body(PLIST, info::info_plist(&receiver.config, &receiver.identity, receiver.initial_volume())),
                None,
            ),
            ("POST", "/pair-setup") => {
                match self.pairing.handle(&receiver.verifier, receiver.random, &request.body) {
                    Step::Continue(body) => (Response::ok().body(OCTETS, body), None),
                    Step::Done { response, secret } => (Response::ok().body(OCTETS, response), Some(secret)),
                    Step::Failed(body) => {
                        events.push(Event::PairingFailed);
                        (Response::ok().body(OCTETS, body), None)
                    }
                }
            }
            #[cfg(feature = "fairplay")]
            ("POST", "/fp-setup") => match crate::fairplay::answer(&request.body) {
                Some(body) => (Response::ok().body(OCTETS, body), None),
                None => (Response::status(400, "Bad Request"), None),
            },
            // Asked when a PIN is required; ours is the transient one.
            ("POST", "/pair-pin-start") => (Response::ok(), None),
            // Keep-alives the sender interleaves.
            ("POST", "/feedback" | "/command" | "/audioMode") => (Response::ok(), None),
            _ => (Response::status(501, "Not Implemented"), None),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bplist;
    use crate::srp::tests::test_random;
    use crate::srp::SrpClient;
    use crate::tlv::{kind, Tlv};

    fn receiver() -> Receiver {
        Receiver::new(Config::new("Robine Wake"), Identity::generate(test_random), test_random)
    }

    fn post(target: &str, cseq: u32, body: &[u8]) -> Vec<u8> {
        let mut request = alloc::format!(
            "POST {target} RTSP/1.0\r\nCSeq: {cseq}\r\nContent-Type: application/octet-stream\r\nContent-Length: {}\r\n\r\n",
            body.len()
        )
        .into_bytes();
        request.extend_from_slice(body);
        request
    }

    /// Splits a plaintext response into status line and body.
    fn split(response: &[u8]) -> (String, Vec<u8>) {
        let end = response.windows(4).position(|w| w == b"\r\n\r\n").unwrap();
        let head = core::str::from_utf8(&response[..end]).unwrap();
        (head.lines().next().unwrap().into(), response[end + 4..].to_vec())
    }

    #[test]
    fn info_describes_the_receiver() {
        let receiver = receiver();
        let mut connection = Connection::new([192, 168, 1, 2]);
        let output = connection.feed(&receiver, b"GET /info RTSP/1.0\r\nCSeq: 1\r\n\r\n").unwrap();
        let (status, body) = split(&output.reply);
        assert_eq!(status, "RTSP/1.0 200 OK");
        let info = bplist::from_bytes(&body).unwrap();
        assert_eq!(info.get("name").and_then(|v| v.as_str()), Some("Robine Wake"));
        assert_eq!(info.get("features").and_then(|v| v.as_integer()), Some(crate::DEFAULT_FEATURES as i64));
        assert_eq!(info.get("pk").and_then(|v| v.as_data()), Some(&receiver.identity.public_key()[..]));
        assert!(info.get("initialVolume").is_none());

        receiver.set_initial_volume(Some(-7.5));
        let output = connection.feed(&receiver, b"GET /info RTSP/1.0\r\nCSeq: 2\r\n\r\n").unwrap();
        let info = bplist::from_bytes(&split(&output.reply).1).unwrap();
        assert_eq!(info.get("initialVolume"), Some(&bplist::Value::Real(-7.5)));
    }

    /// The exchange an iPhone performs, then an encrypted request.
    #[test]
    fn transient_pairing_switches_the_channel_to_encryption() {
        let receiver = receiver();
        let mut connection = Connection::new([192, 168, 1, 2]);

        let mut m1 = Tlv::new();
        m1.put_u8(kind::METHOD, 0).put_u8(kind::STATE, 1).put_u8(kind::FLAGS, 0x10);
        let output = connection.feed(&receiver, &post("/pair-setup", 1, &m1.encode())).unwrap();
        let m2 = Tlv::decode(&split(&output.reply).1).unwrap();
        assert_eq!(m2.get_u8(kind::STATE), Some(2));

        let mut client = SrpClient::new(TRANSIENT_PIN, test_random);
        let proof = client.process(m2.get(kind::SALT).unwrap(), m2.get(kind::PUBLIC_KEY).unwrap());
        let mut m3 = Tlv::new();
        m3.put_u8(kind::STATE, 3)
            .put(kind::PUBLIC_KEY, client.public_key())
            .put(kind::PROOF, proof.to_vec());
        let output = connection.feed(&receiver, &post("/pair-setup", 2, &m3.encode())).unwrap();
        assert!(output.events.contains(&Event::Paired));
        let m4 = Tlv::decode(&split(&output.reply).1).unwrap();
        assert!(client.verify_server(m4.get(kind::PROOF).unwrap()));
        assert!(connection.is_encrypted());

        // The sender now encrypts with the SRP session key.
        let (mut seal, mut open) = cipher::sender(client.session_key());
        let request = seal.seal(b"POST /feedback RTSP/1.0\r\nCSeq: 3\r\n\r\n");
        // Delivered in two pieces, as TCP may.
        assert!(connection.feed(&receiver, &request[..10]).unwrap().reply.is_empty());
        let output = connection.feed(&receiver, &request[10..]).unwrap();
        let mut plain = Vec::new();
        open.open(&output.reply, &mut plain).unwrap();
        assert_eq!(split(&plain).0, "RTSP/1.0 200 OK");
    }

    #[test]
    fn wrong_proof_fails_pairing_without_encryption() {
        let receiver = receiver();
        let mut connection = Connection::new([192, 168, 1, 2]);
        let mut m1 = Tlv::new();
        m1.put_u8(kind::STATE, 1).put_u8(kind::FLAGS, 0x10);
        connection.feed(&receiver, &post("/pair-setup", 1, &m1.encode())).unwrap();
        let mut m3 = Tlv::new();
        m3.put_u8(kind::STATE, 3).put(kind::PUBLIC_KEY, alloc::vec![7; 384]).put(kind::PROOF, alloc::vec![0; 64]);
        let output = connection.feed(&receiver, &post("/pair-setup", 2, &m3.encode())).unwrap();
        assert!(output.events.contains(&Event::PairingFailed));
        assert_eq!(Tlv::decode(&split(&output.reply).1).unwrap().get_u8(kind::ERROR), Some(2));
        assert!(!connection.is_encrypted());
    }

    #[test]
    fn tampered_encrypted_bytes_close_the_connection() {
        let receiver = receiver();
        let mut connection = Connection::new([192, 168, 1, 2]);
        connection.channel = Some(cipher::receiver(&[3; 64]));
        assert_eq!(connection.feed(&receiver, &[4, 0, 1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), Err(Error::Authentication));
    }
}
