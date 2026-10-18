//! SRP-6a, HomeKit variant used by AirPlay 2 `pair-setup`: RFC 5054 3072-bit
//! group, `g = 5`, SHA-512, username `Pair-Setup`.
//!
//! Apple specifics (checked against shairport-sync and openairplay2):
//! `k = H(PAD(N) | PAD(g))`, `u = H(PAD(A) | PAD(B))`, session key `K = H(S)`,
//! `M1 = H(H(N) xor H(g) | H(I) | s | A | B | K)`, `HAMK = H(A | M1 | K)`.

use alloc::vec;
use alloc::vec::Vec;

use num_bigint::BigUint;
use sha2::{Digest, Sha512};

use crate::RandomSource;

pub const USERNAME: &str = "Pair-Setup";
const N_LEN: usize = 384;

/// RFC 5054 3072-bit group prime.
const N_HEX: &[u8] = b"\
FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B\
139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485\
B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1F\
E649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23\
DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32\
905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF69558\
17183995497CEA956AE515D2261898FA051015728E5A8AAAC42DAD33170D04507A33A85521\
ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7ABF5AE8CDB0933D7\
1E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864D87602733EC86A64521F2B1817\
7B200CBBE117577A615D6C770988C0BAD946E208E24FA074E5AB3143DB5BFCE0FD108E4B82\
D120A93AD2CAFFFFFFFFFFFFFFFF";

struct Group {
    n: BigUint,
    g: BigUint,
}

impl Group {
    fn new() -> Self {
        Self {
            n: BigUint::parse_bytes(N_HEX, 16).expect("valid group prime"),
            g: BigUint::from(5u32),
        }
    }

    /// `k = H(PAD(N) | PAD(g))`.
    fn k(&self) -> BigUint {
        BigUint::from_bytes_be(&hash(&[&pad(&self.n), &pad(&self.g)]))
    }

    /// `M1 = H(H(N) xor H(g) | H(I) | s | A | B | K)`.
    fn m1(&self, salt: &[u8], a: &BigUint, b: &BigUint, key: &[u8]) -> [u8; 64] {
        let h_n = hash(&[&self.n.to_bytes_be()]);
        let h_g = hash(&[&self.g.to_bytes_be()]);
        let mut xor = [0u8; 64];
        for (index, byte) in xor.iter_mut().enumerate() {
            *byte = h_n[index] ^ h_g[index];
        }
        let h_i = hash(&[USERNAME.as_bytes()]);
        hash(&[&xor, &h_i, salt, &a.to_bytes_be(), &b.to_bytes_be(), key])
    }
}

fn hash(parts: &[&[u8]]) -> [u8; 64] {
    let mut hasher = Sha512::new();
    for part in parts {
        hasher.update(part);
    }
    hasher.finalize().into()
}

fn pad(number: &BigUint) -> Vec<u8> {
    let bytes = number.to_bytes_be();
    let mut out = vec![0u8; N_LEN.saturating_sub(bytes.len())];
    out.extend_from_slice(&bytes);
    out
}

/// `u = H(PAD(A) | PAD(B))`.
fn scrambler(a: &BigUint, b: &BigUint) -> BigUint {
    BigUint::from_bytes_be(&hash(&[&pad(a), &pad(b)]))
}

/// `x = H(s | H(I ":" p))`.
fn private_key(salt: &[u8], password: &str) -> BigUint {
    let inner = hash(&[USERNAME.as_bytes(), b":", password.as_bytes()]);
    BigUint::from_bytes_be(&hash(&[salt, &inner]))
}

fn random_exponent(random: RandomSource) -> BigUint {
    let mut bytes = [0u8; 32];
    random(&mut bytes);
    BigUint::from_bytes_be(&bytes)
}

fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    left.len() == right.len() && left.iter().zip(right).fold(0u8, |acc, (a, b)| acc | (a ^ b)) == 0
}

/// Salt and verifier for a password. The transient code is fixed, so a
/// receiver computes this once instead of once per connection: on a
/// microcontroller each 3072-bit exponentiation is expensive.
pub struct Verifier {
    group: Group,
    salt: [u8; 16],
    v: BigUint,
}

impl Verifier {
    pub fn new(password: &str, random: RandomSource) -> Self {
        let group = Group::new();
        let mut salt = [0u8; 16];
        random(&mut salt);
        let v = group.g.modpow(&private_key(&salt, password), &group.n);
        Self { group, salt, v }
    }
}

/// Server side of one `pair-setup` exchange.
pub struct SrpServer {
    b: BigUint,
    big_b: BigUint,
}

impl SrpServer {
    pub fn new(verifier: &Verifier, random: RandomSource) -> Self {
        let group = &verifier.group;
        let b = random_exponent(random);
        // B = k*v + g^b mod N
        let big_b = (group.k() * &verifier.v + group.g.modpow(&b, &group.n)) % &group.n;
        Self { b, big_b }
    }

    pub fn public_key(&self) -> Vec<u8> {
        self.big_b.to_bytes_be()
    }

    /// Checks the client proof `M1` for its public key `A`. Returns the
    /// server proof `HAMK` and the 64-byte session key.
    pub fn verify(&self, verifier: &Verifier, a: &[u8], m1: &[u8]) -> Option<([u8; 64], [u8; 64])> {
        let group = &verifier.group;
        let a = BigUint::from_bytes_be(a);
        if (&a % &group.n) == BigUint::from(0u32) {
            return None;
        }
        let u = scrambler(&a, &self.big_b);
        // S = (A * v^u)^b mod N
        let s = (&a * verifier.v.modpow(&u, &group.n)).modpow(&self.b, &group.n);
        let key = hash(&[&s.to_bytes_be()]);
        let expected = group.m1(&verifier.salt, &a, &self.big_b, &key);
        if !constant_time_eq(&expected, m1) {
            return None;
        }
        Some((hash(&[&a.to_bytes_be(), m1, &key]), key))
    }
}

impl Verifier {
    pub fn salt(&self) -> &[u8; 16] {
        &self.salt
    }
}

/// Client side, for tests and test senders.
pub struct SrpClient {
    group: Group,
    a: BigUint,
    big_a: BigUint,
    password: alloc::string::String,
    m1: [u8; 64],
    key: [u8; 64],
}

impl SrpClient {
    pub fn new(password: &str, random: RandomSource) -> Self {
        let group = Group::new();
        let a = random_exponent(random);
        let big_a = group.g.modpow(&a, &group.n);
        Self {
            group,
            a,
            big_a,
            password: password.into(),
            m1: [0; 64],
            key: [0; 64],
        }
    }

    pub fn public_key(&self) -> Vec<u8> {
        self.big_a.to_bytes_be()
    }

    /// Computes the proof `M1` from the server salt and `B`.
    pub fn process(&mut self, salt: &[u8], b: &[u8]) -> [u8; 64] {
        let group = &self.group;
        let b = BigUint::from_bytes_be(b);
        let x = private_key(salt, &self.password);
        let u = scrambler(&self.big_a, &b);
        // S = (B - k*g^x)^(a + u*x) mod N
        let kgx = (group.k() * group.g.modpow(&x, &group.n)) % &group.n;
        let base = (&b + &group.n - kgx) % &group.n;
        let s = base.modpow(&(&self.a + &u * &x), &group.n);
        self.key = hash(&[&s.to_bytes_be()]);
        self.m1 = group.m1(salt, &self.big_a, &b, &self.key);
        self.m1
    }

    pub fn verify_server(&self, hamk: &[u8]) -> bool {
        constant_time_eq(&hash(&[&self.big_a.to_bytes_be(), &self.m1, &self.key]), hamk)
    }

    pub fn session_key(&self) -> &[u8; 64] {
        &self.key
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub fn test_random(bytes: &mut [u8]) {
        use core::sync::atomic::{AtomicU64, Ordering};
        static STATE: AtomicU64 = AtomicU64::new(0x9E37_79B9_7F4A_7C15);
        for byte in bytes {
            // xorshift64*, enough for tests.
            let mut x = STATE.load(Ordering::Relaxed);
            x ^= x >> 12;
            x ^= x << 25;
            x ^= x >> 27;
            STATE.store(x, Ordering::Relaxed);
            *byte = (x.wrapping_mul(0x2545_F491_4F6C_DD1D) >> 56) as u8;
        }
    }

    #[test]
    fn client_and_server_agree_on_the_session_key() {
        let verifier = Verifier::new("3939", test_random);
        let server = SrpServer::new(&verifier, test_random);
        let mut client = SrpClient::new("3939", test_random);
        let m1 = client.process(verifier.salt(), &server.public_key());
        let (hamk, key) = server.verify(&verifier, &client.public_key(), &m1).unwrap();
        assert!(client.verify_server(&hamk));
        assert_eq!(&key, client.session_key());
    }

    #[test]
    fn wrong_password_is_rejected() {
        let verifier = Verifier::new("3939", test_random);
        let server = SrpServer::new(&verifier, test_random);
        let mut client = SrpClient::new("0000", test_random);
        let m1 = client.process(verifier.salt(), &server.public_key());
        assert!(server.verify(&verifier, &client.public_key(), &m1).is_none());
    }
}
