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

The public instance runs in the k3s cluster managed by `../silo01`, like the
other apps there. `make docker-build-and-push` builds the image for the
cluster, tagged with the current commit (uncommitted changes are refused), and
pushes it to the registry; `make robine-wake-demo` in `../silo01` runs it and
then rolls the image out to <https://robine-wake-demo.bailleul.dev/demo>.

The Raspberry Pi web interface is intentionally passwordless and intended only
for the trusted local network. Firmware updates and SSH remain authenticated.

## Experimental prototypes

The [`experimental/`](experimental/README.md) directory holds throwaway
evaluation prototypes that are **not part of the product**: they are not built
by `mix verify`, not shipped in the firmware, not deployed in the demo. The
current one is a Rust port of the alarm API used to evaluate a future
Buildroot-based system on custom hardware.

## Website and documentation

The marketing page and the technical documentation (generated from `docs/`) live
in [`website/`](website/README.md), an Astro / Starlight project:
`make site-dev`, `make site-build`.

## Mobile app

The iOS and Android application is the Expo / React Native project, written in
Gleam, in
[`mobile/`](mobile/README.md). `make expo-iphone` installs it on a local iPhone,
`make ios-beta` uploads it to TestFlight and `make play-store` to Google Play.

> The BLE control service is disabled on the Raspberry Pi firmware: the onboard
> controller now serves the [Bluetooth audio receiver](docs/specs/30/005-bluetooth-audio-receiver/spec.md).
> On the device, the app only reaches the clock over Wi-Fi.

The stable versioned command envelope, GATT UUIDs, paged response header, CRC32
validation, compatibility rules, and supported operations are documented in the
[Bluetooth v1 contract](docs/bluetooth/v1.md).

## LED strip

The light comes from a 60-LED WS2812B strip driven by the ESP32 co-processor,
which the Pi commands over UART (`light.program`). No bridge, cloud account or
network light is involved.

- **Dawn.** Each alarm can raise a dawn on the strip over its pre-wake ramp, so
  that full daylight arrives at the alarm time. Snooze turns the strip off and
  resuming starts it again; dismissal turns it off or leaves it lit, per alarm.
- **Evening breathing.** The `Soir` screen starts a guided breathing session at
  a cadence picked from named patterns (or typed in) and a duration: the strip
  breathes while the speaker plays the meditation ambience at the chosen volume. An alarm takes over the strip.
- **Reading light.** On the `Soir` screen, a warm amber at the bottom of the
  vertical strip to read by, orange then red towards the top, for up to 4
  hours, then an optional sunset of up to 2 hours.
- **Ambience.** A program can play a sound along, such as the storm and rain:
  it lowers to silence as the light fades and stops with it.
- **Manual programs.** The same screen starts a sunrise or a sunset of 1 minute
  to 4 hours, or turns the strip off. It also reads the strip back, pixel by
  pixel.

Strip failures are logged and never prevent the local audio alarm from running.

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
`Robine Wake Bedroom` as an AirPlay 2 receiver (`robine-airplayd`). An alarm always preempts
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

## Build for Raspberry Pi Zero W

The `rpi0` target (ARMv6, one core, 512 MB) reuses the application and the
Pi 3 build options, with its own system in `nerves_system_rpi0` (upstream Nerves
Zero system plus BlueZ/A2DP, `speaker-test` and the HiFiBerry overlays) and
its own `config/rpi0-config.txt` / `config/rpi0-fwup.conf`. The Pi 3 files are
unchanged.

```sh
make firmware-rpi0                      # MIX_TARGET=rpi0 make firmware
make burn-sd MIX_TARGET=rpi0 DEVICE=/dev/diskN
```

The Zero has no Ethernet: the micro-USB *data* port is an Ethernet gadget
(`usb0`) for a first access, and `wlan0` takes the Wi-Fi values from `.env`.
The LoRa radio and the ESP32 guide light are disabled on this target until they
are wired (`config/target.exs`). The I2S amplifier overlay is set in
`config/rpi0-config.txt` (InnoMaker MA12070P HAT, `merus-amp`, by default). The first build
compiles the whole Buildroot system, which takes a while; it is not
cross-built from the Pi 3 artifacts.
