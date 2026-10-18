//! HomeKit TLV8: `[type][length][value]` items. Values longer than 255 bytes
//! are split into consecutive items of the same type.

use alloc::vec::Vec;

/// Item types used by pairing.
pub mod kind {
    pub const METHOD: u8 = 0x00;
    pub const IDENTIFIER: u8 = 0x01;
    pub const SALT: u8 = 0x02;
    pub const PUBLIC_KEY: u8 = 0x03;
    pub const PROOF: u8 = 0x04;
    pub const ENCRYPTED_DATA: u8 = 0x05;
    pub const STATE: u8 = 0x06;
    pub const ERROR: u8 = 0x07;
    pub const SIGNATURE: u8 = 0x0A;
    pub const FLAGS: u8 = 0x13;
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Tlv(Vec<(u8, Vec<u8>)>);

impl Tlv {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn put(&mut self, kind: u8, value: impl Into<Vec<u8>>) -> &mut Self {
        self.0.push((kind, value.into()));
        self
    }

    pub fn put_u8(&mut self, kind: u8, value: u8) -> &mut Self {
        self.put(kind, alloc::vec![value])
    }

    pub fn get(&self, kind: u8) -> Option<&[u8]> {
        self.0
            .iter()
            .find(|(item, _)| *item == kind)
            .map(|(_, value)| value.as_slice())
    }

    pub fn get_u8(&self, kind: u8) -> Option<u8> {
        self.get(kind).and_then(|value| value.first().copied())
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::new();
        for (kind, value) in &self.0 {
            if value.is_empty() {
                out.extend_from_slice(&[*kind, 0]);
            }
            for chunk in value.chunks(255) {
                out.push(*kind);
                out.push(chunk.len() as u8);
                out.extend_from_slice(chunk);
            }
        }
        out
    }

    /// `None` on a truncated item.
    pub fn decode(mut bytes: &[u8]) -> Option<Self> {
        let mut items: Vec<(u8, Vec<u8>)> = Vec::new();
        while let [kind, len, rest @ ..] = bytes {
            let value = rest.get(..usize::from(*len))?;
            // A fragment continues the previous item of the same type when
            // that item ends on a full 255-byte fragment.
            match items.last_mut() {
                Some((last, data)) if last == kind && !data.is_empty() && data.len() % 255 == 0 => {
                    data.extend_from_slice(value);
                }
                _ => items.push((*kind, value.to_vec())),
            }
            bytes = &rest[usize::from(*len)..];
        }
        bytes.is_empty().then_some(Self(items))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn long_values_are_fragmented_and_reassembled() {
        let value: Vec<u8> = (0..600).map(|i| i as u8).collect();
        let mut tlv = Tlv::new();
        tlv.put_u8(kind::STATE, 2).put(kind::PUBLIC_KEY, value.clone());
        let encoded = tlv.encode();
        assert_eq!(&encoded[..5], &[kind::STATE, 1, 2, kind::PUBLIC_KEY, 255]);
        let decoded = Tlv::decode(&encoded).unwrap();
        assert_eq!(decoded.get(kind::PUBLIC_KEY), Some(value.as_slice()));
        assert_eq!(decoded.get_u8(kind::STATE), Some(2));
    }

    #[test]
    fn truncated_input_is_rejected() {
        assert!(Tlv::decode(&[kind::SALT, 5, 1, 2]).is_none());
        assert!(Tlv::decode(&[kind::SALT]).is_none());
        assert_eq!(Tlv::decode(&[]).unwrap(), Tlv::new());
    }
}
