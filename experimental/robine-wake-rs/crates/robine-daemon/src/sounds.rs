//! Sound library: bundled sounds (`priv/sounds`) and imported custom WAV sounds (`/data/sounds`).
//!
//! Port of `RobineWake.SoundLibrary` (AUD-001, DAT-001).
//! Validates PCM WAV format (16-bit, 44.1 kHz / 48 kHz, mono or stereo, <= 5 MB),
//! verifies SHA-256 digest, writes atomically with 0600 permissions,
//! and computes audio metadata (duration, peak dBFS).

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use base64::prelude::*;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

pub const MAXIMUM_SOUND_BYTES: usize = 5 * 1024 * 1024; // 5 MB

#[derive(Debug, PartialEq, Eq)]
pub enum SoundError {
    InvalidSoundId,
    InvalidSizeOrDigest,
    InvalidWave,
    NotPcm,
    UnsupportedChannels,
    UnsupportedSampleRate,
    UnsupportedBitDepth,
    InvalidFormatSizes,
    InvalidFileSizes,
    InvalidSound,
    IoError(String),
}

impl SoundError {
    pub fn code(&self) -> &'static str {
        match self {
            SoundError::InvalidSoundId => "invalid_sound_id",
            SoundError::InvalidSizeOrDigest => "invalid_size_or_digest",
            SoundError::InvalidWave => "invalid_wave",
            SoundError::NotPcm => "not_pcm",
            SoundError::UnsupportedChannels => "unsupported_channels",
            SoundError::UnsupportedSampleRate => "unsupported_sample_rate",
            SoundError::UnsupportedBitDepth => "unsupported_bit_depth",
            SoundError::InvalidFormatSizes => "invalid_format_sizes",
            SoundError::InvalidFileSizes => "invalid_file_sizes",
            SoundError::InvalidSound => "invalid_sound",
            SoundError::IoError(_) => "internal_error",
        }
    }
}

pub struct Sounds {
    bundled_directory: PathBuf,
    custom_directory: PathBuf,
    manifest: Vec<Value>,
}

impl Sounds {
    #[allow(dead_code)]
    pub fn open(bundled_directory: impl Into<PathBuf>) -> Sounds {
        let bundled = bundled_directory.into();
        let custom = bundled.join("custom");
        Self::with_custom(bundled, custom)
    }

    pub fn with_custom(
        bundled_directory: impl Into<PathBuf>,
        custom_directory: impl Into<PathBuf>,
    ) -> Sounds {
        let bundled_directory = bundled_directory.into();
        let custom_directory = custom_directory.into();
        let manifest = fs::read(bundled_directory.join("manifest.json"))
            .ok()
            .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
            .and_then(|value| value.as_array().cloned())
            .unwrap_or_default();
        Sounds {
            bundled_directory,
            custom_directory,
            manifest,
        }
    }

    #[allow(dead_code)]
    pub fn bundled_directory(&self) -> &Path {
        &self.bundled_directory
    }

    #[allow(dead_code)]
    pub fn custom_directory(&self) -> &Path {
        &self.custom_directory
    }

    /// Check if a sound ID exists and is ready for playback.
    ///
    /// `"default"` is always accepted. Custom `.wav` files take precedence,
    /// then bundled `.wav` / `.mp3` files listed in the manifest.
    pub fn available(&self, id: &str) -> bool {
        if id == "default" {
            return true;
        }
        self.file_for(id).is_some_and(|path| path.is_file())
    }

    /// Resolve the file path for playback on disk.
    pub fn file_for(&self, id: &str) -> Option<PathBuf> {
        if !validate_sound_id(id) {
            return None;
        }

        // 1. Custom WAV file on disk
        let custom_wav = self.custom_directory.join(format!("{id}.wav"));
        if custom_wav.is_file() {
            return Some(custom_wav);
        }

        // 2. Bundled sound file from manifest
        let filename = self
            .manifest
            .iter()
            .find(|entry| entry.get("id").and_then(Value::as_str) == Some(id))
            .and_then(|entry| entry.get("filename"))
            .and_then(Value::as_str)?;

        if Path::new(filename).components().count() != 1 {
            return None;
        }

        let bundled_path = self.bundled_directory.join(filename);
        if bundled_path.is_file() {
            Some(bundled_path)
        } else {
            None
        }
    }

    /// List all sounds (bundled + custom), sorted by source rank then title.
    pub fn list(&self) -> Vec<Value> {
        let mut sounds = Vec::new();

        // 1. Bundled sounds
        for entry in &self.manifest {
            if let Some(id) = entry.get("id").and_then(Value::as_str) {
                let mut item = entry.clone();
                item["source"] = json!("bundled");
                item["available"] = json!(self.available(id));
                sounds.push(item);
            }
        }

        // 2. Custom sounds in custom_directory
        if let Ok(entries) = fs::read_dir(&self.custom_directory) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) == Some("wav") {
                    if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                        if let Ok(metadata) = inspect_wave_file(&path) {
                            let title = format_title(stem);
                            let item = json!({
                                "id": stem,
                                "title": title,
                                "artist": Value::Null,
                                "format": metadata["format"],
                                "channels": metadata["channels"],
                                "sample_rate": metadata["sample_rate"],
                                "bits_per_sample": metadata["bits_per_sample"],
                                "duration_ms": metadata["duration_ms"],
                                "bytes": metadata["bytes"],
                                "normalized_peak_dbfs": metadata["normalized_peak_dbfs"],
                                "sha256": metadata["sha256"],
                                "intensity": "custom",
                                "source": if stem == "default" { "system" } else { "custom" },
                                "available": true,
                                "version": 1,
                            });
                            // If stem already in sounds (e.g. override), replace or add
                            if let Some(existing) = sounds
                                .iter_mut()
                                .find(|s| s.get("id").and_then(Value::as_str) == Some(stem))
                            {
                                *existing = item;
                            } else {
                                sounds.push(item);
                            }
                        }
                    }
                }
            }
        }

        sounds.sort_by(|a, b| {
            let rank_a = source_rank(a["source"].as_str().unwrap_or(""));
            let rank_b = source_rank(b["source"].as_str().unwrap_or(""));
            let title_a = a["title"].as_str().unwrap_or("").to_lowercase();
            let title_b = b["title"].as_str().unwrap_or("").to_lowercase();
            (rank_a, title_a).cmp(&(rank_b, title_b))
        });

        sounds
    }

    /// Import and store a custom sound (POST /api/sounds).
    ///
    /// Validates the sound ID, contents size, claimed SHA-256 digest,
    /// PCM WAV header, and writes to `custom_directory/{id}.wav` atomically (mode 0600).
    pub fn import(
        &self,
        id: &str,
        contents: &[u8],
        claimed_sha256: &str,
    ) -> Result<Value, SoundError> {
        if !validate_sound_id(id) {
            return Err(SoundError::InvalidSoundId);
        }

        if contents.len() <= 44 || contents.len() > MAXIMUM_SOUND_BYTES {
            return Err(SoundError::InvalidSizeOrDigest);
        }

        if claimed_sha256.len() != 64 || !claimed_sha256.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(SoundError::InvalidSizeOrDigest);
        }

        let mut hasher = Sha256::new();
        hasher.update(contents);
        let actual_digest = hex::encode(hasher.finalize());

        if !actual_digest.eq_ignore_ascii_case(claimed_sha256) {
            return Err(SoundError::InvalidSizeOrDigest);
        }

        let mut metadata = parse_wave(contents)?;
        metadata.insert("id".to_string(), json!(id));
        metadata.insert("sha256".to_string(), json!(actual_digest));
        metadata.insert("version".to_string(), json!(1));

        fs::create_dir_all(&self.custom_directory)
            .map_err(|e| SoundError::IoError(e.to_string()))?;

        let destination = self.custom_directory.join(format!("{id}.wav"));
        let temp_filename = format!("{id}.wav.{}.tmp", uuid::Uuid::new_v4());
        let temp_path = self.custom_directory.join(temp_filename);

        fs::write(&temp_path, contents).map_err(|e| SoundError::IoError(e.to_string()))?;

        #[cfg(unix)]
        {
            let mut perms = fs::metadata(&temp_path)
                .map_err(|e| SoundError::IoError(e.to_string()))?
                .permissions();
            perms.set_mode(0o600);
            fs::set_permissions(&temp_path, perms)
                .map_err(|e| SoundError::IoError(e.to_string()))?;
        }

        fs::rename(&temp_path, &destination).map_err(|e| {
            let _ = fs::remove_file(&temp_path);
            SoundError::IoError(e.to_string())
        })?;

        Ok(Value::Object(
            metadata
                .into_iter()
                .collect::<serde_json::Map<String, Value>>(),
        ))
    }

    /// Import from base64 data string (from HTTP JSON body).
    pub fn import_base64(
        &self,
        id: &str,
        data_base64: &str,
        claimed_sha256: &str,
    ) -> Result<Value, SoundError> {
        let contents = BASE64_STANDARD
            .decode(data_base64.trim())
            .map_err(|_| SoundError::InvalidSound)?;
        self.import(id, &contents, claimed_sha256)
    }
}

fn source_rank(source: &str) -> u8 {
    match source {
        "bundled" => 0,
        "system" => 1,
        _ => 2,
    }
}

fn format_title(id: &str) -> String {
    let replaced = id.replace('_', " ");
    let mut chars = replaced.chars();
    match chars.next() {
        None => String::new(),
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
    }
}

pub fn validate_sound_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 64
        && id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

pub fn inspect_wave_file(path: &Path) -> Result<serde_json::Map<String, Value>, SoundError> {
    let contents = fs::read(path).map_err(|e| SoundError::IoError(e.to_string()))?;
    let mut map = parse_wave(&contents)?;
    let mut hasher = Sha256::new();
    hasher.update(&contents);
    let digest = hex::encode(hasher.finalize());
    map.insert("sha256".to_string(), json!(digest));
    Ok(map.into_iter().collect::<serde_json::Map<String, Value>>())
}

/// Parse and validate canonical PCM WAV structure.
pub fn parse_wave(
    contents: &[u8],
) -> Result<std::collections::BTreeMap<String, Value>, SoundError> {
    if contents.len() < 44 {
        return Err(SoundError::InvalidWave);
    }

    if &contents[0..4] != b"RIFF" || &contents[8..12] != b"WAVE" || &contents[12..16] != b"fmt " {
        return Err(SoundError::InvalidWave);
    }

    let riff_size = u32::from_le_bytes(contents[4..8].try_into().unwrap());
    let fmt_size = u32::from_le_bytes(contents[16..20].try_into().unwrap());
    if fmt_size != 16 {
        return Err(SoundError::InvalidWave);
    }

    let audio_format = u16::from_le_bytes(contents[20..22].try_into().unwrap());
    if audio_format != 1 {
        return Err(SoundError::NotPcm);
    }

    let channels = u16::from_le_bytes(contents[22..24].try_into().unwrap());
    if channels != 1 && channels != 2 {
        return Err(SoundError::UnsupportedChannels);
    }

    let sample_rate = u32::from_le_bytes(contents[24..28].try_into().unwrap());
    if sample_rate != 44_100 && sample_rate != 48_000 {
        return Err(SoundError::UnsupportedSampleRate);
    }

    let byte_rate = u32::from_le_bytes(contents[28..32].try_into().unwrap());
    let block_align = u16::from_le_bytes(contents[32..34].try_into().unwrap());
    let bits_per_sample = u16::from_le_bytes(contents[34..36].try_into().unwrap());

    if bits_per_sample != 16 {
        return Err(SoundError::UnsupportedBitDepth);
    }

    let expected_align = channels * 2;
    if block_align != expected_align || byte_rate != sample_rate * (expected_align as u32) {
        return Err(SoundError::InvalidFormatSizes);
    }

    if &contents[36..40] != b"data" {
        return Err(SoundError::InvalidWave);
    }

    let data_size = u32::from_le_bytes(contents[40..44].try_into().unwrap()) as usize;
    let data = &contents[44..];

    if data_size != data.len() || riff_size as usize != 36 + data_size {
        return Err(SoundError::InvalidFileSizes);
    }

    // Compute peak sample and dBFS
    let mut peak: i16 = 0;
    #[allow(clippy::chunks_exact_to_as_chunks)]
    for chunk in data.chunks_exact(2) {
        let sample = i16::from_le_bytes([chunk[0], chunk[1]]);
        peak = peak.max(sample.abs());
    }

    let normalized_peak_dbfs = if peak == 0 {
        -120.0
    } else {
        let db = 20.0 * (peak as f64 / 32768.0).log10();
        (db * 100.0).round() / 100.0
    };

    let duration_ms = (data_size as u64 * 1000) / (byte_rate as u64);

    let mut map = std::collections::BTreeMap::new();
    map.insert("format".to_string(), json!("wav_pcm"));
    map.insert("channels".to_string(), json!(channels));
    map.insert("sample_rate".to_string(), json!(sample_rate));
    map.insert("bits_per_sample".to_string(), json!(bits_per_sample));
    map.insert("duration_ms".to_string(), json!(duration_ms));
    map.insert("bytes".to_string(), json!(contents.len()));
    map.insert(
        "normalized_peak_dbfs".to_string(),
        json!(normalized_peak_dbfs),
    );

    Ok(map)
}

/// Create a valid PCM WAV byte vector for testing or synthetic sound generation.
#[allow(dead_code)]
pub fn create_test_wav(
    sample_rate: u32,
    channels: u16,
    duration_seconds: f64,
    frequency: f64,
) -> Vec<u8> {
    let samples = (sample_rate as f64 * duration_seconds) as usize;
    let mut pcm = Vec::with_capacity(samples * channels as usize * 2);

    for i in 0..samples {
        let t = i as f64 / sample_rate as f64;
        let angle = 2.0 * std::f64::consts::PI * frequency * t;
        let value = (angle.sin() * 16000.0) as i16;
        for _ in 0..channels {
            pcm.extend_from_slice(&value.to_le_bytes());
        }
    }

    let data_size = pcm.len() as u32;
    let byte_rate = sample_rate * (channels as u32) * 2;
    let block_align = channels * 2;

    let mut wave = Vec::with_capacity(44 + pcm.len());
    wave.extend_from_slice(b"RIFF");
    wave.extend_from_slice(&(36 + data_size).to_le_bytes());
    wave.extend_from_slice(b"WAVE");
    wave.extend_from_slice(b"fmt ");
    wave.extend_from_slice(&16u32.to_le_bytes());
    wave.extend_from_slice(&1u16.to_le_bytes()); // PCM
    wave.extend_from_slice(&channels.to_le_bytes());
    wave.extend_from_slice(&sample_rate.to_le_bytes());
    wave.extend_from_slice(&byte_rate.to_le_bytes());
    wave.extend_from_slice(&block_align.to_le_bytes());
    wave.extend_from_slice(&16u16.to_le_bytes()); // 16-bit
    wave.extend_from_slice(b"data");
    wave.extend_from_slice(&data_size.to_le_bytes());
    wave.extend_from_slice(&pcm);

    wave
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_and_validates_canonical_wav() {
        let wav = create_test_wav(44100, 2, 0.5, 440.0);
        let meta = parse_wave(&wav).unwrap();
        assert_eq!(meta["format"], json!("wav_pcm"));
        assert_eq!(meta["channels"], json!(2));
        assert_eq!(meta["sample_rate"], json!(44100));
        assert_eq!(meta["duration_ms"], json!(500));
    }

    #[test]
    fn rejects_invalid_wav_attributes() {
        // Unsupported sample rate
        let bad_rate = create_test_wav(22050, 1, 0.5, 440.0);
        assert_eq!(
            parse_wave(&bad_rate),
            Err(SoundError::UnsupportedSampleRate)
        );

        // Corrupt header
        let corrupt = b"NOT_A_WAV_HEADER_AT_ALL_JUST_RANDOM_TEXT_HERE_1234";
        assert_eq!(parse_wave(corrupt), Err(SoundError::InvalidWave));
    }

    #[test]
    fn imports_and_persists_custom_sound() {
        let temp = std::env::temp_dir().join(format!("sounds-test-{}", uuid::Uuid::new_v4()));
        let bundled = temp.join("bundled");
        let custom = temp.join("custom");
        fs::create_dir_all(&bundled).unwrap();

        let sounds = Sounds::with_custom(&bundled, &custom);
        let wav = create_test_wav(48000, 1, 1.0, 520.0);

        let mut hasher = Sha256::new();
        hasher.update(&wav);
        let digest = hex::encode(hasher.finalize());

        let result = sounds.import("rain_storm", &wav, &digest).unwrap();
        assert_eq!(result["id"], "rain_storm");
        assert_eq!(result["sample_rate"], 48000);
        assert_eq!(result["duration_ms"], 1000);

        assert!(sounds.available("rain_storm"));
        let listed = sounds.list();
        assert!(listed.iter().any(|s| s["id"] == "rain_storm"));

        // Base64 import
        let b64 = BASE64_STANDARD.encode(&wav);
        let result2 = sounds.import_base64("ocean_waves", &b64, &digest).unwrap();
        assert_eq!(result2["id"], "ocean_waves");
        assert!(sounds.available("ocean_waves"));
    }
}
