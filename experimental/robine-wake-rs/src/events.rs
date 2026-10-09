//! Small replayable event stream used by HTTP SSE clients.
//!
//! Port of `RobineWake.EventStream`: a sequence counter, a 64-event replay
//! buffer for `Last-Event-ID`, and a broadcast channel for live subscribers.

use std::collections::VecDeque;
use std::sync::Mutex;

use chrono::Utc;
use serde::Serialize;
use serde_json::Value;
use tokio::sync::broadcast;

const MAXIMUM_EVENTS: usize = 64;

#[derive(Clone, Debug, Serialize)]
pub struct Event {
    pub id: u64,
    pub event: String,
    pub at: Option<String>,
    pub data: Option<Value>,
}

impl Event {
    /// Wire format of `sse_event/1` in the Elixir router (axum builds the
    /// frames itself in `http.rs`; kept as the reference encoding).
    #[allow(dead_code)]
    pub fn to_sse(&self) -> String {
        let data = serde_json::json!({
            "v": 1, "id": self.id, "event": self.event, "at": self.at, "data": self.data
        });
        format!("id: {}\nevent: {}\ndata: {}\n\n", self.id, self.event, data)
    }
}

struct Inner {
    sequence: u64,
    events: VecDeque<Event>,
}

pub struct EventStream {
    inner: Mutex<Inner>,
    sender: broadcast::Sender<Event>,
}

pub struct Subscription {
    pub sequence: u64,
    pub replay: Vec<Event>,
    pub receiver: broadcast::Receiver<Event>,
}

impl Default for EventStream {
    fn default() -> Self {
        Self::new()
    }
}

impl EventStream {
    pub fn new() -> EventStream {
        let (sender, _receiver) = broadcast::channel(MAXIMUM_EVENTS);
        EventStream {
            inner: Mutex::new(Inner {
                sequence: 0,
                events: VecDeque::new(),
            }),
            sender,
        }
    }

    pub fn publish(&self, name: &str, data: Option<Value>) -> Event {
        let mut inner = self.lock();
        let event = Event {
            id: inner.sequence + 1,
            event: name.to_string(),
            at: Some(Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true)),
            data,
        };
        inner.sequence = event.id;
        inner.events.push_back(event.clone());
        while inner.events.len() > MAXIMUM_EVENTS {
            inner.events.pop_front();
        }
        // No live subscriber is not an error; the replay buffer keeps the event.
        let _ = self.sender.send(event.clone());
        event
    }

    pub fn subscribe(&self, last_event_id: Option<u64>) -> Subscription {
        let inner = self.lock();
        let floor = last_event_id.unwrap_or(0);
        Subscription {
            sequence: inner.sequence,
            replay: inner
                .events
                .iter()
                .filter(|event| event.id > floor)
                .cloned()
                .collect(),
            receiver: self.sender.subscribe(),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replays_events_after_the_last_seen_id_and_caps_the_buffer() {
        let stream = EventStream::new();
        for index in 0..70 {
            stream.publish("state.changed", Some(serde_json::json!({ "n": index })));
        }
        let subscription = stream.subscribe(Some(66));
        assert_eq!(subscription.sequence, 70);
        let ids: Vec<u64> = subscription.replay.iter().map(|event| event.id).collect();
        assert_eq!(ids, vec![67, 68, 69, 70]);

        let full = stream.subscribe(None);
        assert_eq!(full.replay.len(), MAXIMUM_EVENTS);
        assert_eq!(full.replay[0].id, 7);
    }

    #[tokio::test]
    async fn live_subscribers_receive_new_events() {
        let stream = EventStream::new();
        let mut subscription = stream.subscribe(None);
        stream.publish("state.changed", None);
        let event = subscription.receiver.recv().await.unwrap();
        assert_eq!((event.id, event.event.as_str()), (1, "state.changed"));
        assert!(event
            .to_sse()
            .starts_with("id: 1\nevent: state.changed\ndata: {\"at\":"));
        assert!(event.to_sse().ends_with("\"v\":1}\n\n"));
    }
}
