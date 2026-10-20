//! Glue between the protocol, the clock, the flash and the event bus.

use core::sync::atomic::{AtomicBool, Ordering};

use alloc::vec::Vec;
use embassy_net::Stack;
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::mutex::Mutex;
use log::{error, info};
use robine_api::{Context, Device, Outcome};

use crate::store::Store;
use crate::{clock, events, guide_light};

/// Whether an alarm is audible; drives the LED until the amplifier is wired.
pub static RINGING: AtomicBool = AtomicBool::new(false);

pub struct App {
    device: Mutex<CriticalSectionRawMutex, Device>,
    store: Mutex<CriticalSectionRawMutex, Option<Store>>,
    /// `None` without Wi-Fi, on the Pi's light co-processor.
    stack: Option<Stack<'static>>,
}

impl App {
    pub fn new(device: Device, store: Option<Store>, stack: Option<Stack<'static>>) -> Self {
        Self {
            device: Mutex::new(device),
            store: Mutex::new(store),
            stack,
        }
    }

    pub fn context(&self) -> Context {
        Context {
            now: clock::now(),
            monotonic_ms: clock::monotonic_ms(),
            clock_trusted: clock::trusted(),
            ipv4: self
                .stack
                .and_then(|stack| stack.config_v4())
                .map(|config| config.address.address().octets()),
        }
    }

    /// `POST /api/v1/command`.
    pub async fn command(&self, request: &[u8]) -> Vec<u8> {
        let ctx = self.context();
        let (response, outcome, snapshot) = {
            let mut device = self.device.lock().await;
            let (response, outcome) = device.handle(request, &ctx);
            if outcome.clock_confirmed {
                clock::trust();
                device.refresh_schedule(&self.context());
            }
            RINGING.store(device.audio().is_some(), Ordering::Relaxed);
            guide_light::publish(device.light());
            let snapshot = outcome.persist.then(|| device.snapshot());
            (response, outcome, snapshot)
        };
        self.apply(outcome, snapshot).await;
        response
    }

    /// Scheduler and session step, about once a second.
    pub async fn tick(&self) {
        let ctx = self.context();
        let (outcome, snapshot) = {
            let mut device = self.device.lock().await;
            let outcome = device.tick(&ctx);
            RINGING.store(device.audio().is_some(), Ordering::Relaxed);
            let snapshot = outcome.persist.then(|| device.snapshot());
            (outcome, snapshot)
        };
        self.apply(outcome, snapshot).await;
    }

    /// The clock was just set: occurrences must be computed again.
    pub async fn clock_changed(&self) {
        let ctx = self.context();
        self.device.lock().await.refresh_schedule(&ctx);
        events::publish(robine_api::STATE_CHANGED);
    }

    async fn apply(&self, outcome: Outcome, snapshot: Option<Vec<u8>>) {
        if let Some(snapshot) = snapshot {
            if let Some(store) = self.store.lock().await.as_mut() {
                match store.save(&snapshot) {
                    Ok(()) => info!("state saved ({} bytes)", snapshot.len()),
                    Err(error) => error!("state not saved: {error:?}"),
                }
            }
        }
        for event in outcome.events {
            events::publish(event);
        }
    }
}
