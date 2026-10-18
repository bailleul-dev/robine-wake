//! Persistent snapshot in the `robine` flash partition.
//!
//! The partition holds two slots written alternately. Each slot starts with a
//! header (magic, sequence, length, CRC-32) written after the data, so a power
//! cut during a save leaves the previous slot as the latest valid one.

use alloc::vec;
use alloc::vec::Vec;

use esp_bootloader_esp_idf::partitions::{self, PARTITION_TABLE_MAX_LEN};
use esp_storage::FlashStorage;

const LABEL: &str = "robine";
const MAGIC: [u8; 4] = *b"RWS1";
const HEADER_LEN: u32 = 16;

#[derive(Debug)]
pub enum Error {
    TooLarge,
    Flash,
}

pub struct Store {
    flash: FlashStorage<'static>,
    offset: u32,
    slot_size: u32,
    sequence: u32,
    next_slot: u32,
}

#[derive(Clone, Copy)]
struct Header {
    sequence: u32,
    len: u32,
    crc: u32,
}

impl Store {
    /// Finds the `robine` partition; `None` with another partition table.
    pub fn open(mut flash: FlashStorage<'static>) -> Option<Self> {
        let mut table = [0u8; PARTITION_TABLE_MAX_LEN];
        let partition = partitions::read_partition_table(&mut flash, &mut table)
            .ok()?
            .iter()
            .find(|entry| entry.label_as_str() == LABEL)?;
        let slot_size = partition.len() / 2 / FlashStorage::SECTOR_SIZE * FlashStorage::SECTOR_SIZE;
        let offset = partition.offset();
        Some(Self {
            flash,
            offset,
            slot_size,
            sequence: 0,
            next_slot: 0,
        })
    }

    /// Largest snapshot a slot can hold.
    pub fn capacity(&self) -> usize {
        (self.slot_size - HEADER_LEN) as usize
    }

    /// Latest valid snapshot, if any.
    pub fn load(&mut self) -> Option<Vec<u8>> {
        let mut latest: Option<(u32, Header)> = None;
        for slot in 0..2 {
            if let Some(header) = self.read_header(slot) {
                if latest.is_none_or(|(_, best)| header.sequence > best.sequence) {
                    latest = Some((slot, header));
                }
            }
        }
        let (slot, header) = latest?;
        let mut data = vec![0u8; header.len as usize];
        self.flash
            .read(self.slot_offset(slot) + HEADER_LEN, &mut data)
            .ok()?;
        if crc32(&data) != header.crc {
            return None;
        }
        self.sequence = header.sequence;
        self.next_slot = 1 - slot;
        Some(data)
    }

    pub fn save(&mut self, data: &[u8]) -> Result<(), Error> {
        if data.len() > self.capacity() {
            return Err(Error::TooLarge);
        }
        let slot = self.next_slot;
        let start = self.slot_offset(slot);
        self.flash
            .erase(start, start + self.slot_size)
            .map_err(|_| Error::Flash)?;

        // NOR writes are word aligned.
        let mut padded = data.to_vec();
        padded.resize(data.len().next_multiple_of(4), 0xFF);
        self.flash
            .write_nor(start + HEADER_LEN, &padded)
            .map_err(|_| Error::Flash)?;

        let sequence = self.sequence.wrapping_add(1);
        let mut header = [0u8; HEADER_LEN as usize];
        header[..4].copy_from_slice(&MAGIC);
        header[4..8].copy_from_slice(&sequence.to_le_bytes());
        header[8..12].copy_from_slice(&(data.len() as u32).to_le_bytes());
        header[12..16].copy_from_slice(&crc32(data).to_le_bytes());
        self.flash
            .write_nor(start, &header)
            .map_err(|_| Error::Flash)?;

        self.sequence = sequence;
        self.next_slot = 1 - slot;
        Ok(())
    }

    fn slot_offset(&self, slot: u32) -> u32 {
        self.offset + slot * self.slot_size
    }

    fn read_header(&mut self, slot: u32) -> Option<Header> {
        let mut raw = [0u8; HEADER_LEN as usize];
        self.flash.read(self.slot_offset(slot), &mut raw).ok()?;
        let word = |index: usize| u32::from_le_bytes([raw[index], raw[index + 1], raw[index + 2], raw[index + 3]]);
        let header = Header {
            sequence: word(4),
            len: word(8),
            crc: word(12),
        };
        (raw[..4] == MAGIC && header.len <= self.slot_size - HEADER_LEN).then_some(header)
    }
}

/// CRC-32 (IEEE), the checksum of the Bluetooth v1 pages.
fn crc32(bytes: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &byte in bytes {
        crc ^= u32::from(byte);
        for _ in 0..8 {
            crc = (crc >> 1) ^ (0xEDB8_8320 & 0u32.wrapping_sub(crc & 1));
        }
    }
    !crc
}
