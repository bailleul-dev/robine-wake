// Live mode: the room shows what the real server commands.
//
// Served by the demo server (ROBINE_DEMO=1), the page follows the emulated
// hardware stream (/emulator/stream): the Hue targets set by the domain
// (breathing halo, dawn and reading lamps), the audio output, and the
// server's virtual clock, which also drives the window (night, twilight,
// day). The bedside remote behaves like the firmware: it polls session.get
// every 2 s and its PRG button presses the server-side virtual remote, which
// signs the dismiss command.

import { createAudio } from "./audio.js";

const POLL_MS = 2000; // kWakeStateIntervalMs
const OFFLINE_AFTER = 3; // kWakeOfflineFailureThreshold
// A Hue bulb runs its transitions in real time. Short ones (breathing phases,
// strong-wake colours) are paced for a human and stay real; long ones are
// sunrise stages, scheduled on the domain clock, so they follow its speed.
const REAL_TRANSITION_MAX_MS = 10_000;
const TIME_ZONE = "Europe/Paris";

const smoothstep = (a, b, x) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};

// Daylight at the window (0 night, 1 day) for an autumn day in Paris: civil
// twilight from 07:15, sunrise around 07:45, sunset around 19:30.
const daylight = (hours) => smoothstep(7.25, 8.25, hours) * (1 - smoothstep(19.0, 20.0, hours));

/**
 * Connects to the demo server. Resolves to null when the page is served
 * without it (static hosting): the room then keeps its scripted scenes.
 */
export async function connectLive(ctx) {
  let snapshot;
  try {
    const response = await fetch("/emulator/state", { cache: "no-store" });
    if (!response.ok) return null;
    snapshot = await response.json();
  } catch {
    return null;
  }

  const { THREE, setLamp, setHalo, setWindow, kelvin, fromXy, invalidate } = ctx;
  const { HALO_MAX_LM, LAMP_LM, LUX_PER_LUMEN_AT_EYE, NIGHT_ADAPTATION_LUX, NIGHT_SKY, MOON } = ctx;
  const DAY_SKY = new THREE.Color(0xcfe3ff);
  const SUN = new THREE.Color(0xfff1dc);
  const MAX_LM = { halo: HALO_MAX_LM, lamp_left: LAMP_LM, lamp_right: LAMP_LM };

  // --- Virtual clock, extrapolated between server events -------------------

  let clock = null;
  function setClock(c) {
    clock = { utcMs: c.utc_ms ?? Date.parse(c.utc), speed: c.speed, at: performance.now() };
    invalidate();
  }
  const virtualNow = () => clock.utcMs + (performance.now() - clock.at) * clock.speed;
  const parts = new Intl.DateTimeFormat("en-GB", { timeZone: TIME_ZONE, hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" });
  function localTime() {
    const p = Object.fromEntries(parts.formatToParts(virtualNow()).map((x) => [x.type, Number(x.value)]));
    return { hours: p.hour + p.minute / 60 + p.second / 3600, hh: p.hour, mm: p.minute };
  }

  // --- Lights: Hue state to lumens and colour, with transitions ------------

  const outputs = {};
  const sample = (o, now) => {
    const elapsed = o.virtual ? (virtualNow() - o.startVirtual) : now - o.startReal;
    const k = o.duration > 0 ? Math.min(1, elapsed / o.duration) : 1;
    return { lumens: o.from.lumens + (o.to.lumens - o.from.lumens) * k, colour: o.from.colour.clone().lerp(o.to.colour, k), done: k >= 1 };
  };
  function setOutput(id, s) {
    const now = performance.now();
    const previous = outputs[id];
    const from = previous ? sample(previous, now) : { lumens: 0, colour: kelvin(2700) };
    const colour = s.xy ? fromXy(s.xy.x, s.xy.y) : kelvin(1e6 / (s.mirek || 370));
    const lumens = s.on ? (MAX_LM[id] * s.brightness) / 100 : 0;
    const duration = s.transition_ms || 0;
    outputs[id] = {
      from: { lumens: from.lumens, colour: from.colour },
      to: { lumens, colour: s.on ? colour : from.colour },
      duration,
      virtual: duration > REAL_TRANSITION_MAX_MS,
      startReal: now,
      startVirtual: virtualNow(),
      state: s,
    };
    invalidate();
  }
  const current = (id, now) => (outputs[id] ? sample(outputs[id], now) : { lumens: 0, colour: kelvin(2700), done: true });

  // --- Audio ------------------------------------------------------------------

  const audio = createAudio(document.getElementById("live-bar"));
  let sound = snapshot.audio;

  // --- Stream -------------------------------------------------------------------

  function applySnapshot(s) {
    setClock(s.clock);
    for (const [id, light] of Object.entries(s.lights)) setOutput(id, light);
    sound = s.audio;
    audio.update(sound);
  }
  applySnapshot(snapshot);

  const stream = new EventSource("/emulator/stream");
  stream.addEventListener("snapshot", (e) => applySnapshot(JSON.parse(e.data)));
  stream.addEventListener("hardware", (e) => {
    const event = JSON.parse(e.data);
    if (event.type === "light") setOutput(event.id, event.state);
    else if (event.type === "audio") (sound = event.state), audio.update(sound);
    else if (event.type === "clock") setClock(event.state);
    else if (event.type === "snapshot") applySnapshot(event.state);
  });

  // The window and the remote's clock move with time even when nothing else
  // does.
  setInterval(invalidate, 1000);

  // --- Remote (firmware loop) ----------------------------------------------------

  let wakeActive = false;
  let failures = 0;
  async function command(op) {
    const response = await fetch("/api/v1/command", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ v: 1, op, body: {} }),
    });
    if (!response.ok) throw new Error(String(response.status));
    return response.json();
  }
  async function poll() {
    try {
      const result = await command("session.get");
      wakeActive = result.status === "ok" && result.body.active_session != null;
      failures = 0;
    } catch {
      failures++;
    }
  }
  poll();
  setInterval(poll, POLL_MS);

  const remote = {
    alarmActive: () => wakeActive,
    reachable: () => failures < OFFLINE_AFTER,
    clock() {
      const t = localTime();
      return `${String(t.hh).padStart(2, "0")}:${String(t.mm).padStart(2, "0")}`;
    },
    async press() {
      try {
        const response = await fetch("/emulator/remote/press", { method: "POST" });
        if (!response.ok) return "server_error";
        const { feedback } = await response.json();
        poll();
        return feedback;
      } catch {
        return "network_error";
      }
    },
  };

  // --- Scene --------------------------------------------------------------------

  const scene = {
    label: "",
    animated: () =>
      clock.speed > 1 || Object.values(outputs).some((o) => !sample(o, performance.now()).done),
    update() {
      const now = performance.now();
      const halo = current("halo", now);
      const left = current("lamp_left", now);
      const right = current("lamp_right", now);
      setHalo(halo.lumens, halo.colour);
      setLamp("L", left.lumens, left.colour);
      setLamp("R", right.lumens, right.colour);

      const day = daylight(localTime().hours);
      setWindow(
        NIGHT_SKY.clone().lerp(DAY_SKY, day),
        MOON.clone().lerp(SUN, day),
        0.05 + 250 * Math.pow(day, 2),
        0.6 + 420 * Math.pow(day, 1.5),
      );
      const lampLux = Math.max(left.lumens, right.lumens) * LUX_PER_LUMEN_AT_EYE;
      return {
        lumens: halo.lumens + left.lumens + right.lumens + 400 * day,
        lux: Math.max(NIGHT_ADAPTATION_LUX, lampLux, 220 * day),
        environment: 0.01 + 0.04 * day,
      };
    },
    status() {
      const t = localTime();
      const time = `${String(t.hh).padStart(2, "0")}:${String(t.mm).padStart(2, "0")}`;
      const describe = (id, name) => {
        const o = outputs[id]?.state;
        if (!o?.on) return null;
        const colour = o.xy ? `xy ${o.xy.x.toFixed(2)}, ${o.xy.y.toFixed(2)}` : `${Math.round(1e6 / o.mirek)} K`;
        return `${name} ${Math.round(o.brightness)} % · ${colour}`;
      };
      const lights = [describe("halo", "halo"), describe("lamp_left", "lamps")].filter(Boolean).join(" · ") || "lights off";
      const playing = sound.playing ? ` · ♪ ${sound.sound_id}${sound.db != null ? ` ${sound.db.toFixed(0)} dB` : ""}` : "";
      const alarm = wakeActive ? " · <strong>alarm ringing</strong>" : "";
      return `<strong>Live</strong> · ${time} ×${clock.speed} · ${lights}${playing}${alarm}`;
    },
  };

  return { scene, remote };
}
