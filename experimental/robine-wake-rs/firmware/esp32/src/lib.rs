//! Robine Wake firmware for ESP32: the v1 command API of the mobile app and
//! the remote button, served over Wi-Fi without an operating system.

#![no_std]

extern crate alloc;

pub mod airplay;
pub mod app;
pub mod clock;
pub mod events;
pub mod guide_light;
pub mod http;
pub mod ntp;
pub mod serial;
pub mod store;
pub mod web;
