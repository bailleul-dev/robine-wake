# Requirements Traceability

Baseline evidence audit: 2026-08-20. Scope/requirements update: 2026-09-06.

The camera-free and tactile requirements below have not been implemented or
retested by this documentation update. Unchanged evidence describes the earlier
audit; it is not a fresh verification of the current working tree. Retired
requirements no longer count toward delivery gates. Changed requirements must
be revalidated against their new scope.

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
- **Retired**: removed from the product; ID reserved for historical reports.
- **Specified**: acceptance requirement documented; implementation/evidence pending.
- **Not audited**: existing requirement newly inventoried; implementation evidence
  was not assessed in the earlier matrix or this documentation update.
- **Revalidation required**: previous evidence does not establish the revised contract.

## Architecture

| ID | Status | Evidence or remaining proof |
|---|---|---|
| ARCH-001 | Implemented | Scheduler has no network dependency; offline target boot remains `VAL-HW-001`. |
| ARCH-002 | Partial | Existing boundaries are exercised; the new tactile adapter remains to be implemented and tested. |
| ARCH-003 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| ARCH-004 | Partial | Existing session timing uses a monotonic clock; tactile timing and removal of presence timers remain to be verified. |
| ARCH-005 | Verified | Alarm occurrences and persisted instants use UTC plus an explicit IANA zone. |
| ARCH-006 | Verified | `EventLog` events include event, session, and alarm identifiers; wake-session tests inspect correlation. |
| ARCH-007 | Revalidation required | Camera-free health and the new tactile capability remain to be implemented. |

## Nerves platform

| ID | Status | Evidence or remaining proof |
|---|---|---|
| NRV-001 | Verified | `mix verify` runs on `host` without Raspberry Pi access. |
| NRV-002 | Verified | Locked dependencies, fixed source epoch, and `MIX_TARGET=rpi3 mix firmware` produce the image without edits. |
| NRV-003 | Revalidation required | Legacy presence migration and tactile calibration validation are newly specified. |
| NRV-004 | Revalidation required | Revised 2026-09-06; previous evidence does not cover the new contract. See `docs/specs/10/001-nerves-platform/spec.md`. |
| NRV-005 | Implemented | Nerves A/B slot status and `StartupGuard` validation/rollback are enabled; a target rollback drill is still required. |
| NRV-006 | Verified | Target configuration contains no administrator password; exports/events filter sensitive fields. |
| NRV-007 | Verified | `ClockQuality` is in health and prevents automatic arming until confirmed on target. |

## Hardware profile

| ID | Status | Evidence or remaining proof |
|---|---|---|
| HW-001 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| HW-002 | Partial | Amp2 bring-up passed in the earlier audit; any additional audio device is optional and needs stable addressing if selected. |
| HW-003 | Partial | Amp2 is verified; final button/RTC and tactile wiring require conflict review. Camera/IR choices are retired. |
| HW-004 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| HW-005 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
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
| SES-001 | Revalidation required | Existing persistence precedes audio; this must also precede newly specified tactile side effects. |
| SES-002 | Revalidation required | Explicit controls must also be idempotent for tactile ownership and shutdown. |
| SES-003 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| SES-004 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| SES-005 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
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
| APY-003 | Partial | Existing direct HiFiBerry path is implemented; the simplified tactile energy-envelope extraction is specified only. |
| APY-004 | Implemented | Shairport Sync attenuates in software under the 0 dB hardware music level kept by `RobineWake.Audio`, resets idle sessions to -7.5 dB (75 %), and treats -3 dB as the high-volume threshold; acoustic calibration remains pending. |
| APY-005 | Verified | Forcibly terminating target PID 209 produced a healthy replacement at PID 226 after the configured two-second recovery delay without restarting the BEAM. |
| APY-006 | Verified | Host builds disable the receiver and require no Shairport executable or network service. |
| APY-007 | Partial | AirPlay 2 is enabled (Shairport Sync with Avahi and NQPTP, supervised by `RobineWake.AirPlay`) and advertised on the network; resource, compatibility, and overnight timing evidence is pending. |

## Bluetooth audio receiver

| ID | Status | Evidence or remaining proof |
|---|---|---|
| BTA-001 | Implemented | BlueZ `main.conf` makes the onboard controller always discoverable and pairable; `bluetoothctl --agent auto` accepts requests. Target pairing with a phone is pending. |
| BTA-002 | Implemented | `RobineWake.Audio` suspends and resumes every configured music receiver; suspend stops `bluealsa-aplay`. Target alarm-during-stream drill is pending. |
| BTA-003 | Verified | A receiver that exits or raises on suspend and resume is logged and skipped while wake audio plays and stops (`audio_test.exs`). |
| BTA-004 | Implemented | The player uses BlueALSA software volume under the `0.0 dB` Amp2 music level, which only `RobineWake.Audio` writes (restored at boot and after each alarm, `audio_test.exs`); acoustic calibration is pending. |
| BTA-005 | Implemented | `bluealsa` runs with `--profile=a2dp-sink` and AAC, aptX and aptX HD codecs built from FDK AAC and libopenaptx; target codec negotiation is pending. |
| BTA-006 | Implemented | Stack exits restart the whole stack and player exits restart the player after the configured delay; host tests cover missing executables. Target kill drill is pending. |
| BTA-007 | Implemented | The onboard controller moves to the PL011 UART under `hci_uart`; BlueHeron is disabled and built with `runtime: false`. Target Bluetooth/Wi-Fi coexistence check is pending. |
| BTA-009 | Implemented | BlueALSA 5.0.0 (`package/bluez-alsa5`) reports codec, processing and player delay to BlueZ, which forwards it to the phone. On target 2026-10-02, `bluealsa-aplay` reported a 151.6 ms client delay with aptX from a Galaxy S25, and YouTube stayed lip-synced, with instant seeking. |
| BTA-008 | Verified | Host builds disable the receiver; an enabled receiver without its executables keeps retrying without crashing (`bluetooth_audio_test.exs`). |

## Infrared camera — retired

| ID | Status | Evidence or remaining proof |
|---|---|---|
| CAM-001 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| CAM-002 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| CAM-003 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| CAM-004 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| CAM-005 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| CAM-006 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| CAM-007 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |

## Bed-exit detection — retired

| ID | Status | Evidence or remaining proof |
|---|---|---|
| VIS-001 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| VIS-002 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| VIS-003 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| VIS-004 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| VIS-005 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| VIS-006 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| VIS-007 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |

## Local interface

| ID | Status | Evidence or remaining proof |
|---|---|---|
| UI-001 | Partial | Earlier editor exists; new tactile configuration and removal of presence controls remain pending. |
| UI-002 | Verified | CSRF-protected preview returns five local/UTC-aware occurrences without persisting. |
| UI-003 | Implemented | Health identifies capability and reason; final user-impact wording awaits physical failure review. |
| UI-004 | Verified | No video or image endpoint exists. |
| UI-005 | Verified | Patch and delete require the current resource revision. |
| UI-006 | Implemented | Actions return synchronously and refresh immediately; target p95 must be measured. |
| UI-007 | Verified | API/exports exclude credentials and camera data. |
| UI-008 | Revalidation required | Alarm editor must follow manual-only dismissal and include the separately bounded tactile profile. |

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
| DAT-001 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| DAT-002 | Verified | Session retention runs at Settings boot and every 24 hours; 31-day purge is tested. |
| DAT-003 | Partial | Existing atomic writes are baseline evidence; camera-free legacy-policy/profile migration still needs implementation. |
| DAT-004 | Verified | Configuration and diagnostic exports contain no credential, token, or pixels. |
| DAT-005 | Verified | RingLogger/EventLog are size-bounded and structured events expire after seven days. |
| DAT-006 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| DAT-007 | Verified | Confirmed factory reset clears settings, sessions, profile, telemetry, and stored credential, then returns to setup. |

## Operations and updates

| ID | Status | Evidence or remaining proof |
|---|---|---|
| OPS-001 | Revalidation required | Remove camera/detector health and add enabled tactile-failure reporting. |
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
| TST-002 | Partial | The matrix inventories requirements; new camera-removal and tactile acceptance tests are not yet linked or run. |
| TST-003 | Revalidation required | Revised 2026-09-06; previous evidence does not cover the new contract. See `docs/specs/80/001-simulation-validation/spec.md`. |
| TST-004 | Retired | Removed 2026-09-06; retained ID, no active acceptance work. |
| TST-005 | Hardware pending | Validation record cannot exist before the selected assembly is available. |
| TST-006 | Verified | Repository fixtures are synthetic and contain no bedroom imagery. |

## Requirements added to the matrix on 2026-09-06

These entries include new requirements and existing requirements omitted from the
earlier matrix. Their status does not claim completed implementation or testing.

### [001-system-architecture](specs/00/001-system-architecture/spec.md)

| ID | Status | Evidence or remaining proof |
|---|---|---|
| ARCH-008 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| ARCH-009 | Specified | Implementation and acceptance evidence pending; see linked specification. |

### [002-gentle-awakening-mechanisms](specs/00/002-gentle-awakening-mechanisms/spec.md)

| ID | Status | Evidence or remaining proof |
|---|---|---|
| GWA-001 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| GWA-002 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| GWA-003 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| GWA-004 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| GWA-005 | Retired | Removed from scope; ID reserved. |
| GWA-006 | Retired | Removed from scope; ID reserved. |
| GWA-007 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| GWA-008 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| GWA-009 | Retired | Removed from scope; ID reserved. |
| GWA-010 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| GWA-011 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| GWA-012 | Specified | Implementation and acceptance evidence pending; see linked specification. |

### [002-hardware-profile](specs/10/002-hardware-profile/spec.md)

| ID | Status | Evidence or remaining proof |
|---|---|---|
| HW-007 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| HW-008 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| HW-009 | Specified | Implementation and acceptance evidence pending; see linked specification. |

### [001-alarm-scheduling](specs/20/001-alarm-scheduling/spec.md)

| ID | Status | Evidence or remaining proof |
|---|---|---|
| ALM-009 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| ALM-010 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| ALM-011 | Specified | Implementation and acceptance evidence pending; see linked specification. |

### [002-wake-session](specs/20/002-wake-session/spec.md)

| ID | Status | Evidence or remaining proof |
|---|---|---|
| SES-009 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| SES-010 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| SES-011 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| SES-012 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| SES-013 | Specified | Implementation and acceptance evidence pending; see linked specification. |

### [002-airplay-receiver](specs/30/002-airplay-receiver/spec.md)

| ID | Status | Evidence or remaining proof |
|---|---|---|
| APY-008 | Specified | Implementation and acceptance evidence pending; see linked specification. |

### [003-guided-breathing](specs/30/003-guided-breathing/spec.md)

| ID | Status | Evidence or remaining proof |
|---|---|---|
| BRTH-001 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| BRTH-002 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| BRTH-003 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| BRTH-004 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| BRTH-005 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| BRTH-006 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| BRTH-007 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| BRTH-008 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| BRTH-009 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| BRTH-010 | Specified | Implementation and acceptance evidence pending; see linked specification. |

### [004-bed-vibration](specs/30/004-bed-vibration/spec.md)

| ID | Status | Evidence or remaining proof |
|---|---|---|
| VIB-001 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-002 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-003 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-004 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-005 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-006 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-007 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-008 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-009 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-010 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-011 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-012 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-013 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-014 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| VIB-015 | Specified | Implementation and acceptance evidence pending; see linked specification. |

### [001-local-interface](specs/50/001-local-interface/spec.md)

| ID | Status | Evidence or remaining proof |
|---|---|---|
| UI-009 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| UI-010 | Specified | Implementation and acceptance evidence pending; see linked specification. |

### [001-data-privacy](specs/60/001-data-privacy/spec.md)

| ID | Status | Evidence or remaining proof |
|---|---|---|
| DAT-008 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| DAT-009 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| DAT-010 | Specified | Implementation and acceptance evidence pending; see linked specification. |

### [001-operations-updates](specs/70/001-operations-updates/spec.md)

| ID | Status | Evidence or remaining proof |
|---|---|---|
| OPS-008 | Specified | Implementation and acceptance evidence pending; see linked specification. |

### [001-simulation-validation](specs/80/001-simulation-validation/spec.md)

| ID | Status | Evidence or remaining proof |
|---|---|---|
| TST-007 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| TST-008 | Specified | Implementation and acceptance evidence pending; see linked specification. |

### [002-host-hardware-emulator](specs/80/002-host-hardware-emulator/spec.md)

| ID | Status | Evidence or remaining proof |
|---|---|---|
| EMU-001 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| EMU-002 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| EMU-003 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| EMU-004 | Retired | Removed from scope; ID reserved. |
| EMU-005 | Retired | Removed from scope; ID reserved. |
| EMU-006 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| EMU-007 | Not audited | Existing requirement newly added to this matrix; implementation and evidence need review. |
| EMU-008 | Specified | Implementation and acceptance evidence pending; see linked specification. |
| EMU-009 | Specified | Implementation and acceptance evidence pending; see linked specification. |

## Active delivery gates — revised 2026-09-06

| Gate | Current result |
|---|---|
| Existing host suite/build evidence | Historical audit above; not rerun for this documentation change. |
| Camera-free startup, health, API/UI and exports | Specified; removal of existing camera/detector integration pending. |
| Manual-only legacy policy and session recovery | Specified; migration and obsolete-event tests pending. |
| Offline audio, explicit physical controls and fixed escalation | Existing software evidence must be rechecked after removal/integration. |
| P0 hardware: `VAL-HW-001`, `VAL-HW-002`, `VAL-HW-006`, `VAL-HW-011`, `VAL-HW-012` | Earlier Pi/Amp2 bring-up is recorded; revised electrical, acoustic, endurance, control and migration gates remain open. |
| P1 tactile: `VAL-HW-008` through `VAL-HW-010`, plus tactile endurance | Specified; hardware assembly, implementation and measurement pending. |
| Former camera, optical and false-bed-exit gates | Retired; no dataset or camera purchase required. |

No retired result may be used as verification for a new tactile requirement.
