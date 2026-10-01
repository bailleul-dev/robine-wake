// Sound of the bar in live mode: plays what the server's audio service sends
// to the emulated driver (RobineWake.Audio.Driver.Emulated), at the level the
// Amp2 would output.
//
// Events carry the sound URL and the output level in dB from the ALSA
// driver's curve (-45 dB at gain 1 to -6 dB at gain 100, null when muted).
// The browser cannot know the visitor's speakers, so the curve is shifted to
// put the loudest level at full scale; the ratios between levels are kept.

const MAX_DB = -6;
const RAMP_S = 0.25;

export function createAudio(host) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "sound-toggle";
  host.append(button);

  let context = null;
  let gain = null;
  let element = null;
  let current = { url: null, loop: false, db: null };
  let enabled = false;

  const level = (db) => (db == null ? 0 : Math.pow(10, (db - MAX_DB) / 20));

  function render() {
    button.textContent = enabled ? "Sound on" : "Enable sound";
    button.setAttribute("aria-pressed", String(enabled));
    button.classList.toggle("playing", enabled && Boolean(current.url));
  }

  function stopElement() {
    if (!element) return;
    element.pause();
    element.removeAttribute("src");
    element.load();
    element = null;
  }

  function sync() {
    if (!enabled) return;
    if (!current.url) {
      stopElement();
      return;
    }
    if (!element || element.dataset.url !== current.url) {
      stopElement();
      element = new Audio();
      element.crossOrigin = "anonymous";
      element.dataset.url = current.url;
      element.src = current.url;
      element.loop = current.loop;
      context.createMediaElementSource(element).connect(gain);
      element.play().catch(() => {});
    }
    gain.gain.setTargetAtTime(level(current.db), context.currentTime, RAMP_S / 3);
  }

  button.addEventListener("click", async () => {
    if (!context) {
      context = new AudioContext();
      gain = context.createGain();
      gain.gain.value = 0;
      gain.connect(context.destination);
    }
    enabled = !enabled;
    if (enabled) {
      await context.resume();
      sync();
    } else {
      stopElement();
    }
    render();
  });

  render();

  return {
    // audio: { playing, url, loop, db } from the emulated hardware.
    update(audio) {
      current = audio.playing ? { url: audio.url, loop: audio.loop, db: audio.db } : { url: null, loop: false, db: null };
      sync();
      render();
    },
  };
}
