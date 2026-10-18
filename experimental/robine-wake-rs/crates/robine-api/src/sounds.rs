//! Sound catalogue advertised in `state.get`.

use serde::Serialize;

#[derive(Clone, Copy, Debug, Serialize)]
pub struct Sound {
    pub id: &'static str,
    pub title: &'static str,
    pub artist: &'static str,
    pub duration_ms: u64,
    pub intensity: &'static str,
    pub source: &'static str,
}

/// Sounds bundled with the firmware (`priv/sounds/manifest.json`).
pub const BUNDLED: &[Sound] = &[
    Sound {
        id: "jazz_for_breakfast",
        title: "Jazz for Breakfast",
        artist: "TokyoRifft",
        duration_ms: 242_112,
        intensity: "bright",
        source: "bundled",
    },
    Sound {
        id: "jungle_sunrise",
        title: "Jungle Sunrise",
        artist: "Nature's Eye",
        duration_ms: 976_056,
        intensity: "gentle",
        source: "bundled",
    },
    Sound {
        id: "storm_rain_lasonotheque_2719",
        title: "Orage et pluie 4",
        artist: "Joseph SARDIN · LaSonotheque.org",
        duration_ms: 2_092_152,
        intensity: "meditation",
        source: "bundled",
    },
    Sound {
        id: "sleep_music_vol_16",
        title: "Sleep Music · Vol. 16",
        artist: "Relaxing Time",
        duration_ms: 1_207_920,
        intensity: "gentle",
        source: "bundled",
    },
    Sound {
        id: "wake_up_call",
        title: "Wake Up Call",
        artist: "4379051",
        duration_ms: 71_040,
        intensity: "strong",
        source: "bundled",
    },
];
