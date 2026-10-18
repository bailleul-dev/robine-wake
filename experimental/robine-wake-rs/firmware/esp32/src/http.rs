//! HTTP/1.1 server: the command API, the event stream and the web app.
//!
//! One request per connection (`Connection: close`), which is what the app,
//! the remote button and browsers handle without keep-alive.

use alloc::format;
use alloc::string::String;

use embassy_net::tcp::TcpSocket;
use embassy_net::Stack;
use embassy_time::{with_timeout, Duration, Timer};
use embedded_io_async::Write;
use log::warn;

use crate::app::App;
use crate::{events, web};

/// Largest accepted request: headers plus a command body.
const REQUEST_CAPACITY: usize = 6 * 1024;
const KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(15);

struct Request<'a> {
    method: &'a str,
    path: &'a str,
    body: &'a [u8],
}

enum ReadError {
    Closed,
    TooLarge,
    Malformed,
}

/// Accepts and answers connections on `port` forever.
pub async fn serve(stack: Stack<'static>, app: &'static App, port: u16) -> ! {
    let mut rx_buffer = [0u8; 1536];
    let mut tx_buffer = [0u8; 2048];
    let mut request = [0u8; REQUEST_CAPACITY];

    loop {
        let mut socket = TcpSocket::new(stack, &mut rx_buffer, &mut tx_buffer);
        socket.set_timeout(Some(Duration::from_secs(20)));
        if socket.accept(port).await.is_err() {
            continue;
        }
        if let Err(error) = handle(&mut socket, app, &mut request).await {
            warn!("http: {error:?}");
        }
        let _ = socket.flush().await;
        socket.close();
        Timer::after(Duration::from_millis(20)).await;
        socket.abort();
    }
}

async fn handle(socket: &mut TcpSocket<'_>, app: &App, buffer: &mut [u8]) -> Result<(), embassy_net::tcp::Error> {
    let request = match read_request(socket, buffer).await {
        Ok(request) => request,
        Err(ReadError::Closed) => return Ok(()),
        Err(ReadError::TooLarge) => return respond(socket, "413 Payload Too Large", "text/plain", &[], b"").await,
        Err(ReadError::Malformed) => return respond(socket, "400 Bad Request", "text/plain", &[], b"").await,
    };
    let path = request.path.split('?').next().unwrap_or("/");

    match (request.method, path) {
        ("POST", "/api/v1/command") => {
            let response = app.command(request.body).await;
            respond(socket, "200 OK", "application/json", &[], &response).await
        }
        ("GET", "/api/v1/events") => stream_events(socket).await,
        ("GET" | "HEAD", _) => match web::find(path) {
            Some(asset) => {
                let cache = if asset.path == "/index.html" {
                    "no-cache"
                } else {
                    "public, max-age=31536000, immutable"
                };
                let headers = [("Content-Encoding", "gzip"), ("Cache-Control", cache)];
                let body = if request.method == "HEAD" { &[][..] } else { asset.gzip };
                respond(socket, "200 OK", asset.content_type, &headers, body).await
            }
            None => respond(socket, "404 Not Found", "text/plain", &[], b"not found").await,
        },
        _ => respond(socket, "405 Method Not Allowed", "text/plain", &[], b"").await,
    }
}

async fn read_request<'a>(socket: &mut TcpSocket<'_>, buffer: &'a mut [u8]) -> Result<Request<'a>, ReadError> {
    let mut filled = 0;
    let header_end = loop {
        if filled == buffer.len() {
            return Err(ReadError::TooLarge);
        }
        let read = socket.read(&mut buffer[filled..]).await.map_err(|_| ReadError::Closed)?;
        if read == 0 {
            return Err(ReadError::Closed);
        }
        filled += read;
        if let Some(index) = find(&buffer[..filled], b"\r\n\r\n") {
            break index + 4;
        }
    };

    let (method, path, content_length) = {
        let head = core::str::from_utf8(&buffer[..header_end]).map_err(|_| ReadError::Malformed)?;
        let mut lines = head.split("\r\n");
        let mut request_line = lines.next().ok_or(ReadError::Malformed)?.split(' ');
        let method = request_line.next().ok_or(ReadError::Malformed)?;
        let path = request_line.next().ok_or(ReadError::Malformed)?;
        let content_length = lines
            .filter_map(|line| line.split_once(':'))
            .find(|(name, _)| name.trim().eq_ignore_ascii_case("content-length"))
            .map(|(_, value)| value.trim().parse::<usize>().map_err(|_| ReadError::Malformed))
            .transpose()?
            .unwrap_or(0);
        // Ranges, so the buffer can be filled with the body afterwards.
        let path_start = method.len() + 1;
        (0..method.len(), path_start..path_start + path.len(), content_length)
    };

    let total = header_end + content_length;
    if total > buffer.len() {
        return Err(ReadError::TooLarge);
    }
    while filled < total {
        let read = socket.read(&mut buffer[filled..total]).await.map_err(|_| ReadError::Closed)?;
        if read == 0 {
            return Err(ReadError::Closed);
        }
        filled += read;
    }

    let buffer = &buffer[..total];
    let text = |range: core::ops::Range<usize>| core::str::from_utf8(&buffer[range]).unwrap_or("");
    Ok(Request {
        method: text(method),
        path: text(path),
        body: &buffer[header_end..],
    })
}

async fn respond(
    socket: &mut TcpSocket<'_>,
    status: &str,
    content_type: &str,
    headers: &[(&str, &str)],
    body: &[u8],
) -> Result<(), embassy_net::tcp::Error> {
    let mut head = format!(
        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n",
        body.len()
    );
    for (name, value) in headers {
        head.push_str(&format!("{name}: {value}\r\n"));
    }
    head.push_str("\r\n");
    socket.write_all(head.as_bytes()).await?;
    socket.write_all(body).await
}

/// `GET /api/v1/events`: `ready`, then one SSE frame per event, with
/// keep-alive comments in between (same frames as the Elixir router).
async fn stream_events(socket: &mut TcpSocket<'_>) -> Result<(), embassy_net::tcp::Error> {
    let Some(mut subscriber) = events::subscribe() else {
        return respond(socket, "503 Service Unavailable", "text/plain", &[], b"too many streams").await;
    };
    socket.set_timeout(Some(Duration::from_secs(60)));
    socket
        .write_all(
            b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache, no-transform\r\n\
              Connection: keep-alive\r\nTransfer-Encoding: chunked\r\n\r\n",
        )
        .await?;
    write_chunk(socket, &frame(events::sequence(), "ready")).await?;

    loop {
        let chunk = match with_timeout(KEEP_ALIVE_INTERVAL, subscriber.next_message_pure()).await {
            Ok(event) => frame(event.id, event.name),
            Err(_) => String::from(": keep-alive\n\n"),
        };
        write_chunk(socket, &chunk).await?;
    }
}

fn frame(id: u32, event: &str) -> String {
    format!(
        "id: {id}\nevent: {event}\ndata: {{\"v\":1,\"id\":{id},\"event\":\"{event}\",\"at\":null,\"data\":null}}\n\n"
    )
}

async fn write_chunk(socket: &mut TcpSocket<'_>, data: &str) -> Result<(), embassy_net::tcp::Error> {
    let chunk = format!("{:x}\r\n{data}\r\n", data.len());
    socket.write_all(chunk.as_bytes()).await?;
    socket.flush().await
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|window| window == needle)
}
