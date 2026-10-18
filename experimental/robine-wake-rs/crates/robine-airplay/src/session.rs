//! Audio session verbs of the control connection: `SETUP` (timing, then
//! stream), volume, `RECORD`, play/pause anchor, flush and `TEARDOWN`.
//!
//! The core does not open sockets: the platform listens on the fixed
//! [`Ports`] announced here and handles the audio bytes itself.

use alloc::format;
use alloc::string::String;
use alloc::vec::Vec;

use crate::bplist::{self, dict, Value};
use crate::rtsp::{Request, Response};
use crate::Event;

const PLIST: &str = "application/x-apple-binary-plist";
const PARAMETERS: &str = "text/parameters";

/// Realtime stream (UDP, ALAC).
pub const STREAM_REALTIME: i64 = 96;
/// Buffered stream (TCP, usually AAC), pushed ahead of playback.
pub const STREAM_BUFFERED: i64 = 103;

/// Ports the platform listens on for a session.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Ports {
    /// TCP, events from the receiver to the sender (kept open, unused).
    pub event: u16,
    /// TCP for buffered audio, UDP for realtime audio.
    pub data: u16,
    /// UDP, retransmissions and sync packets.
    pub control: u16,
}

impl Default for Ports {
    fn default() -> Self {
        Self { event: 7001, data: 7002, control: 7003 }
    }
}

/// Stream announced by `SETUP` phase 2.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Stream {
    /// [`STREAM_REALTIME`] or [`STREAM_BUFFERED`].
    pub kind: i64,
    /// Sender's audio format bitmask (codec, rate, channels).
    pub audio_format: Option<i64>,
    /// Compression type (`ct`): 2 = ALAC, 4 = AAC-LC, 8 = AAC-ELD.
    pub compression: Option<i64>,
    pub samples_per_frame: Option<i64>,
    /// ChaCha20-Poly1305 key of the audio packets (`shk`).
    pub key: [u8; 32],
}

pub(crate) struct Session {
    local_ip: [u8; 4],
    /// dB, 0 = maximum, -144 = muted.
    volume: f32,
}

impl Session {
    pub fn new(local_ip: [u8; 4]) -> Self {
        Self { local_ip, volume: -20.0 }
    }

    /// `None` if the request is not a session verb.
    pub fn handle(&mut self, ports: Ports, buffer_size: u32, request: &Request, events: &mut Vec<Event>) -> Option<Response> {
        let response = match request.method.as_str() {
            "SETUP" => self.setup(ports, buffer_size, request, events),
            "GET_PARAMETER" => {
                let query = core::str::from_utf8(&request.body).unwrap_or("").trim();
                if query == "volume" {
                    Response::ok().body(PARAMETERS, format!("volume: {:.6}\r\n", self.volume).into_bytes())
                } else {
                    Response::ok()
                }
            }
            "SET_PARAMETER" => {
                let text = core::str::from_utf8(&request.body).unwrap_or("");
                if let Some(db) = text
                    .lines()
                    .find_map(|line| line.trim().strip_prefix("volume:"))
                    .and_then(|value| value.trim().parse::<f32>().ok())
                {
                    self.volume = db;
                    events.push(Event::Volume { db });
                }
                Response::ok()
            }
            "SETRATEANCHORTIME" => {
                if let Ok(body) = bplist::from_bytes(&request.body) {
                    let integer = |key: &str| body.get(key).and_then(Value::as_integer);
                    let anchor = match (integer("rtpTime"), integer("networkTimeSecs")) {
                        (Some(rtp_time), Some(seconds)) => Some(crate::ptp::Anchor {
                            rtp_time: rtp_time as u32,
                            // Unsigned 64-bit values are stored as their bits.
                            network_ns: crate::ptp::network_time_ns(seconds, integer("networkTimeFrac").unwrap_or(0) as u64),
                        }),
                        _ => None,
                    };
                    events.push(Event::RateAnchor {
                        rate: integer("rate").unwrap_or(0),
                        anchor,
                        timeline: integer("networkTimeTimelineID").map(|id| id as u64),
                    });
                    events.push(Event::Body { method: request.method.clone(), summary: summarize(&body) });
                }
                Response::ok()
            }
            "FLUSHBUFFERED" | "FLUSH" => {
                let until = bplist::from_bytes(&request.body)
                    .ok()
                    .and_then(|body| body.get("flushUntilSeq").and_then(Value::as_integer));
                events.push(Event::Flush { until_seq: until });
                Response::ok()
            }
            "TEARDOWN" => {
                events.push(Event::Teardown);
                Response::ok()
            }
            "RECORD" | "SETPEERS" | "SETPEERSX" => Response::ok(),
            _ => return None,
        };
        Some(response)
    }

    fn setup(&mut self, ports: Ports, buffer_size: u32, request: &Request, events: &mut Vec<Event>) -> Response {
        let Ok(body) = bplist::from_bytes(&request.body) else {
            return Response::status(400, "Bad Request");
        };
        events.push(Event::Body { method: request.method.clone(), summary: summarize(&body) });

        match body.get("streams").and_then(Value::as_array) {
            // Phase 1: event channel and timing (PTP, peer = ourselves).
            None => {
                let ip = format!("{}.{}.{}.{}", self.local_ip[0], self.local_ip[1], self.local_ip[2], self.local_ip[3]);
                let reply = dict([
                    ("eventPort", Value::Integer(i64::from(ports.event))),
                    ("timingPort", Value::Integer(0)),
                    (
                        "timingPeerInfo",
                        dict([
                            ("Addresses", Value::Array(alloc::vec![Value::String(ip.clone())])),
                            ("ID", Value::String(ip)),
                        ]),
                    ),
                ]);
                Response::ok().body(PLIST, bplist::to_bytes(&reply))
            }
            // Phase 2: the audio stream.
            Some(streams) => {
                let Some(stream) = streams.first() else {
                    return Response::status(400, "Bad Request");
                };
                let kind = stream.get("type").and_then(Value::as_integer).unwrap_or(STREAM_REALTIME);
                let key = stream.get("shk").and_then(Value::as_data).and_then(|key| <[u8; 32]>::try_from(key).ok());
                let Some(key) = key else {
                    return Response::status(400, "Bad Request");
                };
                events.push(Event::Stream(Stream {
                    kind,
                    audio_format: stream.get("audioFormat").and_then(Value::as_integer),
                    compression: stream.get("ct").and_then(Value::as_integer),
                    samples_per_frame: stream.get("spf").and_then(Value::as_integer),
                    key,
                }));

                let mut reply: Vec<(String, Value)> = alloc::vec![
                    ("type".into(), Value::Integer(kind)),
                    ("dataPort".into(), Value::Integer(i64::from(ports.data))),
                    ("controlPort".into(), Value::Integer(i64::from(ports.control))),
                ];
                if kind == STREAM_BUFFERED {
                    reply.push(("audioBufferSize".into(), Value::Integer(i64::from(buffer_size))));
                }
                let reply = dict([("streams", Value::Array(alloc::vec![Value::Dict(reply)]))]);
                Response::ok().body(PLIST, bplist::to_bytes(&reply))
            }
        }
    }
}

/// Compact one-line rendering for logs; data shows its length only, so keys
/// never reach a log.
pub fn summarize(value: &Value) -> String {
    match value {
        Value::Bool(flag) => format!("{flag}"),
        Value::Integer(number) => format!("{number}"),
        Value::Real(number) => format!("{number}"),
        Value::String(text) => format!("{text:?}"),
        Value::Data(bytes) => format!("<{} bytes>", bytes.len()),
        Value::Array(items) => {
            let items: Vec<String> = items.iter().map(summarize).collect();
            format!("[{}]", items.join(", "))
        }
        Value::Dict(entries) => {
            let entries: Vec<String> = entries.iter().map(|(key, item)| format!("{key}: {}", summarize(item))).collect();
            format!("{{{}}}", entries.join(", "))
        }
    }
}
