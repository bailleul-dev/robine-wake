//! API-002 commands from the Raspberry Pi over UART: one JSON request per
//! line, one JSON response per line, through the same handler as HTTP.
//!
//! The Pi's kernel console shares this UART, so lines that are not JSON
//! objects are dropped without an answer.

use esp_hal::uart::Uart;
use esp_hal::Async;
use log::warn;

use crate::app::App;

pub const BAUDRATE: u32 = 115_200;
/// Longest request line; a longer one is dropped whole.
const MAX_LINE: usize = 1024;

#[embassy_executor::task]
pub async fn run(uart: Uart<'static, Async>, app: &'static App) {
    let (mut rx, mut tx) = uart.split();
    let mut line = [0u8; MAX_LINE];
    let mut length = 0;
    // Inside a line too long to keep: skip up to its end.
    let mut overflow = false;
    let mut chunk = [0u8; 64];

    loop {
        let read = match rx.read_async(&mut chunk).await {
            Ok(read) => read,
            Err(error) => {
                warn!("serial: {error:?}");
                (length, overflow) = (0, true);
                continue;
            }
        };
        for &byte in &chunk[..read] {
            if byte != b'\n' {
                if length < MAX_LINE {
                    line[length] = byte;
                    length += 1;
                } else {
                    overflow = true;
                }
                continue;
            }
            let request = line[..length].trim_ascii();
            if !overflow && request.first() == Some(&b'{') {
                let mut response = app.command(request).await;
                response.push(b'\n');
                // `write_async` only fills the 128-byte FIFO: loop until all
                // of the response is sent.
                let mut pending = response.as_slice();
                while !pending.is_empty() {
                    match tx.write_async(pending).await {
                        Ok(written) => pending = &pending[written..],
                        Err(error) => {
                            warn!("serial: {error:?}");
                            break;
                        }
                    }
                }
            }
            (length, overflow) = (0, false);
        }
    }
}
