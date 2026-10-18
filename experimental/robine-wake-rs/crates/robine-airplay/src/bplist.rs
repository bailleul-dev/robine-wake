//! Apple binary property lists (`bplist00`), the body format of `/info`,
//! `SETUP` and the other AirPlay 2 control requests.
//!
//! Supports the types AirPlay uses: booleans, integers, reals, strings,
//! data, arrays and dictionaries (dates and UIDs are rejected).

use alloc::string::String;
use alloc::vec::Vec;

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Bool(bool),
    /// Unsigned integers above `i64::MAX` are stored as their bit pattern.
    Integer(i64),
    Real(f64),
    String(String),
    Data(Vec<u8>),
    Array(Vec<Value>),
    /// Ordered key/value pairs.
    Dict(Vec<(String, Value)>),
}

impl Value {
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Dict(entries) => entries.iter().find(|(name, _)| name == key).map(|(_, value)| value),
            _ => None,
        }
    }

    pub fn as_integer(&self) -> Option<i64> {
        match self {
            Value::Integer(value) => Some(*value),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::String(value) => Some(value),
            _ => None,
        }
    }

    pub fn as_data(&self) -> Option<&[u8]> {
        match self {
            Value::Data(value) => Some(value),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[Value]> {
        match self {
            Value::Array(value) => Some(value),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(value) => Some(*value),
            _ => None,
        }
    }
}

/// Builds a dictionary from `(key, value)` pairs.
pub fn dict<const N: usize>(entries: [(&str, Value); N]) -> Value {
    Value::Dict(entries.into_iter().map(|(key, value)| (key.into(), value)).collect())
}

// ----- Writing ---------------------------------------------------------------

pub fn to_bytes(value: &Value) -> Vec<u8> {
    // Values in depth-first pre-order, so the children of the container at
    // index `i` start at `i + 1`, each taking `subtree_len` indices. The
    // dictionary keys follow all values, in the order dictionaries are met.
    let mut objects: Vec<&Value> = Vec::new();
    let mut keys: Vec<&str> = Vec::new();
    flatten(value, &mut objects, &mut keys);
    let count = objects.len() + keys.len();
    let ref_size: usize = if count <= 0xFF { 1 } else { 2 };

    let mut out = Vec::from(&b"bplist00"[..]);
    let mut offsets = Vec::with_capacity(count);
    let mut next_key = objects.len();
    for (index, object) in objects.iter().enumerate() {
        offsets.push(out.len());
        write_object(object, index, &mut next_key, ref_size, &mut out);
    }
    for key in &keys {
        offsets.push(out.len());
        write_string(key, &mut out);
    }

    let table_offset = out.len();
    let offset_size = byte_width(table_offset as u64);
    for offset in &offsets {
        out.extend_from_slice(&(*offset as u64).to_be_bytes()[8 - offset_size..]);
    }
    out.extend_from_slice(&[0; 6]);
    out.push(offset_size as u8);
    out.push(ref_size as u8);
    out.extend_from_slice(&(count as u64).to_be_bytes());
    out.extend_from_slice(&0u64.to_be_bytes());
    out.extend_from_slice(&(table_offset as u64).to_be_bytes());
    out
}

fn flatten<'a>(value: &'a Value, objects: &mut Vec<&'a Value>, keys: &mut Vec<&'a str>) {
    objects.push(value);
    match value {
        Value::Array(items) => items.iter().for_each(|item| flatten(item, objects, keys)),
        Value::Dict(entries) => {
            keys.extend(entries.iter().map(|(key, _)| key.as_str()));
            entries.iter().for_each(|(_, item)| flatten(item, objects, keys));
        }
        _ => {}
    }
}

fn subtree_len(value: &Value) -> usize {
    1 + match value {
        Value::Array(items) => items.iter().map(subtree_len).sum(),
        Value::Dict(entries) => entries.iter().map(|(_, item)| subtree_len(item)).sum(),
        _ => 0,
    }
}

fn write_children<'a>(index: usize, children: impl Iterator<Item = &'a Value>, ref_size: usize, out: &mut Vec<u8>) {
    let mut child = index + 1;
    for item in children {
        write_ref(child, ref_size, out);
        child += subtree_len(item);
    }
}

fn write_object(value: &Value, index: usize, next_key: &mut usize, ref_size: usize, out: &mut Vec<u8>) {
    match value {
        Value::Bool(false) => out.push(0x08),
        Value::Bool(true) => out.push(0x09),
        Value::Integer(number) => write_integer(*number, out),
        Value::Real(number) => {
            out.push(0x23);
            out.extend_from_slice(&number.to_bits().to_be_bytes());
        }
        Value::String(text) => write_string(text, out),
        Value::Data(bytes) => {
            write_marker(0x40, bytes.len(), out);
            out.extend_from_slice(bytes);
        }
        Value::Array(items) => {
            write_marker(0xA0, items.len(), out);
            write_children(index, items.iter(), ref_size, out);
        }
        Value::Dict(entries) => {
            write_marker(0xD0, entries.len(), out);
            for _ in entries {
                write_ref(*next_key, ref_size, out);
                *next_key += 1;
            }
            write_children(index, entries.iter().map(|(_, item)| item), ref_size, out);
        }
    }
}

fn write_integer(number: i64, out: &mut Vec<u8>) {
    let (marker, bytes): (u8, usize) = match number {
        0..=0xFF => (0x10, 1),
        0x100..=0xFFFF => (0x11, 2),
        0x1_0000..=0xFFFF_FFFF => (0x12, 4),
        // Negative numbers and large values use 8 bytes.
        _ => (0x13, 8),
    };
    out.push(marker);
    out.extend_from_slice(&number.to_be_bytes()[8 - bytes..]);
}

fn write_string(text: &str, out: &mut Vec<u8>) {
    if text.is_ascii() {
        write_marker(0x50, text.len(), out);
        out.extend_from_slice(text.as_bytes());
    } else {
        let units: Vec<u16> = text.encode_utf16().collect();
        write_marker(0x60, units.len(), out);
        for unit in units {
            out.extend_from_slice(&unit.to_be_bytes());
        }
    }
}

fn write_marker(kind: u8, len: usize, out: &mut Vec<u8>) {
    if len < 0x0F {
        out.push(kind | len as u8);
    } else {
        out.push(kind | 0x0F);
        write_integer(len as i64, out);
    }
}

fn write_ref(index: usize, ref_size: usize, out: &mut Vec<u8>) {
    out.extend_from_slice(&(index as u64).to_be_bytes()[8 - ref_size..]);
}

fn byte_width(value: u64) -> usize {
    match value {
        0..=0xFF => 1,
        0x100..=0xFFFF => 2,
        0x1_0000..=0xFFFF_FFFF => 4,
        _ => 8,
    }
}

// ----- Reading ---------------------------------------------------------------

#[derive(Debug, PartialEq, Eq)]
pub struct ParseError;

pub fn from_bytes(bytes: &[u8]) -> Result<Value, ParseError> {
    if bytes.len() < 8 + 32 || &bytes[..8] != b"bplist00" {
        return Err(ParseError);
    }
    let trailer = &bytes[bytes.len() - 32..];
    let offset_size = usize::from(trailer[6]);
    let ref_size = usize::from(trailer[7]);
    let count = read_uint(&trailer[8..16]) as usize;
    let top = read_uint(&trailer[16..24]) as usize;
    let table = read_uint(&trailer[24..32]) as usize;
    if !(1..=8).contains(&offset_size) || !(1..=8).contains(&ref_size) || top >= count {
        return Err(ParseError);
    }
    let table_end = count
        .checked_mul(offset_size)
        .and_then(|len| len.checked_add(table))
        .ok_or(ParseError)?;
    if table_end > bytes.len() - 32 {
        return Err(ParseError);
    }
    let reader = Reader {
        bytes,
        offsets: &bytes[table..table_end],
        offset_size,
        ref_size,
        count,
    };
    reader.object(top, 0)
}

struct Reader<'a> {
    bytes: &'a [u8],
    offsets: &'a [u8],
    offset_size: usize,
    ref_size: usize,
    count: usize,
}

/// Nesting limit, against hostile input.
const MAX_DEPTH: usize = 32;

impl Reader<'_> {
    fn object(&self, index: usize, depth: usize) -> Result<Value, ParseError> {
        if index >= self.count || depth > MAX_DEPTH {
            return Err(ParseError);
        }
        let entry = &self.offsets[index * self.offset_size..(index + 1) * self.offset_size];
        let offset = read_uint(entry) as usize;
        let marker = *self.bytes.get(offset).ok_or(ParseError)?;
        let (kind, info) = (marker >> 4, marker & 0x0F);
        let body = offset + 1;

        match (kind, info) {
            (0x0, 0x8) => Ok(Value::Bool(false)),
            (0x0, 0x9) => Ok(Value::Bool(true)),
            (0x1, size @ 0..=3) => {
                let len = 1 << size;
                Ok(Value::Integer(read_uint(self.slice(body, len)?) as i64))
            }
            (0x2, 2) => Ok(Value::Real(f32::from_bits(read_uint(self.slice(body, 4)?) as u32) as f64)),
            (0x2, 3) => Ok(Value::Real(f64::from_bits(read_uint(self.slice(body, 8)?)))),
            (0x4, _) => {
                let (len, start) = self.length(info, body)?;
                Ok(Value::Data(self.slice(start, len)?.to_vec()))
            }
            (0x5, _) => {
                let (len, start) = self.length(info, body)?;
                let text = core::str::from_utf8(self.slice(start, len)?).map_err(|_| ParseError)?;
                Ok(Value::String(text.into()))
            }
            (0x6, _) => {
                let (len, start) = self.length(info, body)?;
                let raw = self.slice(start, len.checked_mul(2).ok_or(ParseError)?)?;
                let units = raw.chunks(2).map(|pair| u16::from_be_bytes([pair[0], pair[1]]));
                let text: Result<String, _> = char::decode_utf16(units).collect();
                Ok(Value::String(text.map_err(|_| ParseError)?))
            }
            (0xA, _) => {
                let (len, start) = self.length(info, body)?;
                let mut items = Vec::with_capacity(len.min(256));
                for position in 0..len {
                    items.push(self.object(self.reference(start, position)?, depth + 1)?);
                }
                Ok(Value::Array(items))
            }
            (0xD, _) => {
                let (len, start) = self.length(info, body)?;
                let mut entries = Vec::with_capacity(len.min(256));
                for position in 0..len {
                    let key = match self.object(self.reference(start, position)?, depth + 1)? {
                        Value::String(key) => key,
                        _ => return Err(ParseError),
                    };
                    let value = self.object(self.reference(start, len + position)?, depth + 1)?;
                    entries.push((key, value));
                }
                Ok(Value::Dict(entries))
            }
            _ => Err(ParseError),
        }
    }

    /// Length from the marker, or from the integer object that follows it.
    fn length(&self, info: u8, body: usize) -> Result<(usize, usize), ParseError> {
        if info != 0x0F {
            return Ok((usize::from(info), body));
        }
        let marker = *self.bytes.get(body).ok_or(ParseError)?;
        if marker >> 4 != 0x1 || marker & 0x0F > 3 {
            return Err(ParseError);
        }
        let size = 1usize << (marker & 0x0F);
        let len = read_uint(self.slice(body + 1, size)?) as usize;
        Ok((len, body + 1 + size))
    }

    fn reference(&self, start: usize, position: usize) -> Result<usize, ParseError> {
        let at = start + position * self.ref_size;
        Ok(read_uint(self.slice(at, self.ref_size)?) as usize)
    }

    fn slice(&self, start: usize, len: usize) -> Result<&[u8], ParseError> {
        start
            .checked_add(len)
            .and_then(|end| self.bytes.get(start..end))
            .ok_or(ParseError)
    }
}

fn read_uint(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0, |acc, byte| (acc << 8) | u64::from(*byte))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::vec;

    fn sample() -> Value {
        dict([
            ("name", Value::String("Robine Wake".into())),
            ("features", Value::Integer(0x0001_8340_405F_CA00)),
            ("small", Value::Integer(7)),
            ("negative", Value::Integer(-3)),
            ("ready", Value::Bool(true)),
            ("rate", Value::Real(1.5)),
            ("pk", Value::Data(vec![1, 2, 3])),
            ("accent", Value::String("Chambre été".into())),
            (
                "streams",
                Value::Array(vec![
                    dict([("type", Value::Integer(103)), ("shk", Value::Data(vec![9; 32]))]),
                    Value::Array(vec![Value::Bool(false), Value::Integer(1)]),
                ]),
            ),
            ("long", Value::Data(vec![0xAB; 300])),
        ])
    }

    #[test]
    fn round_trips_nested_values() {
        let value = sample();
        assert_eq!(from_bytes(&to_bytes(&value)).unwrap(), value);
    }

    #[test]
    fn many_objects_use_two_byte_references() {
        let items = (0..300).map(Value::Integer).collect();
        let value = dict([("items", Value::Array(items))]);
        let bytes = to_bytes(&value);
        assert_eq!(bytes[bytes.len() - 25], 2, "reference size");
        assert_eq!(from_bytes(&bytes).unwrap(), value);
    }

    #[test]
    fn rejects_garbage_and_truncation() {
        assert_eq!(from_bytes(b"bplist00"), Err(ParseError));
        let mut bytes = to_bytes(&sample());
        bytes.truncate(bytes.len() - 40);
        assert!(from_bytes(&bytes).is_err());
    }
}
