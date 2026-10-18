//! Audio port adapter, arbitrator, and mock recording sink (AUD-001, AUD-002, AUD-003, PRD-002).
//!
//! Provides an in-memory testable AudioPort implementation that tracks audio commands,
//! gain changes, verifies session ownership (AUD-001.1), and arbitrates output
//! by preempting external music receivers (AirPlay, Bluetooth) before alarm playback (AUD-001, AUD-002.2, AUD-003.2).

use robine_ports::AudioPort;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::Duration;

pub const SERVICES_TO_PREEMPT: &[&str] = &["shairport-sync", "bluealsa-aplay"];
pub const PREEMPTION_TIMEOUT: Duration = Duration::from_millis(500);

#[derive(Debug)]
pub struct AudioArbitrator {
    service_dir: PathBuf,
    is_preempted: AtomicBool,
}

impl AudioArbitrator {
    pub fn new(service_dir: impl Into<PathBuf>) -> Self {
        Self {
            service_dir: service_dir.into(),
            is_preempted: AtomicBool::new(false),
        }
    }

    pub fn airplay_available(&self) -> bool {
        self.service_dir.join("shairport-sync").exists()
    }

    pub fn bluetooth_available(&self) -> bool {
        self.service_dir.join("bluealsa-aplay").exists()
    }

    #[allow(dead_code)]
    pub fn is_preempted(&self) -> bool {
        self.is_preempted.load(Ordering::SeqCst)
    }

    /// Suspend external receivers (shairport-sync, bluealsa-aplay) before alarm playback (AUD-001, AUD-002.2, AUD-003.2).
    /// Timeout is capped at 500 ms so that a slow or wedged receiver never delays the alarm (AUD-001.3).
    pub async fn preempt(&self) {
        if self.is_preempted.swap(true, Ordering::SeqCst) {
            return;
        }

        for svc in SERVICES_TO_PREEMPT {
            let svc_path = self.service_dir.join(svc);
            if svc_path.exists() {
                let cmd = tokio::process::Command::new("sv")
                    .arg("-w")
                    .arg("1")
                    .arg("down")
                    .arg(&svc_path)
                    .output();
                match tokio::time::timeout(PREEMPTION_TIMEOUT, cmd).await {
                    Ok(Ok(output)) if !output.status.success() => {
                        eprintln!("warning: sv down {} returned {:?}", svc, output.status);
                    }
                    Ok(Err(e)) => {
                        eprintln!("warning: failed to invoke sv down {}: {}", svc, e);
                    }
                    Err(_) => {
                        eprintln!("warning: sv down {} timed out after 500ms (AUD-001.3)", svc);
                    }
                    _ => {}
                }
            }
        }
    }

    /// Restore external music receivers after the alarm session finishes (AUD-001, AUD-002.2, AUD-003.2).
    pub async fn restore(&self) {
        if !self.is_preempted.swap(false, Ordering::SeqCst) {
            return;
        }

        for svc in SERVICES_TO_PREEMPT {
            let svc_path = self.service_dir.join(svc);
            if svc_path.exists() {
                let _ = tokio::process::Command::new("sv")
                    .arg("up")
                    .arg(&svc_path)
                    .output()
                    .await;
            }
        }
    }
}

/// Selects the stable ALSA `(output_device, mixer_control_name)` from `/proc/asound/cards` content (PLT-002.1, PLT-005).
/// Supports:
/// - InnoMaker HiFi AMP Pro Mini HAT (`sndrpimerusamp` / Infineon MA12070P, mixer `"A.Mstr Vol"`)
/// - JustBoom Amp Zero pHAT (`sndrpijustboomd`, mixer `"Digital"`)
/// - HiFiBerry Amp2 (`sndrpihifiberry`, mixer `"Digital"`)
/// - Fallback (`plughw:CARD=Amp2,DEV=0`, mixer `"Digital"`)
pub fn select_alsa_card_config(asound_cards: &str) -> (&'static str, &'static str) {
    if asound_cards.contains("sndrpimerusamp") {
        ("plughw:CARD=sndrpimerusamp,DEV=0", "A.Mstr Vol")
    } else if asound_cards.contains("sndrpijustboomd") {
        ("plughw:CARD=sndrpijustboomd,DEV=0", "Digital")
    } else if asound_cards.contains("sndrpihifiberry") {
        ("plughw:CARD=sndrpihifiberry,DEV=0", "Digital")
    } else {
        ("plughw:CARD=Amp2,DEV=0", "Digital")
    }
}

/// Returns the `shairport-sync` interpolation mode for a target architecture (AUD-002, PLT-005).
/// Single-core 32-bit ARMv6 (`arm` / Pi Zero 1 W) uses `"basic"` (~15% CPU),
/// while multi-core 64-bit targets (`aarch64` / Pi 3, Pi Zero 2 W) use `"soxr"`.
pub fn select_shairport_interpolation(target_arch: &str) -> &'static str {
    if target_arch == "arm" {
        "basic"
    } else {
        "soxr"
    }
}

/// Generates `/run/shairport-sync.conf` on daemon startup (AUD-002).
pub fn generate_shairport_config(dest: &Path) -> std::io::Result<()> {
    let cards = std::fs::read_to_string("/proc/asound/cards").unwrap_or_default();
    let (output_device, mixer_control_name) = select_alsa_card_config(&cards);
    let interpolation = select_shairport_interpolation(std::env::consts::ARCH);
    let conf = format!(
        r#"// Generated by robine-wake (AUD-002)
general = {{
    name = "Robine Wake Bedroom";
    interpolation = "{interpolation}";
}};

alsa = {{
    output_device = "{output_device}";
    output_format = "S32";
    mixer_control_name = "{mixer_control_name}";
}};
"#
    );
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(dest, conf)
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AudioRecord {
    pub session_id: String,
    pub action: String,
    pub sound_id: Option<String>,
    pub gain: Option<i64>,
}

pub struct AudioSink {
    arbitrator: AudioArbitrator,
    inner: Mutex<AudioInner>,
}

struct AudioInner {
    active_session_id: Option<String>,
    current_sound_id: Option<String>,
    current_gain: i64,
    is_playing: bool,
    history: Vec<AudioRecord>,
}

impl AudioSink {
    pub fn new() -> Self {
        let service_dir = std::env::var("ROBINE_RS_SERVICES")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("/etc/service"));
        Self::with_service_dir(service_dir)
    }

    pub fn with_service_dir(service_dir: impl Into<PathBuf>) -> Self {
        Self {
            arbitrator: AudioArbitrator::new(service_dir),
            inner: Mutex::new(AudioInner {
                active_session_id: None,
                current_sound_id: None,
                current_gain: 0,
                is_playing: false,
                history: Vec::new(),
            }),
        }
    }

    #[allow(dead_code)]
    pub fn arbitrator(&self) -> &AudioArbitrator {
        &self.arbitrator
    }

    pub fn airplay_available(&self) -> bool {
        self.arbitrator.airplay_available()
    }

    pub fn bluetooth_available(&self) -> bool {
        self.arbitrator.bluetooth_available()
    }

    #[allow(dead_code)]
    pub fn is_preempted(&self) -> bool {
        self.arbitrator.is_preempted()
    }

    #[allow(dead_code)]
    pub fn is_playing(&self) -> bool {
        self.inner.lock().unwrap().is_playing
    }

    #[allow(dead_code)]
    pub fn current_gain(&self) -> i64 {
        self.inner.lock().unwrap().current_gain
    }

    #[allow(dead_code)]
    pub fn current_sound_id(&self) -> Option<String> {
        self.inner.lock().unwrap().current_sound_id.clone()
    }

    #[allow(dead_code)]
    pub fn history(&self) -> Vec<AudioRecord> {
        self.inner.lock().unwrap().history.clone()
    }
}

impl Default for AudioSink {
    fn default() -> Self {
        Self::new()
    }
}

impl AudioPort for AudioSink {
    async fn play(&self, session_id: &str, sound_id: &str, gain: i64) -> Result<(), String> {
        // Preempt external music receivers before opening output for an alarm (AUD-001, AUD-002, AUD-003)
        self.arbitrator.preempt().await;

        let mut state = self.inner.lock().unwrap();

        // AUD-001.1: An audio command from an older session does not affect the active session
        if let Some(active) = &state.active_session_id {
            if active != session_id && state.is_playing {
                return Err(format!(
                    "audio output already owned by session '{active}', rejecting session '{session_id}'"
                ));
            }
        }

        // AUD-001.2: Gain must be clamped to safety ceiling
        let safe_gain = gain.clamp(0, 100);

        state.active_session_id = Some(session_id.to_string());
        state.current_sound_id = Some(sound_id.to_string());
        state.current_gain = safe_gain;
        state.is_playing = true;
        state.history.push(AudioRecord {
            session_id: session_id.to_string(),
            action: "play".to_string(),
            sound_id: Some(sound_id.to_string()),
            gain: Some(safe_gain),
        });

        Ok(())
    }

    async fn set_gain(&self, session_id: &str, gain: i64) -> Result<(), String> {
        let mut state = self.inner.lock().unwrap();

        // Ignore gain changes for non-active sessions
        if state.active_session_id.as_deref() != Some(session_id) {
            return Ok(());
        }

        let safe_gain = gain.clamp(0, 100);
        state.current_gain = safe_gain;
        state.history.push(AudioRecord {
            session_id: session_id.to_string(),
            action: "set_gain".to_string(),
            sound_id: None,
            gain: Some(safe_gain),
        });

        Ok(())
    }

    async fn stop(&self, session_id: &str) -> Result<(), String> {
        let should_restore = {
            let mut state = self.inner.lock().unwrap();

            // Ignore stop commands for non-active sessions
            if state.active_session_id.as_deref() != Some(session_id) {
                false
            } else {
                state.is_playing = false;
                state.active_session_id = None;
                state.history.push(AudioRecord {
                    session_id: session_id.to_string(),
                    action: "stop".to_string(),
                    sound_id: None,
                    gain: None,
                });
                true
            }
        };

        if should_restore {
            // Restore music receivers after session ends (AUD-001, AUD-002, AUD-003)
            self.arbitrator.restore().await;
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn plays_and_stops_audio_recording_commands() {
        let sink = AudioSink::new();
        assert!(!sink.is_playing());

        sink.play("sess-1", "jungle_sunrise", 40).await.unwrap();
        assert!(sink.is_playing());
        assert_eq!(sink.current_gain(), 40);
        assert_eq!(sink.current_sound_id().as_deref(), Some("jungle_sunrise"));

        sink.set_gain("sess-1", 60).await.unwrap();
        assert_eq!(sink.current_gain(), 60);

        sink.stop("sess-1").await.unwrap();
        assert!(!sink.is_playing());

        let history = sink.history();
        assert_eq!(history.len(), 3);
        assert_eq!(history[0].action, "play");
        assert_eq!(history[1].action, "set_gain");
        assert_eq!(history[2].action, "stop");
    }

    #[tokio::test]
    async fn ignores_stale_session_commands() {
        let sink = AudioSink::new();
        sink.play("sess-active", "alarm_sound", 50).await.unwrap();

        // Stale session commands are ignored
        sink.set_gain("sess-old", 90).await.unwrap();
        assert_eq!(sink.current_gain(), 50);

        sink.stop("sess-old").await.unwrap();
        assert!(sink.is_playing());
    }

    #[tokio::test]
    async fn arbitrator_preempts_and_restores_receivers() {
        let temp = std::env::temp_dir().join(format!("audio-test-{}", uuid::Uuid::new_v4()));
        let shairport_dir = temp.join("shairport-sync");
        let bluealsa_dir = temp.join("bluealsa-aplay");
        std::fs::create_dir_all(&shairport_dir).unwrap();
        std::fs::create_dir_all(&bluealsa_dir).unwrap();

        let sink = AudioSink::with_service_dir(&temp);
        assert!(sink.airplay_available());
        assert!(sink.bluetooth_available());
        assert!(!sink.is_preempted());

        sink.play("sess-1", "alarm", 50).await.unwrap();
        assert!(sink.is_preempted());

        sink.stop("sess-1").await.unwrap();
        assert!(!sink.is_preempted());
    }

    #[test]
    fn generates_shairport_configuration_file() {
        let temp = std::env::temp_dir().join(format!("shairport-conf-{}", uuid::Uuid::new_v4()));
        let conf_file = temp.join("shairport-sync.conf");
        generate_shairport_config(&conf_file).unwrap();

        let contents = std::fs::read_to_string(&conf_file).unwrap();
        assert!(contents.contains("Robine Wake Bedroom"));
        assert!(contents.contains("plughw:CARD="));
        assert!(contents.contains("Digital"));
    }

    #[test]
    fn selects_innomaker_merus_justboom_and_hifiberry_alsa_cards() {
        let innomaker_merus_proc = " 0 [sndrpimerusamp ]: Merus_Amp - snd_rpi_merus_amp\n                      snd_rpi_merus_amp\n";
        assert_eq!(
            select_alsa_card_config(innomaker_merus_proc),
            ("plughw:CARD=sndrpimerusamp,DEV=0", "A.Mstr Vol")
        );

        let justboom_proc = " 0 [sndrpijustboomd]: JustBoomDac - snd_rpi_justboom_dac\n                      snd_rpi_justboom_dac\n";
        assert_eq!(
            select_alsa_card_config(justboom_proc),
            ("plughw:CARD=sndrpijustboomd,DEV=0", "Digital")
        );

        let hifiberry_proc = " 0 [sndrpihifiberry]: HifiBerryDacPlu - snd_rpi_hifiberry_dacplus\n                      snd_rpi_hifiberry_dacplus\n";
        assert_eq!(
            select_alsa_card_config(hifiberry_proc),
            ("plughw:CARD=sndrpihifiberry,DEV=0", "Digital")
        );

        assert_eq!(
            select_alsa_card_config(""),
            ("plughw:CARD=Amp2,DEV=0", "Digital")
        );

        assert_eq!(select_shairport_interpolation("arm"), "basic");
        assert_eq!(select_shairport_interpolation("aarch64"), "soxr");
    }
}
