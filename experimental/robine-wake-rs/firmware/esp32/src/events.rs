//! Event bus behind `GET /api/v1/events`.

use core::sync::atomic::{AtomicU32, Ordering};

use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::pubsub::{PubSubChannel, Subscriber};

/// Simultaneous event streams (app, web page, one spare).
pub const MAX_STREAMS: usize = 3;
const CAPACITY: usize = 8;

#[derive(Clone, Copy, Debug)]
pub struct Event {
    pub id: u32,
    pub name: &'static str,
}

pub type EventSubscriber = Subscriber<'static, CriticalSectionRawMutex, Event, CAPACITY, MAX_STREAMS, 1>;

static CHANNEL: PubSubChannel<CriticalSectionRawMutex, Event, CAPACITY, MAX_STREAMS, 1> =
    PubSubChannel::new();
static SEQUENCE: AtomicU32 = AtomicU32::new(0);

pub fn publish(name: &'static str) {
    let id = SEQUENCE.fetch_add(1, Ordering::Relaxed) + 1;
    CHANNEL.immediate_publisher().publish_immediate(Event { id, name });
}

/// Id of the last published event, sent with `ready`.
pub fn sequence() -> u32 {
    SEQUENCE.load(Ordering::Relaxed)
}

/// `None` when every stream slot is taken.
pub fn subscribe() -> Option<EventSubscriber> {
    CHANNEL.subscriber().ok()
}
