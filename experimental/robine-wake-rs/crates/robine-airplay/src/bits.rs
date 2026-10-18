//! MSB-first bit reader shared by the ALAC and AAC decoders.

/// Read past the end of the data.
#[derive(Debug, PartialEq, Eq)]
pub struct Truncated;

pub struct BitReader<'a> {
    bytes: &'a [u8],
    position: usize,
}

impl<'a> BitReader<'a> {
    pub fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, position: 0 }
    }

    pub fn remaining(&self) -> usize {
        (self.bytes.len() * 8).saturating_sub(self.position)
    }

    /// Up to 32 bits, most significant first.
    pub fn peek(&self, count: u32) -> Result<u32, Truncated> {
        if count == 0 {
            return Ok(0);
        }
        if self.remaining() < count as usize {
            return Err(Truncated);
        }
        let mut value: u64 = 0;
        let first = self.position / 8;
        for offset in 0..5 {
            value = (value << 8) | u64::from(*self.bytes.get(first + offset).unwrap_or(&0));
        }
        let skip = (self.position % 8) as u32;
        Ok(((value << (24 + skip)) >> (64 - count)) as u32)
    }

    pub fn read(&mut self, count: u32) -> Result<u32, Truncated> {
        let value = self.peek(count)?;
        self.position += count as usize;
        Ok(value)
    }

    pub fn read_bool(&mut self) -> Result<bool, Truncated> {
        Ok(self.read(1)? == 1)
    }

    pub fn skip(&mut self, count: usize) -> Result<(), Truncated> {
        if self.remaining() < count {
            return Err(Truncated);
        }
        self.position += count;
        Ok(())
    }

    pub fn align(&mut self) {
        self.position = self.position.div_ceil(8) * 8;
    }
}
