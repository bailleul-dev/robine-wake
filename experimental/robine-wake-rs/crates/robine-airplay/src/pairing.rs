//! Transient `pair-setup`: SRP with the fixed code `3939`, two rounds
//! (M1 -> M2, M3 -> M4). The SRP session key then encrypts the control
//! channel; no long-term pairing is stored.

use alloc::vec::Vec;

use crate::srp::{SrpServer, Verifier};
use crate::tlv::{kind, Tlv};
use crate::RandomSource;

/// Code of transient pairing.
pub const TRANSIENT_PIN: &str = "3939";
const FLAG_TRANSIENT: u8 = 0x10;
const ERROR_AUTHENTICATION: u8 = 0x02;
const ERROR_UNAVAILABLE: u8 = 0x06;

pub enum Step {
    /// Answer and wait for the next round.
    Continue(Vec<u8>),
    /// Answer in clear, then encrypt the channel with this secret.
    Done { response: Vec<u8>, secret: [u8; 64] },
    /// Error answer.
    Failed(Vec<u8>),
}

#[derive(Default)]
pub struct PairSetup {
    server: Option<SrpServer>,
    transient: bool,
}

impl PairSetup {
    pub fn handle(&mut self, verifier: &Verifier, random: RandomSource, body: &[u8]) -> Step {
        let Some(request) = Tlv::decode(body) else {
            return failed(2, ERROR_AUTHENTICATION);
        };
        match request.get_u8(kind::STATE) {
            Some(1) => self.m1(verifier, random, &request),
            Some(3) => self.m3(verifier, &request),
            // M5: persistent pairing (Home app), not supported.
            _ => failed(6, ERROR_UNAVAILABLE),
        }
    }

    fn m1(&mut self, verifier: &Verifier, random: RandomSource, request: &Tlv) -> Step {
        self.transient = request
            .get(kind::FLAGS)
            .and_then(|flags| flags.last())
            .is_some_and(|flags| flags & FLAG_TRANSIENT != 0);
        let server = SrpServer::new(verifier, random);
        let mut response = Tlv::new();
        response
            .put_u8(kind::STATE, 2)
            .put(kind::SALT, verifier.salt().to_vec())
            .put(kind::PUBLIC_KEY, server.public_key());
        self.server = Some(server);
        Step::Continue(response.encode())
    }

    fn m3(&mut self, verifier: &Verifier, request: &Tlv) -> Step {
        let (Some(server), Some(a), Some(proof)) = (
            self.server.take(),
            request.get(kind::PUBLIC_KEY),
            request.get(kind::PROOF),
        ) else {
            return failed(4, ERROR_AUTHENTICATION);
        };
        let Some((hamk, secret)) = server.verify(verifier, a, proof) else {
            return failed(4, ERROR_AUTHENTICATION);
        };
        let mut response = Tlv::new();
        response.put_u8(kind::STATE, 4).put(kind::PROOF, hamk.to_vec());
        if self.transient {
            Step::Done { response: response.encode(), secret }
        } else {
            Step::Continue(response.encode())
        }
    }
}

fn failed(state: u8, error: u8) -> Step {
    let mut tlv = Tlv::new();
    tlv.put_u8(kind::STATE, state).put_u8(kind::ERROR, error);
    Step::Failed(tlv.encode())
}
