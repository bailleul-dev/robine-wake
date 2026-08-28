# Requirements Traceability

Audit date: 2026-08-20

This matrix records the evidence available for every numbered requirement in
the specification set. It deliberately does not treat a successful firmware
build as evidence for electrical, acoustic, optical, endurance, or rollback
behavior that can only be measured on the intended device.

Status meanings:

- **Verified**: covered by source inspection plus an automated host check.
- **Implemented**: present in software, but final target evidence is pending.
- **Partial**: useful behavior exists, but the full stated requirement is not
  yet proved.
- **Hardware pending**: requires the selected physical assembly.
- **Deferred**: explicitly outside the current software MVP.

## Architecture

| ID | Status | Evidence or remaining proof |
|---|---|---|
| ARCH-001 | Implemented | Scheduler has no network dependency; offline target boot remains `VAL-HW-001`. |
| ARCH-002 | Verified | Clock, audio, camera, network, and persistence access are isolated in boundary modules; host adapters are exercised by the suite. |
| ARCH-003 | Verified | `unknown`, stale, malformed, and missing camera observations never dismiss a session. |
| ARCH-004 | Verified | Wake-session confirmation, snooze, ramp, and audible duration use `Clock.monotonic_ms/0`. |
| ARCH-005 | Verified | Alarm occurrences and persisted instants use UTC plus an explicit IANA zone. |
| ARCH-006 | Verified | `EventLog` events include event, session, and alarm identifiers; wake-session tests inspect correlation. |
| ARCH-007 | Verified | Clock, scheduler, storage, audio, camera, authentication, network, and firmware slot/validation state appear in health. |

## Nerves platform

| ID | Status | Evidence or remaining proof |
|---|---|---|
| NRV-001 | Verified | `mix verify` runs on `host` without Raspberry Pi access. |
| NRV-002 | Verified | Locked dependencies, fixed source epoch, and `MIX_TARGET=rpi3 mix firmware` produce the image without edits. |
| NRV-003 | Verified | Alarm, detection-profile, auth, and runtime integer inputs are validated before use. |
| NRV-004 | Implemented | Missing camera/network and exhausted audio retries produce degraded or failed-safe states; physical adapter failures remain to be injected on target. |
| NRV-005 | Implemented | Nerves A/B slot status and `StartupGuard` validation/rollback are enabled; a target rollback drill is still required. |
| NRV-006 | Verified | Target configuration contains no administrator password; exports/events filter sensitive fields. |
| NRV-007 | Verified | `ClockQuality` is in health and prevents automatic arming until confirmed on target. |

## Hardware profile

| ID | Status | Evidence or remaining proof |
|---|---|---|
| HW-001 | Hardware pending | Illuminator circuit and power source have not been selected. |
| HW-002 | Verified | A physical Amp2 was detected by stable HiFiBerry name and selected as `plughw:0`; stereo playback was confirmed on 2026-08-20. |
| HW-003 | Partial | Amp2/I²S and the Raspberry Pi 3 B+ are verified. APKLVSR V0348/OV5647 over dedicated 15-pin CSI remains the camera candidate; RTC/button decisions, electrical measurements, and the final wiring diagram remain pending. |
| HW-004 | Hardware pending | Software supports a bounded bed ROI; installed camera framing requires bedroom validation. |
| HW-005 | Verified | Camera loss leaves audio and authenticated manual dismissal operational. |
| HW-006 | Hardware pending | Requires measured peak current and a selected supply. |

## Alarm scheduling

| ID | Status | Evidence or remaining proof |
|---|---|---|
| ALM-001 | Verified | Scheduler maintains one occurrence per enabled alarm. |
| ALM-002 | Verified | Persisted `(alarm_id, scheduled_for)` prevents duplicate sessions; 10,000 recalculations are duplicate-free. |
| ALM-003 | Verified | Unit tests cover European DST gap and ambiguity rules. |
| ALM-004 | Verified | Revisioned updates synchronously persist, then rebuild the scheduler map. |
| ALM-005 | Verified | A one-shot alarm is disabled after its session is created. |
| ALM-006 | Verified | Due, expired, restart-style refresh, and ten-minute clock-jump paths exercise catch-up and `missed` history. |
| ALM-007 | Verified | An untrusted clock leaves the schedule visible but `armed: false`. |
| ALM-008 | Verified | Alarm parsing and settings validation persist and independently validate `sound_id` and `strong_sound_id`; legacy alarms receive the default strong sound. |

## Wake session

| ID | Status | Evidence or remaining proof |
|---|---|---|
| SES-001 | Verified | Session persistence completes before `Audio.play/2`. |
| SES-002 | Verified | Repeated snooze in the same snoozed state and repeated dismissal are successful no-ops. |
| SES-003 | Verified | Missing/unknown frames cannot create `bed_exit_confirmed`. |
| SES-004 | Verified | Vacancy requires the startup grace and continuous monotonic confirmation. |
| SES-005 | Verified | A reliable occupied observation cancels the candidate. |
| SES-006 | Verified | Snooze count and a future snooze UTC deadline survive recovery. |
| SES-007 | Verified | Completion writes one terminal state, reason, and timestamp. |
| SES-008 | Verified | Wake-session tests advance the ramp to completion and assert one switch from the gentle sound to the configured strong sound at ceiling gain. |

## Audio

| ID | Status | Evidence or remaining proof |
|---|---|---|
| AUD-001 | Verified | A different session cannot replace or stop active audio. |
| AUD-002 | Verified | Alarm validation and `Audio` enforce the independent safety ceiling of 80; pure mapping tests prove the Amp2 curve reaches no more than -15 dB. |
| AUD-003 | Hardware pending | Software starts synchronously after persistence; sub-500 ms HiFiBerry latency must be measured. |
| AUD-004 | Verified | User WAV files require PCM 44.1/48 kHz, 16-bit structure, a 5 MB limit, SHA-256 match, atomic publication, and measured peak metadata; bundled files are immutable release assets with manifest digests. |
| AUD-005 | Verified | Repeated valid gain and stop operations are safe. |
| AUD-006 | Verified | Injected failures prove immediate attempt, three retries, and final visible error. |
| AUD-007 | Verified | Host driver records commands and emits no sound. |
| AUD-008 | Verified | One resolver exposes generated/default WAV, validated custom WAV, and five manifest-backed bundled MP3 tracks, including the recorded storm meditation ambience; both a gentle and a strong MP3 played through target `mpg123` and HiFiBerry ALSA. |
| AUD-009 | Verified | ALSA playback runs under `MuonTrap.Daemon`; target gentle-to-strong replacement and final stop left no `mpg123` process and returned AirPlay to `available`. |

## AirPlay receiver

| ID | Status | Evidence or remaining proof |
|---|---|---|
| APY-001 | Verified | Shairport Sync is embedded and supervised; macOS `dns-sd` discovered `CC1323229925@Robine Wake Bedroom` and TCP 5000 accepted connections on the target. End-to-end source playback remains part of acoustic acceptance. |
| APY-002 | Verified | Automated tests cover alarm ownership, and a target suspend/resume drill removed the Shairport process completely before returning with a new PID in under 750 ms. |
| APY-003 | Implemented | The receiver uses the HiFiBerry `plughw:0` output and `Digital` hardware mixer; target AirPlay playback remains to be confirmed. |
| APY-004 | Implemented | Shairport Sync caps hardware gain at -20 dB, resets idle sessions to -30 dB, and treats -24 dB as the high-volume threshold; acoustic calibration remains pending. |
| APY-005 | Verified | Forcibly terminating target PID 209 produced a healthy replacement at PID 226 after the configured two-second recovery delay without restarting the BEAM. |
| APY-006 | Verified | Host builds disable the receiver and require no Shairport executable or network service. |
| APY-007 | Deferred | AirPlay 2 requires the separate Avahi, NQPTP, FFmpeg, resource, and compatibility validation described in `30/002-airplay-receiver`. |

## Infrared camera

| ID | Status | Evidence or remaining proof |
|---|---|---|
| CAM-001 | Verified | Target adapter returns only 8-bit grayscale luminance. |
| CAM-002 | Verified | Frames and observations carry a monotonic timestamp. |
| CAM-003 | Verified | No normal camera code writes pixels; diagnostics reject pixel/image/frame fields. |
| CAM-004 | Verified | Analysis becomes degraded after 2,000 ms without a fresh frame. |
| CAM-005 | Implemented | Camera is independently supervised and recovery does not own or restart sessions; target recovery needs soak testing. |
| CAM-006 | Verified | Resolution, ROI, and bounded thresholds are rejected when incompatible. |
| CAM-007 | Verified | Capture is serialized, duplicate/stale frames are discarded, and histories are bounded. |

## Bed-exit detection

| ID | Status | Evidence or remaining proof |
|---|---|---|
| VIS-001 | Verified | No identity, face, pose, or biometric code/dependency exists. |
| VIS-002 | Verified | Unusable/malformed input always yields `unknown`. |
| VIS-003 | Verified | Detector emits observations only; `WakeSession` owns temporal dismissal. |
| VIS-004 | Verified | Rectangle and polygon tests prove outside pixels do not affect occupancy. |
| VIS-005 | Verified | Every observation includes a detection-profile revision. |
| VIS-006 | Hardware pending | The annotated nighttime dataset and confusion matrix require the selected camera and bedroom scenes. |
| VIS-007 | Implemented | Stale frames are discarded and capture is serialized; Pi CPU/backpressure metrics need hardware endurance evidence. |

## Local interface

| ID | Status | Evidence or remaining proof |
|---|---|---|
| UI-001 | Verified | Browser UI creates/edits all essential alarm fields without IEx. |
| UI-002 | Verified | CSRF-protected preview returns five local/UTC-aware occurrences without persisting. |
| UI-003 | Implemented | Health identifies capability and reason; final user-impact wording awaits physical failure review. |
| UI-004 | Verified | No video or image endpoint exists. |
| UI-005 | Verified | Patch and delete require the current resource revision. |
| UI-006 | Implemented | Actions return synchronously and refresh immediately; target p95 must be measured. |
| UI-007 | Verified | API/exports exclude credentials and camera data. |
| UI-008 | Verified | The native dialog editor presents schedule, both sound stages, ramp, dismissal, and snooze controls in one responsive, keyboard-operable form. |

## HTTP Model Context Protocol

| ID | Status | Evidence or remaining proof |
|---|---|---|
| MCP-001 | Verified | MCP tests cover initialization, version negotiation, capability declaration, discovery, and unsupported versions. |
| MCP-002 | Verified | Router tests require the provisioned administrator credentials before dispatch. |
| MCP-003 | Verified | Router tests accept same-origin/native requests and reject a cross-origin request. |
| MCP-004 | Verified | Tool tests create, update, conflict, and delete through `Settings` with resource revisions. |
| MCP-005 | Verified | The finite tool mapping returns only health, domain configuration, sound metadata, and session state; no pixel or credential source is exposed. |
| MCP-006 | Verified | Unknown tools return JSON-RPC invalid-parameter errors, while domain revision conflicts return tool results with `isError: true`. |
| MCP-007 | Implemented | The implementation uses existing Plug/Jason dependencies shared by host and target; target interoperability remains to be exercised with an external client. |
| MCP-008 | Verified | Router tests enforce the configured per-peer request ceiling and return HTTP 429 with `Retry-After`. |

## Data and privacy

| ID | Status | Evidence or remaining proof |
|---|---|---|
| DAT-001 | Verified | Camera backgrounds remain in memory only. |
| DAT-002 | Verified | Session retention runs at Settings boot and every 24 hours; 31-day purge is tested. |
| DAT-003 | Partial | Version 1 writes are atomic, unknown schemas are rejected, and failed serialization preserves the previous file; no pre-v1 production schema exists, and power-cut fault injection is still required. |
| DAT-004 | Verified | Configuration and diagnostic exports contain no credential, token, or pixels. |
| DAT-005 | Verified | RingLogger/EventLog are size-bounded and structured events expire after seven days. |
| DAT-006 | Deferred | Temporary visual diagnostic capture is not exposed in this MVP. |
| DAT-007 | Verified | Confirmed factory reset clears settings, sessions, profile, telemetry, and stored credential, then returns to setup. |

## Operations and updates

| ID | Status | Evidence or remaining proof |
|---|---|---|
| OPS-001 | Verified | Core capabilities and Nerves firmware validation/slot state publish explainable health. |
| OPS-002 | Verified | Events/logs are bounded and structured events have tested seven-day expiry; target saturation remains an endurance check. |
| OPS-003 | Verified | Diagnostic export has five virtual files, per-file SHA-256/size manifest, and privacy inspection tests. |
| OPS-004 | Implemented | SSH requires an authorized key and Fwup requires the embedded Ed25519 public key; a signed archive verifies and the unsigned build is rejected. Hardware installation remains pending. |
| OPS-005 | Verified | `UpdatePolicy` refuses installation with an active session, untrusted clock, or next alarm within 15 minutes. |
| OPS-006 | Implemented | Nerves A/B updates, `StartupGuard`, firmware validation state, and ten-minute heart handshake are configured; target rollback drill remains pending. |
| OPS-007 | Verified | Redacted critical events are persisted in a 100-entry journal and reload after a controlled restart. |

## Simulation and validation

| ID | Status | Evidence or remaining proof |
|---|---|---|
| TST-001 | Verified | Domain tests use `Clock.Manual`; no scenario sleeps for domain time. |
| TST-002 | Verified | This matrix links every numbered requirement to evidence/status; `mix verify` is the single host gate. |
| TST-003 | Partial | Connected LiveView tests inject audio, camera, time, and network conditions through the Hardware Lab; corrupt-schema and failed-write paths are also automated, while disk-full and target power-cut injection remain pending. |
| TST-004 | Verified | Synthetic detector inputs and fixed ExUnit seeds reproduce vision decisions. |
| TST-005 | Hardware pending | Validation record cannot exist before the selected assembly is available. |
| TST-006 | Verified | Repository fixtures are synthetic and contain no bedroom imagery. |

## MVP delivery gates

| Gate | Current result |
|---|---|
| Host P0 suite | Passes through `mix verify`. |
| State machines and critical errors | Covered by scheduler, wake-session, recovery, audio-failure, clock-quality, and privacy tests. |
| Duplicate trigger property | 10,000 occurrence sequence plus per-occurrence persistence protection pass. |
| No pixels persisted in normal mode | Proven by code path and export/event inspection tests; target data-partition inspection remains part of hardware validation. |
| `VAL-HW-001` through `VAL-HW-006` | Audio bring-up passed on Raspberry Pi 3 B+ and HiFiBerry Amp2; camera, electrical-margin, acoustic-limit, and endurance records remain open. |
| False-dismissal target evaluated | **Not run: annotated real scenes are not available.** |
| Manual dismissal with camera/network disconnected | Software simulation passes; physical control/network test remains pending. |

The full product MVP therefore remains open until the hardware delivery gates
pass. The host software gate and build gate are reproducible today.
