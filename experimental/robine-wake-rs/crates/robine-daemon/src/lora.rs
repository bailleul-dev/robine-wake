//! LoRa RFM95 / SX1276 remote button protocol and driver (ACC-003).
//!
//! Provides point-to-point 868.1 MHz radio reception on spidev0.0,
//! verifying HMAC-SHA256 dismiss signatures and enforcing monotonic counter anti-replay.

use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use chrono::Utc;
use serde_json::{json, Value};

use crate::events::EventStream;
use crate::session_manager::SessionManager;
use crate::store::Store;
use robine_core::session::DismissSource;

// SX1276 Radio Parameters (ACC-003.1)
#[allow(dead_code)]
pub const FREQUENCY_HZ: u32 = 868_100_000;
#[allow(dead_code)]
pub const BANDWIDTH_KHZ: u32 = 125;
#[allow(dead_code)]
pub const SPREADING_FACTOR: u8 = 9;
#[allow(dead_code)]
pub const CODING_RATE_4_5: u8 = 1;
#[allow(dead_code)]
pub const PREAMBLE_LENGTH: u16 = 8;
pub const SYNC_WORD: u8 = 0x12;
#[allow(dead_code)]
pub const TX_POWER_DBM: i8 = 14;

// SX1276 Register map
pub const REG_FIFO: u8 = 0x00;
pub const REG_OP_MODE: u8 = 0x01;
pub const REG_FR_MSB: u8 = 0x06;
pub const REG_FR_MID: u8 = 0x07;
pub const REG_FR_LSB: u8 = 0x08;
pub const REG_PA_CONFIG: u8 = 0x09;
pub const REG_FIFO_ADDR_PTR: u8 = 0x0D;
#[allow(dead_code)]
pub const REG_FIFO_TX_BASE_ADDR: u8 = 0x0E;
pub const REG_FIFO_RX_BASE_ADDR: u8 = 0x0F;
pub const REG_FIFO_RX_CURRENT_ADDR: u8 = 0x10;
pub const REG_IRQ_FLAGS: u8 = 0x12;
pub const REG_RX_NB_BYTES: u8 = 0x13;
pub const REG_MODEM_CONFIG_1: u8 = 0x1D;
pub const REG_MODEM_CONFIG_2: u8 = 0x1E;
pub const REG_PREAMBLE_MSB: u8 = 0x20;
pub const REG_PREAMBLE_LSB: u8 = 0x21;
#[allow(dead_code)]
pub const REG_PAYLOAD_LENGTH: u8 = 0x22;
pub const REG_MODEM_CONFIG_3: u8 = 0x26;
pub const REG_SYNC_WORD: u8 = 0x39;
pub const REG_VERSION: u8 = 0x42;

pub const EXPECTED_VERSION: u8 = 0x12;

// OpMode flags
pub const MODE_LONG_RANGE_MODE: u8 = 0x80;
pub const MODE_SLEEP: u8 = 0x00;
pub const MODE_STDBY: u8 = 0x01;
pub const MODE_RX_CONTINUOUS: u8 = 0x05;

// Irq flags
pub const IRQ_RX_DONE_MASK: u8 = 0x40;
pub const IRQ_PAYLOAD_CRC_ERROR_MASK: u8 = 0x20;

pub trait SpiBus: Send {
    fn transfer(&mut self, write: &[u8], read: &mut [u8]) -> std::io::Result<()>;
}

pub fn read_reg(bus: &mut dyn SpiBus, reg: u8) -> std::io::Result<u8> {
    let tx = [reg & 0x7F, 0x00];
    let mut rx = [0u8; 2];
    bus.transfer(&tx, &mut rx)?;
    Ok(rx[1])
}

pub fn write_reg(bus: &mut dyn SpiBus, reg: u8, val: u8) -> std::io::Result<()> {
    let tx = [reg | 0x80, val];
    let mut rx = [0u8; 2];
    bus.transfer(&tx, &mut rx)
}

pub fn read_fifo(bus: &mut dyn SpiBus, len: usize) -> std::io::Result<Vec<u8>> {
    let mut tx = vec![0u8; len + 1];
    tx[0] = REG_FIFO & 0x7F;
    let mut rx = vec![0u8; len + 1];
    bus.transfer(&tx, &mut rx)?;
    Ok(rx[1..].to_vec())
}

/// Configure SX1276 with contract parameters (ACC-003.1).
pub fn configure_sx1276(bus: &mut dyn SpiBus) -> std::io::Result<()> {
    // 1. Sleep mode to switch to LoRa mode
    write_reg(bus, REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_SLEEP)?;
    // 2. Standby
    write_reg(bus, REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_STDBY)?;

    // 3. Frequency 868.1 MHz: 0xD90666
    write_reg(bus, REG_FR_MSB, 0xD9)?;
    write_reg(bus, REG_FR_MID, 0x06)?;
    write_reg(bus, REG_FR_LSB, 0x66)?;

    // 4. PA config: PA_BOOST on, 14 dBm -> 0x8D
    write_reg(bus, REG_PA_CONFIG, 0x8D)?;

    // 5. Modem Config 1: BW 125 kHz (0x70) | CR 4/5 (0x02) | Explicit Header (0x00) = 0x72
    write_reg(bus, REG_MODEM_CONFIG_1, 0x72)?;

    // 6. Modem Config 2: SF9 (0x90) | RxPayloadCrcOn (0x04) = 0x94
    write_reg(bus, REG_MODEM_CONFIG_2, 0x94)?;

    // 7. Modem Config 3: AgcAutoOn (0x04) = 0x04
    write_reg(bus, REG_MODEM_CONFIG_3, 0x04)?;

    // 8. Preamble: 8
    write_reg(bus, REG_PREAMBLE_MSB, 0x00)?;
    write_reg(bus, REG_PREAMBLE_LSB, 0x08)?;

    // 9. Sync word: 0x12
    write_reg(bus, REG_SYNC_WORD, SYNC_WORD)?;

    // 10. Continuous RX
    write_reg(bus, REG_FIFO_RX_BASE_ADDR, 0x00)?;
    write_reg(bus, REG_FIFO_ADDR_PTR, 0x00)?;
    write_reg(bus, REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_RX_CONTINUOUS)?;

    Ok(())
}

#[cfg(target_os = "linux")]
#[repr(C)]
struct SpiIocTransfer {
    tx_buf: u64,
    rx_buf: u64,
    len: u32,
    speed_hz: u32,
    delay_usecs: u16,
    bits_per_word: u8,
    cs_change: u8,
    tx_nbits: u8,
    rx_nbits: u8,
    pad: u16,
}

#[cfg(target_os = "linux")]
pub struct SpidevBus {
    file: std::fs::File,
}

#[cfg(target_os = "linux")]
impl SpidevBus {
    pub fn open(path: impl AsRef<Path>) -> std::io::Result<Self> {
        let file = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(path)?;
        Ok(Self { file })
    }
}

#[cfg(target_os = "linux")]
impl SpiBus for SpidevBus {
    fn transfer(&mut self, write: &[u8], read: &mut [u8]) -> std::io::Result<()> {
        use std::os::unix::io::AsRawFd;
        let len = write.len().min(read.len()) as u32;
        let mut msg = SpiIocTransfer {
            tx_buf: write.as_ptr() as u64,
            rx_buf: read.as_mut_ptr() as u64,
            len,
            speed_hz: 500_000,
            delay_usecs: 0,
            bits_per_word: 8,
            cs_change: 0,
            tx_nbits: 0,
            rx_nbits: 0,
            pad: 0,
        };
        let res = unsafe { libc::ioctl(self.file.as_raw_fd(), 0x4020_6b00i32 as _, &mut msg) };
        if res < 0 {
            Err(std::io::Error::last_os_error())
        } else {
            Ok(())
        }
    }
}

type ResponseCache = Arc<Mutex<HashMap<(String, u64), (Instant, Value)>>>;

#[derive(Clone)]
pub struct LoraService {
    store: Arc<Store>,
    sessions: Arc<SessionManager>,
    events: EventStream,
    is_available: Arc<AtomicBool>,
    cache: ResponseCache,
}

impl LoraService {
    pub fn new(store: Arc<Store>, sessions: Arc<SessionManager>, events: EventStream) -> Self {
        Self {
            store,
            sessions,
            events,
            is_available: Arc::new(AtomicBool::new(false)),
            cache: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn is_available(&self) -> bool {
        self.is_available.load(Ordering::SeqCst)
    }

    /// Process a LoRa payload (max 255 bytes, JSON format, ACC-003).
    pub async fn process_payload(&self, payload: &[u8]) -> Option<Value> {
        if payload.len() > 255 {
            return None;
        }

        let msg: Value = serde_json::from_slice(payload).ok()?;
        let op = msg.get("op").and_then(Value::as_str)?;

        match op {
            "dismiss" => {
                let button_id = msg.get("button_id").and_then(Value::as_str)?;
                let counter = msg.get("counter").and_then(Value::as_u64)?;
                let signature = msg.get("signature").and_then(Value::as_str)?;

                // Consult response cache (ACC-003: 32 last responses for 5 min)
                let now = Instant::now();
                let cache_key = (button_id.to_string(), counter);
                {
                    let cache_lock = self.cache.lock().unwrap();
                    if let Some((inserted, cached_resp)) = cache_lock.get(&cache_key) {
                        if now.duration_since(*inserted) < Duration::from_secs(300) {
                            return Some(cached_resp.clone());
                        }
                    }
                }

                let mut button = self.store.get_button(button_id)?;

                match button.verify_and_advance(counter, signature) {
                    Ok(robine_core::remote_button::ButtonResult::DismissAccepted) => {
                        // Persist advanced counter before dismissing session (ACC-002.3, ACC-003.3)
                        self.store.save_button(&button).ok()?;

                        let utc_now = Utc::now();
                        let session = self
                            .sessions
                            .dismiss(DismissSource::RemoteButton, utc_now)
                            .await
                            .ok();

                        self.events.publish(
                            "button.dismissed",
                            Some(json!({
                                "button_id": button_id,
                                "source": "lora",
                                "counter": counter
                            })),
                        );

                        let resp = json!({
                            "status": "ok",
                            "op": "dismiss",
                            "dismissed": true,
                            "session": session
                        });

                        self.record_cache(cache_key, resp.clone(), now);
                        Some(resp)
                    }
                    Ok(robine_core::remote_button::ButtonResult::DuplicateAcknowledged) => {
                        let resp = json!({
                            "status": "ok",
                            "op": "dismiss",
                            "duplicate": true
                        });
                        self.record_cache(cache_key, resp.clone(), now);
                        Some(resp)
                    }
                    Err(e) => {
                        eprintln!("lora: button verification failed: {e}");
                        None
                    }
                }
            }
            "pair" => {
                let button_id = msg.get("button_id").and_then(Value::as_str)?;
                let secret_hex = msg.get("secret").and_then(Value::as_str)?;
                let secret = hex::decode(secret_hex).ok()?;
                let button =
                    robine_core::remote_button::PairedButton::new(button_id, secret, 0);
                self.store.save_button(&button).ok()?;
                Some(json!({ "status": "ok", "op": "pair", "button_id": button_id }))
            }
            _ => None,
        }
    }

    fn record_cache(&self, key: (String, u64), value: Value, now: Instant) {
        let mut cache_lock = self.cache.lock().unwrap();
        // Prune entries older than 5 min or if cache exceeds 32 items
        cache_lock.retain(|_, (inserted, _)| now.duration_since(*inserted) < Duration::from_secs(300));
        if cache_lock.len() >= 32 {
            if let Some(oldest_key) = cache_lock
                .iter()
                .min_by_key(|(_, (t, _))| *t)
                .map(|(k, _)| k.clone())
            {
                cache_lock.remove(&oldest_key);
            }
        }
        cache_lock.insert(key, (now, value));
    }

    /// Background worker monitoring SX1276 radio flags (ACC-003).
    pub fn start(self: Arc<Self>) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move {
            let spidev_path = std::env::var("ROBINE_RS_SPIDEV")
                .unwrap_or_else(|_| "/dev/spidev0.0".to_string());

            loop {
                #[cfg(target_os = "linux")]
                {
                    if let Ok(mut bus) = SpidevBus::open(&spidev_path) {
                        if let Ok(ver) = read_reg(&mut bus, REG_VERSION) {
                            if ver == EXPECTED_VERSION {
                                self.is_available.store(true, Ordering::SeqCst);
                                let _ = configure_sx1276(&mut bus);

                                // Polling loop every 25ms (ACC-003)
                                loop {
                                    tokio::time::sleep(Duration::from_millis(25)).await;

                                    if let Ok(flags) = read_reg(&mut bus, REG_IRQ_FLAGS) {
                                        if flags & IRQ_RX_DONE_MASK != 0 {
                                            let crc_ok = flags & IRQ_PAYLOAD_CRC_ERROR_MASK == 0;
                                            let nb_bytes = read_reg(&mut bus, REG_RX_NB_BYTES)
                                                .unwrap_or(0) as usize;
                                            let cur_addr =
                                                read_reg(&mut bus, REG_FIFO_RX_CURRENT_ADDR)
                                                    .unwrap_or(0);
                                            let _ = write_reg(&mut bus, REG_FIFO_ADDR_PTR, cur_addr);

                                            if crc_ok && nb_bytes > 0 && nb_bytes <= 255 {
                                                if let Ok(bytes) = read_fifo(&mut bus, nb_bytes) {
                                                    self.process_payload(&bytes).await;
                                                }
                                            }
                                            // Clear IRQ flags
                                            let _ = write_reg(&mut bus, REG_IRQ_FLAGS, 0xFF);
                                        }
                                    } else {
                                        break; // SPI error, restart outer connection
                                    }
                                }
                            }
                        }
                    }
                }

                // If device absent or error, mark unavailable and retry in 5s (ACC-003.2)
                self.is_available.store(false, Ordering::SeqCst);
                tokio::time::sleep(Duration::from_secs(5)).await;
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audio::AudioSink;
    use robine_core::remote_button::compute_dismiss_hmac;

    struct MockSpi {
        registers: HashMap<u8, u8>,
        fifo: Vec<u8>,
    }

    impl MockSpi {
        fn new() -> Self {
            let mut registers = HashMap::new();
            registers.insert(REG_VERSION, EXPECTED_VERSION);
            Self {
                registers,
                fifo: Vec::new(),
            }
        }
    }

    impl SpiBus for MockSpi {
        fn transfer(&mut self, write: &[u8], read: &mut [u8]) -> std::io::Result<()> {
            if write.is_empty() {
                return Ok(());
            }
            let reg = write[0] & 0x7F;
            let is_write = (write[0] & 0x80) != 0;

            if is_write {
                if write.len() > 1 {
                    self.registers.insert(reg, write[1]);
                }
            } else if write.len() > 1 {
                if reg == REG_FIFO {
                    for (i, b) in self.fifo.iter().enumerate() {
                        if i + 1 < read.len() {
                            read[i + 1] = *b;
                        }
                    }
                } else {
                    read[1] = *self.registers.get(&reg).unwrap_or(&0);
                }
            }
            Ok(())
        }
    }

    #[test]
    fn sx1276_configuration_writes_contract_registers() {
        let mut mock = MockSpi::new();
        assert_eq!(read_reg(&mut mock, REG_VERSION).unwrap(), EXPECTED_VERSION);

        configure_sx1276(&mut mock).unwrap();

        // 868.1 MHz: 0xD90666
        assert_eq!(*mock.registers.get(&REG_FR_MSB).unwrap(), 0xD9);
        assert_eq!(*mock.registers.get(&REG_FR_MID).unwrap(), 0x06);
        assert_eq!(*mock.registers.get(&REG_FR_LSB).unwrap(), 0x66);

        // BW 125, CR 4/5, Explicit -> 0x72
        assert_eq!(*mock.registers.get(&REG_MODEM_CONFIG_1).unwrap(), 0x72);

        // SF9, CRC on -> 0x94
        assert_eq!(*mock.registers.get(&REG_MODEM_CONFIG_2).unwrap(), 0x94);

        // Sync word 0x12
        assert_eq!(*mock.registers.get(&REG_SYNC_WORD).unwrap(), SYNC_WORD);
    }

    #[tokio::test]
    async fn processes_signed_lora_dismiss_packet() {
        let temp = std::env::temp_dir().join(format!("lora-test-{}", uuid::Uuid::new_v4()));
        let store = Arc::new(Store::open(temp.join("db.json"), |_| true));
        let audio = Arc::new(AudioSink::new());
        let events = EventStream::new();
        let sessions = Arc::new(SessionManager::new(audio, store.clone(), events.clone()));
        let service = LoraService::new(store.clone(), sessions.clone(), events);

        // 1. Pair button
        let secret = vec![0x42u8; 32];
        let button_id = "button-001122334455";
        let pair_msg = json!({
            "op": "pair",
            "button_id": button_id,
            "secret": hex::encode(&secret),
        });
        let pair_resp = service.process_payload(&serde_json::to_vec(&pair_msg).unwrap()).await;
        assert!(pair_resp.is_some());
        assert_eq!(pair_resp.unwrap()["status"], "ok");

        // 2. Send signed dismiss with counter 7 (ACC-002 test vector)
        let signature = compute_dismiss_hmac(&secret, button_id, 7).unwrap();
        let dismiss_msg = json!({
            "op": "dismiss",
            "button_id": button_id,
            "counter": 7,
            "signature": signature,
        });

        let resp1 = service
            .process_payload(&serde_json::to_vec(&dismiss_msg).unwrap())
            .await
            .unwrap();
        assert_eq!(resp1["status"], "ok");
        assert_eq!(resp1["dismissed"], true);

        // 3. Counter updated in store
        let saved_btn = store.get_button(button_id).unwrap();
        assert_eq!(saved_btn.last_counter, 7);

        // 4. Replay of same packet -> cached duplicate
        let resp2 = service
            .process_payload(&serde_json::to_vec(&dismiss_msg).unwrap())
            .await
            .unwrap();
        assert_eq!(resp2["status"], "ok");

        // 5. Counter replay (counter 6 < 7) -> rejected (returns None)
        let sig6 = compute_dismiss_hmac(&secret, button_id, 6).unwrap();
        let replay_msg = json!({
            "op": "dismiss",
            "button_id": button_id,
            "counter": 6,
            "signature": sig6,
        });
        let replay_resp = service
            .process_payload(&serde_json::to_vec(&replay_msg).unwrap())
            .await;
        assert!(replay_resp.is_none());
    }
}
