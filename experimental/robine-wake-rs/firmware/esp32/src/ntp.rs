//! Minimal SNTP client (RFC 4330) over embassy-net.

use embassy_net::dns::DnsQueryType;
use embassy_net::udp::{PacketMetadata, UdpSocket};
use embassy_net::Stack;
use embassy_time::{with_timeout, Duration};

const SERVER: &str = "pool.ntp.org";
const PORT: u16 = 123;
/// Seconds between the NTP era (1900) and the Unix epoch (1970).
const NTP_TO_UNIX_SECONDS: i64 = 2_208_988_800;

#[derive(Debug)]
pub enum Error {
    Dns,
    Socket,
    Timeout,
    InvalidReply,
}

/// Asks the pool for the current time, in Unix milliseconds.
pub async fn query(stack: Stack<'_>) -> Result<i64, Error> {
    let address = *stack
        .dns_query(SERVER, DnsQueryType::A)
        .await
        .map_err(|_| Error::Dns)?
        .first()
        .ok_or(Error::Dns)?;

    let mut rx_meta = [PacketMetadata::EMPTY; 2];
    let mut tx_meta = [PacketMetadata::EMPTY; 2];
    let mut rx_buffer = [0u8; 128];
    let mut tx_buffer = [0u8; 128];
    let mut socket = UdpSocket::new(stack, &mut rx_meta, &mut rx_buffer, &mut tx_meta, &mut tx_buffer);
    socket.bind(0).map_err(|_| Error::Socket)?;

    // LI = 0, version 4, mode 3 (client).
    let mut request = [0u8; 48];
    request[0] = 0x23;
    socket
        .send_to(&request, (address, PORT))
        .await
        .map_err(|_| Error::Socket)?;

    let mut reply = [0u8; 48];
    let (length, _) = with_timeout(Duration::from_secs(5), socket.recv_from(&mut reply))
        .await
        .map_err(|_| Error::Timeout)?
        .map_err(|_| Error::Socket)?;
    if length < 48 || reply[1] == 0 {
        // Too short, or stratum 0: a kiss-of-death packet.
        return Err(Error::InvalidReply);
    }

    let seconds = u32::from_be_bytes([reply[40], reply[41], reply[42], reply[43]]);
    let fraction = u32::from_be_bytes([reply[44], reply[45], reply[46], reply[47]]);
    let millis = (u64::from(fraction) * 1_000) >> 32;
    Ok((i64::from(seconds) - NTP_TO_UNIX_SECONDS) * 1_000 + millis as i64)
}
