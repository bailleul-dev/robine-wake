# Robine Wake

[![build](https://ci.base59.dev/badges/github/laibulle/robine-wake/build.svg)](https://ci.base59.dev/repositories)
[![coverage](https://ci.base59.dev/badges/github/laibulle/robine-wake/coverage.svg)](https://ci.base59.dev/repositories)

Robine Wake is a privacy-first smart alarm clock for Raspberry Pi 3, Nerves,
and HiFiBerry, with a planned DIY bed-vibration channel for breathing, music
and progressive waking. The MVP runs fully on `host` with simulated
hardware, while preserving target adapters for the real device.

The product scope was updated on 2026-09-06: camera and bed-presence features are
removed. Their existing implementation still needs removal; the tactile extension
is specified but not implemented. See the
[bed-vibration specification](docs/specs/30/004-bed-vibration/spec.md) and the
[scope and migration status](docs/MVP_STATUS.md).

## Run on a development computer

Copy the public environment template once. The resulting `.env` is ignored by
Git and is loaded automatically by the Make targets and release scripts:

```sh
cp .env.dist .env
```

The host build does not require any private value. Leave optional entries empty
when they do not apply to your setup.

If a credential was committed before this setup existed, moving it to `.env`
does not remove it from Git history. Rotate that credential and either publish
from a fresh history or purge the old objects before making the repository
public.

```sh
mix deps.get
mix verify
mix run --no-halt
```

`mix verify` checks formatting, compiles with warnings treated as errors, runs
Credo in strict mode, audits Hex dependencies, and runs the complete host suite.
ExCoveralls enforces 67% production-code coverage and writes the browsable report
to `cover/excoveralls.html`; test-support modules are excluded from the metric.
The command also writes the scenario and requirements summary to
`cover/mvp-report.json`.

The individual quality checks are available while iterating:

```sh
mix credo --strict
mix coveralls
mix coveralls.html
```

Open <http://localhost:4110>. The local web interface has no login or password.
The HTTP port can be changed with `ROBINE_WEB_PORT`.

An MCP Streamable HTTP endpoint is available at
`http://localhost:4110/mcp`. It exposes device state and revision-safe alarm and
wake-session tools. Configure the client on the trusted local network and see
the [HTTP MCP specification](docs/specs/50/002-http-mcp/spec.md) for the complete
contract and security profile.

The host build also starts a Phoenix LiveView Hardware Lab at
<http://127.0.0.1:4111>. It emulates HiFiBerry availability and failures, network
loss, clock trust,
deterministic time advancement, alarms, snooze, and dismissal through the real
domain processes. Existing camera simulation controls are legacy functionality
scheduled for removal; tactile simulation is specified and remains to be added.
Change its port with `ROBINE_DEV_PORT`. The laboratory is loopback-only and its
Phoenix/LiveView code is excluded from Raspberry Pi compilation. See the
[host hardware emulator specification](docs/specs/80/002-host-hardware-emulator/spec.md).

### Demo mode

The same server can run as a public demo on a standard server, with the
hardware emulated: the product web app and a photoreal 3D bedroom (the sound
bar, its lights, the bedside remote, the sound) side by side at `/demo`. Every
action goes through the real server logic, routed to emulated drivers, with an
accelerated clock to watch a dawn in a few minutes.

```sh
ROBINE_DEMO=1 ROBINE_DEMO_ACCESS_CODE=change-me mix run --no-halt
open http://localhost:8080/demo
```

With Docker (set `ROBINE_DEMO_ACCESS_CODE` in `.env`):

```sh
docker compose up -d --build
```

The image uses the committed web build in `priv/web`; run `make expo-web`
first to refresh it. See the
[demo deployment section](docs/specs/80/002-host-hardware-emulator/spec.md#demo-deployment).

The Raspberry Pi web interface is intentionally passwordless and intended only
for the trusted local network. Firmware updates and SSH remain authenticated.

## Run the iOS Bluetooth prototype

> The BLE control service is disabled on the Raspberry Pi firmware: the onboard
> controller now serves the [Bluetooth audio receiver](docs/specs/30/005-bluetooth-audio-receiver/spec.md).
> On the device, the app only reaches the clock over Wi-Fi.

The SwiftUI application is generated with XcodeGen. Its prototype local-control
protocol is intentionally unauthenticated and should only be used for feature
testing.

```sh
cd ios/RobineWake
xcodegen generate
open RobineWake.xcodeproj
```

The first Bluetooth connection discovers the clock's local HTTP endpoint and
persists it on the iPhone. Later commands prefer the faster HTTP transport and
automatically retry the same idempotent request over Bluetooth when Wi-Fi is not
available. A replayable Server-Sent Events stream pushes alarm and state changes;
the app does not poll the clock on a timer. The app connects to the first nearby
`Robine Wake` peripheral. Its native
morning dashboard, alarm journey editor, sound library, session controls, and
system view mirror the functional language of the
LiveView application. Use a physical iPhone for BLE testing; the iOS Simulator
build only validates compilation and UI integration.

The stable versioned command envelope, GATT UUIDs, paged response header, CRC32
validation, compatibility rules, and supported operations are documented in the
[Bluetooth v1 contract](docs/bluetooth/v1.md).

## Connect Philips Hue

Robine Wake controls a Philips Hue Bridge directly over the local network; no Hue
cloud account or remote API is used by the firmware. In the iOS app, open the
`Réveil` tab, allow local-network discovery, press the round button on the Hue
Bridge, and select the bridge found automatically through Bonjour. Manual address
entry remains available as a fallback. Rooms and zones then become available in
each alarm under `Lever de lumière`.

Each alarm can choose its Hue target, initial and final brightness, transition
duration, and whether dismissal restores the previous state, turns the target
off, or leaves the final light active. Snooze turns the selected target off and
resuming the alarm starts the transition again. Hue failures are logged as a
degraded accessory event and never prevent the local audio alarm from running.

The bridge application key is stored only in the device's persistent local
configuration. Configuration exports omit Hue credentials.

## Build for Raspberry Pi 3

```sh
make firmware
```

Without Wi-Fi values in `.env`, the firmware still builds and uses Ethernet
only. Set `ROBINE_WIFI_SSID` and `ROBINE_WIFI_PASSPHRASE` to provision Wi-Fi in
your local image.

Production updates are accepted only when signed by the Ed25519 key whose
public half is embedded in the firmware. The private half is intentionally
kept outside the repository. Build and verify a signed update with:

```sh
scripts/build_signed_firmware.sh
```

For a headless first boot, provide the WPA2 network only while building. The
credentials are embedded in the resulting device image but are never written
to the repository or printed by the build:

```sh
cp .env.dist .env
# Fill ROBINE_WIFI_* and ROBINE_FWUP_PRIVATE_KEY in .env, then:
scripts/build_signed_firmware.sh
```

After flashing and booting, open `http://robine-wake.local:4000/`. Raspberry Pi
3 models without dual-band Wi-Fi must use a 2.4 GHz network.

On this development machine the generated private key is stored with mode
`0600` under `~/.config/robine-wake/`; back it up securely before relying on it
for deployed devices. Updates are refused while a wake session is active, when
the clock is untrusted, or within 15 minutes of the next alarm. Nerves then
uses its inactive A/B slot and startup validation guard.

The HiFiBerry Amp2 is validated as `plughw:0` with the
`hifiberry-dacplus` Device Tree overlay. Target firmware also advertises
`Robine Wake Bedroom` as a classic AirPlay receiver. An alarm always preempts
an active stream and the receiver returns after alarm playback ends. Each alarm
selects two sounds: a progressive wake track and a strong fallback track that
starts if the gentle ramp completes without dismissal. Curated MP3 assets and
their manifest live in `priv/sounds`; validated custom WAV files remain under
the persistent `/data/sounds` directory. The DIY tactile assembly and its firmware
integration remain validation items. See
[the specifications](docs/specs/README.md) and
[the MVP implementation status](docs/MVP_STATUS.md). The
[requirements matrix](docs/REQUIREMENTS_TRACEABILITY.md) records verified,
partial, deferred, and hardware-dependent requirements individually.

### Arrêt du réveil

L’arrêt depuis l’iPhone et le web est désactivé côté réveil : le bouton physique
reste disponible. Le réglage distant est verrouillé, y compris lorsqu’une ancienne
préférence autorisait l’arrêt depuis le smartphone. La fonctionnalité est conservée
et peut être réactivée dans le firmware avec `remote_dismiss_enabled: true` dans
`config/config.exs`.
