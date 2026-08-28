# 40-002 — Bed-Exit Detection

## Purpose

Determine whether the bed region is occupied, vacant, or indeterminate from a
fixed infrared camera, without facial recognition.

## MVP strategy

The first algorithm favors explainability and low CPU cost:

1. crop to the bed polygon and mask areas outside it;
2. apply limited brightness normalization;
3. compare against a calibrated nighttime background model;
4. extract motion and foreground mass;
5. apply temporal smoothing;
6. classify as `occupied`, `vacant`, or `unknown` with confidence.

A pose model or neural network is not required for the MVP. One may be added
behind the same contract only if validation data shows that the classical
approach is inadequate on Raspberry Pi 3.

## Inputs and outputs

Input: grayscale frame, calibrated region, camera quality, and profile settings.

`BedObservation` output:

| Field | Description |
|---|---|
| `state` | `occupied`, `vacant`, or `unknown` |
| `confidence` | 0.0–1.0, calibrated per class |
| `motion_score` | normalized motion inside the region |
| `foreground_ratio` | share of region differing from background |
| `quality` | input quality |
| `captured_at_monotonic` | source-frame instant |
| `profile_revision` | calibration used |

## Decision rules

- `unusable` quality always yields `unknown`.
- Obstruction, strong saturation, or a sudden framing change yields `unknown`,
  never `vacant`.
- The background is not learned during a wake session.
- Outside a session, the background is updated only during stable windows judged
  vacant; it is stored as derived parameters, not as a reconstructable image.
- Temporal confirmation belongs to `WakeSession`, not to the detector.

## Calibration and ground truth

The validation set covers at least: empty bed, motionless person under a duvet,
movement, partial exit, full exit, return to bed, another person crossing the
image, pet, visible light switched on, IR switched off, covered camera, and a
moved object. Sequences are interval-annotated without identity.

## Success metrics

- complete-exit recall at least 95% on validation scenes;
- false dismissal while occupied at most 1 per 100 simulated sessions;
- prefer `unknown` over a false vacancy;
- average pipeline CPU at most 60% of one Pi 3-equivalent core at 5 frames/s;
- additional memory at most 80 MiB.

These are prototype targets and must be recalibrated on real hardware. False
dismissal is the primary metric.

## Settings

The region, thresholds, and background model form a versioned `DetectionProfile`.
Only bounded parameters are editable through the advanced interface. Restoring
recommended defaults is always available.

## Requirements

- `VIS-001` — No function shall identify a face or user.
- `VIS-002` — Unusable input shall produce `unknown`.
- `VIS-003` — The detector shall not confirm alarm dismissal itself.
- `VIS-004` — Areas outside the bed region shall not affect occupancy score.
- `VIS-005` — Every observation shall identify its profile revision.
- `VIS-006` — Thresholds shall be evaluated on a versioned dataset.
- `VIS-007` — The pipeline shall apply backpressure and discard stale frames.

## Acceptance criteria

A reproducible report provides the confusion matrix, false dismissals by scenario,
decision time, CPU/memory, and list of `unknown` cases. Every new algorithm
version is compared with the baseline using identical fixtures.

