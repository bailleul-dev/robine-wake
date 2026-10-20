//! Control of a light wired to the device (the ESP32's LED strip).
//!
//! `light.set` is low level: the Raspberry Pi, master of the audio, owns the
//! 4/6 breathing clock (30-003) and sends one per phase with a transition,
//! like `dynamics.duration` on Hue. The device only interpolates from the
//! color shown when the command arrives.
//!
//! `light.program` starts a program the device renders on its own, pixel by
//! pixel: a dawn, a sunset or a breathing session at a given cadence.

use alloc::string::String;

use serde_json::{json, Map, Value};

use crate::breathing::{Breathing, Cadence};
use crate::dawn::Dawn;
use crate::device::{Error, Result};
use crate::sunset::Sunset;
use crate::{Context, Device};

/// Longest transition accepted, in milliseconds.
pub const MAX_TRANSITION_MS: u64 = 60_000;
/// Longest dawn or sunset accepted, in milliseconds: two hours.
pub const MAX_PROGRAM_MS: u64 = 7_200_000;
/// Ceiling of a program's light, in percent: 60 pixels near 2 A on a small
/// 5 V supply.
pub const PROGRAM_MAX_BRIGHTNESS: f32 = 60.0;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Rgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl Rgb {
    pub const OFF: Rgb = Rgb { r: 0, g: 0, b: 0 };
}

/// Interpolation curve of a transition.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Easing {
    Linear,
    /// Same curve as the breathing audio gain of the Pi.
    Smoothstep,
}

impl Easing {
    fn apply(self, progress: f32) -> f32 {
        let x = progress.clamp(0.0, 1.0);
        match self {
            Easing::Linear => x,
            Easing::Smoothstep => x * x * (3.0 - 2.0 * x),
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Easing::Linear => "linear",
            Easing::Smoothstep => "smoothstep",
        }
    }
}

/// A color and an intensity in percent: what the light aims at.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct LightLevel {
    pub color: Rgb,
    pub brightness: f32,
}

impl LightLevel {
    /// Channel values to send to the LED: the color dimmed by the intensity.
    pub fn output(self) -> Rgb {
        let scale = |value: u8| (f32::from(value) * self.brightness.clamp(0.0, 100.0) / 100.0 + 0.5) as u8;
        Rgb {
            r: scale(self.color.r),
            g: scale(self.color.g),
            b: scale(self.color.b),
        }
    }
}

/// Transition in progress, or finished and held.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct LightFade {
    pub from: LightLevel,
    pub to: LightLevel,
    /// Monotonic start of the transition.
    pub started_ms: u64,
    pub duration_ms: u64,
    pub easing: Easing,
}

impl LightFade {
    pub fn level_at(&self, monotonic_ms: u64) -> LightLevel {
        let elapsed = monotonic_ms.saturating_sub(self.started_ms);
        if elapsed >= self.duration_ms {
            return self.to;
        }
        let t = self.easing.apply(elapsed as f32 / self.duration_ms as f32);
        let mix = |from: u8, to: u8| (f32::from(from) + (f32::from(to) - f32::from(from)) * t + 0.5) as u8;
        LightLevel {
            color: Rgb {
                r: mix(self.from.color.r, self.to.color.r),
                g: mix(self.from.color.g, self.to.color.g),
                b: mix(self.from.color.b, self.to.color.b),
            },
            brightness: self.from.brightness + (self.to.brightness - self.from.brightness) * t,
        }
    }
}

/// What the light shows: a `light.set` transition or a program.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum LightScene {
    Fade(LightFade),
    Dawn(Dawn),
    Sunset(Sunset),
    Breathing(Breathing),
}

impl LightScene {
    /// Colour of pixel `index` on a strip of `count` pixels; a transition
    /// shows the same colour on every pixel.
    pub fn pixel_at(&self, monotonic_ms: u64, index: usize, count: usize) -> Rgb {
        match self {
            LightScene::Fade(fade) => fade.level_at(monotonic_ms).output(),
            LightScene::Dawn(dawn) => dawn.pixel_at(monotonic_ms, index, count),
            LightScene::Sunset(sunset) => sunset.pixel_at(monotonic_ms, index, count),
            LightScene::Breathing(breathing) => breathing.pixel_at(monotonic_ms, index, count),
        }
    }

    fn program(&self) -> Option<&'static str> {
        match self {
            LightScene::Fade(_) => None,
            LightScene::Dawn(_) => Some("dawn"),
            LightScene::Sunset(_) => Some("sunset"),
            LightScene::Breathing(_) => Some("breathing"),
        }
    }
}

impl Device {
    /// What the light shows; `None` until the first `light.set` or
    /// `light.program`, and after `light.program` `off`.
    pub fn light(&self) -> Option<LightScene> {
        self.light
    }

    /// `light.program`: `{"program":"dawn"|"sunset","duration_ms":…}`,
    /// `{"program":"breathing","cadence":"0-4-0-6"}` or `{"program":"off"}`.
    /// The program starts now and runs until the next light command.
    pub(crate) fn start_light_program(&mut self, body: &Map<String, Value>, ctx: &Context) -> Result<Value> {
        let duration_ms = || {
            body.get("duration_ms")
                .and_then(Value::as_u64)
                .filter(|ms| (1..=MAX_PROGRAM_MS).contains(ms))
                .ok_or(Error::Code("invalid_duration"))
        };
        let started_ms = ctx.monotonic_ms;
        self.light = match body.get("program").and_then(Value::as_str) {
            Some("dawn") => Some(LightScene::Dawn(Dawn {
                started_ms,
                duration_ms: duration_ms()?,
                max_brightness: PROGRAM_MAX_BRIGHTNESS,
            })),
            Some("sunset") => Some(LightScene::Sunset(Sunset {
                started_ms,
                duration_ms: duration_ms()?,
                max_brightness: PROGRAM_MAX_BRIGHTNESS,
            })),
            Some("breathing") => {
                let cadence = body
                    .get("cadence")
                    .and_then(Value::as_str)
                    .and_then(Cadence::parse)
                    .ok_or(Error::Code("invalid_cadence"))?;
                Some(LightScene::Breathing(Breathing { started_ms, cadence }))
            }
            Some("off") => None,
            _ => return Err(Error::Code("invalid_program")),
        };
        Ok(self.light_status(ctx))
    }

    /// `light.set`: `{"color":{"r","g","b"},"brightness":0-100,
    /// "transition_ms":0-60000,"easing":"linear"|"smoothstep"}`. Only
    /// `brightness` is required; the color defaults to the current one.
    pub(crate) fn set_light(&mut self, body: &Map<String, Value>, ctx: &Context) -> Result<Value> {
        let current = self.current_light(ctx);
        let brightness = body
            .get("brightness")
            .and_then(Value::as_f64)
            .filter(|brightness| (0.0..=100.0).contains(brightness))
            .ok_or(Error::Code("invalid_brightness"))? as f32;
        let color = match body.get("color") {
            None | Some(Value::Null) => current.color,
            Some(color) => parse_color(color).ok_or(Error::Code("invalid_color"))?,
        };
        let duration_ms = match body.get("transition_ms") {
            None | Some(Value::Null) => 0,
            Some(value) => value
                .as_u64()
                .filter(|ms| *ms <= MAX_TRANSITION_MS)
                .ok_or(Error::Code("invalid_transition"))?,
        };
        let easing = match body.get("easing").filter(|easing| !easing.is_null()).map(Value::as_str) {
            None | Some(Some("linear")) => Easing::Linear,
            Some(Some("smoothstep")) => Easing::Smoothstep,
            Some(_) => return Err(Error::Code("invalid_easing")),
        };

        self.light = Some(LightScene::Fade(LightFade {
            from: current,
            to: LightLevel { color, brightness },
            started_ms: ctx.monotonic_ms,
            duration_ms,
            easing,
        }));
        Ok(self.light_status(ctx))
    }

    /// `light.get`.
    pub(crate) fn light_status(&self, ctx: &Context) -> Value {
        let current = self.current_light(ctx);
        let fade = self.fade();
        let target = fade.map_or(current, |fade| fade.to);
        let (remaining_ms, easing) = fade.map_or((0, Easing::Linear), |fade| {
            let end = fade.started_ms + fade.duration_ms;
            (end.saturating_sub(ctx.monotonic_ms), fade.easing)
        });
        json!({
            "name": self.platform.light,
            "program": self.light.and_then(|scene| scene.program()),
            "color": color_json(current.color),
            "brightness": current.brightness,
            "target": { "color": color_json(target.color), "brightness": target.brightness },
            "transition_remaining_ms": remaining_ms,
            "easing": easing.as_str(),
            "monotonic_ms": ctx.monotonic_ms,
        })
    }

    fn fade(&self) -> Option<LightFade> {
        match self.light {
            Some(LightScene::Fade(fade)) => Some(fade),
            _ => None,
        }
    }

    /// Level a transition starts from: a program counts as dark.
    fn current_light(&self, ctx: &Context) -> LightLevel {
        self.fade().map_or_else(LightLevel::default, |fade| fade.level_at(ctx.monotonic_ms))
    }
}

fn parse_color(value: &Value) -> Option<Rgb> {
    let channel = |key: &str| value.get(key)?.as_u64().filter(|v| *v <= 255).map(|v| v as u8);
    Some(Rgb {
        r: channel("r")?,
        g: channel("g")?,
        b: channel("b")?,
    })
}

fn color_json(color: Rgb) -> Value {
    json!({ "r": color.r, "g": color.g, "b": color.b })
}
