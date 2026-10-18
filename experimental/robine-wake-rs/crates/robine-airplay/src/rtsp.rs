//! Requests and responses of the control connection: HTTP/1.1 and RTSP/1.0
//! on one socket; the response echoes the request's protocol token.

use alloc::format;
use alloc::string::String;
use alloc::vec::Vec;

/// Bodies above this size are refused (largest expected: artwork).
pub const MAX_BODY: usize = 512 * 1024;
const MAX_HEAD: usize = 8 * 1024;
pub const SERVER: &str = "AirTunes/366.0";

#[derive(Debug, PartialEq, Eq)]
pub struct Request {
    pub method: String,
    pub target: String,
    pub protocol: String,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum ParseError {
    Malformed,
    TooLarge,
}

impl Request {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(key, _)| key.eq_ignore_ascii_case(name))
            .map(|(_, value)| value.as_str())
    }

    /// Takes one complete request off the front of `buffer`, if present.
    pub fn parse(buffer: &mut Vec<u8>) -> Result<Option<Self>, ParseError> {
        let Some(head_len) = buffer.windows(4).position(|window| window == b"\r\n\r\n") else {
            return if buffer.len() > MAX_HEAD { Err(ParseError::TooLarge) } else { Ok(None) };
        };
        let head = core::str::from_utf8(&buffer[..head_len]).map_err(|_| ParseError::Malformed)?;
        let mut lines = head.split("\r\n");
        let mut request_line = lines.next().unwrap_or("").splitn(3, ' ');
        let (Some(method), Some(target), Some(protocol)) =
            (request_line.next(), request_line.next(), request_line.next())
        else {
            return Err(ParseError::Malformed);
        };
        if method.is_empty() || !(protocol.starts_with("HTTP/") || protocol.starts_with("RTSP/")) {
            return Err(ParseError::Malformed);
        }
        let mut headers = Vec::new();
        for line in lines.filter(|line| !line.is_empty()) {
            let (name, value) = line.split_once(':').ok_or(ParseError::Malformed)?;
            headers.push((String::from(name.trim()), String::from(value.trim())));
        }

        let mut request = Request {
            method: method.into(),
            target: target.into(),
            protocol: protocol.into(),
            headers,
            body: Vec::new(),
        };
        let body_len = match request.header("Content-Length") {
            Some(value) => value.parse::<usize>().map_err(|_| ParseError::Malformed)?,
            None => 0,
        };
        if body_len > MAX_BODY {
            return Err(ParseError::TooLarge);
        }
        let total = head_len + 4 + body_len;
        if buffer.len() < total {
            return Ok(None);
        }
        request.body = buffer[head_len + 4..total].to_vec();
        buffer.drain(..total);
        Ok(Some(request))
    }
}

pub struct Response {
    status: u16,
    reason: &'static str,
    content_type: Option<&'static str>,
    body: Vec<u8>,
}

impl Response {
    pub fn ok() -> Self {
        Self::status(200, "OK")
    }

    pub fn status(status: u16, reason: &'static str) -> Self {
        Self { status, reason, content_type: None, body: Vec::new() }
    }

    pub fn body(mut self, content_type: &'static str, body: Vec<u8>) -> Self {
        self.content_type = Some(content_type);
        self.body = body;
        self
    }

    pub fn code(&self) -> u16 {
        self.status
    }

    /// Wire bytes, echoing the request's protocol and `CSeq`.
    pub fn encode(&self, request: &Request) -> Vec<u8> {
        let mut head = format!("{} {} {}\r\n", request.protocol, self.status, self.reason);
        if let Some(cseq) = request.header("CSeq") {
            head.push_str(&format!("CSeq: {cseq}\r\n"));
        }
        head.push_str(&format!("Server: {SERVER}\r\n"));
        if let Some(content_type) = self.content_type {
            head.push_str(&format!("Content-Type: {content_type}\r\n"));
        }
        head.push_str(&format!("Content-Length: {}\r\n\r\n", self.body.len()));
        let mut out = head.into_bytes();
        out.extend_from_slice(&self.body);
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_pipelined_requests_incrementally() {
        let mut buffer = Vec::from(&b"POST /pair-setup RTSP/1.0\r\nCSeq: 3\r\nContent-Length: 3\r\n\r\nab"[..]);
        assert_eq!(Request::parse(&mut buffer), Ok(None));
        buffer.extend_from_slice(b"cGET /info HTTP/1.1\r\n\r\n");
        let first = Request::parse(&mut buffer).unwrap().unwrap();
        assert_eq!((first.method.as_str(), first.body.as_slice()), ("POST", &b"abc"[..]));
        assert_eq!(first.header("cseq"), Some("3"));
        let second = Request::parse(&mut buffer).unwrap().unwrap();
        assert_eq!((second.target.as_str(), second.protocol.as_str()), ("/info", "HTTP/1.1"));
        assert!(buffer.is_empty());
    }

    #[test]
    fn responses_echo_protocol_and_cseq() {
        let mut buffer = Vec::from(&b"SETUP rtsp://x/1 RTSP/1.0\r\nCSeq: 9\r\n\r\n"[..]);
        let request = Request::parse(&mut buffer).unwrap().unwrap();
        let bytes = Response::ok().body("text/plain", b"hi".to_vec()).encode(&request);
        let text = core::str::from_utf8(&bytes).unwrap();
        assert!(text.starts_with("RTSP/1.0 200 OK\r\nCSeq: 9\r\nServer: AirTunes/366.0\r\n"));
        assert!(text.ends_with("Content-Length: 2\r\n\r\nhi"));
    }

    #[test]
    fn rejects_garbage() {
        let mut buffer = Vec::from(&b"hello\r\n\r\n"[..]);
        assert_eq!(Request::parse(&mut buffer), Err(ParseError::Malformed));
    }
}
