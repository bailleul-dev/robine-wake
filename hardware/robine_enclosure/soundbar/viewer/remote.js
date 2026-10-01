// Emulator of the bedside remote: Heltec WiFi Kit 32 V1 (ESP32, SSD1306
// 128x64 OLED) running hardware/remote_button/src/main.cpp. It is drawn as an
// on-screen device, outside the 3D room: the remote lives in the hand or on
// the nightstand, it is not part of the bar.
//
// Screens, texts, timings and contrast follow the firmware: idle screen,
// active-alarm screen (Robine running with hearts), feedback screens after a
// press, 3 s hold to preview the alarm screen for 15 s.

import { ROBINE_SPRITE } from "./remote_sprites.js";

const W = 128, H = 64;
const FEEDBACK_MS = 3000;
const HOLD_MS = 3000;
const PREVIEW_MS = 15000;
const INTERACTION_BRIGHT_MS = 5000;
const FRAME_MS = 180; // Robine animation phase

const FONTS = {
  small: "8px ui-monospace, Menlo, monospace", // u8g2_font_5x8_tf
  body: "10px ui-monospace, Menlo, monospace", // u8g2_font_6x12_tf
  title: "bold 11px Helvetica, Arial, sans-serif", // u8g2_font_helvB10_tf
  clock: "bold 27px 'Arial Narrow', 'Helvetica Neue', Arial, sans-serif", // u8g2_font_logisoso24_tn
};

const FEEDBACK = {
  dismissed: ["COMMANDE ENVOYEE", "Reveil arrete", "Bonne journee", true],
  idle: ["TOUT EST CALME", "Aucun reveil", "Rien a arreter", true],
};

// --- 1-bit frame buffer, drawn with the same primitives as u8g2 -----------

class Oled {
  constructor() {
    this.buf = new Uint8Array(W * H);
    this.colour = 1;
    this.text = document.createElement("canvas");
    this.text.width = W;
    this.text.height = H;
    this.tctx = this.text.getContext("2d", { willReadFrequently: true });
  }
  clear() { this.buf.fill(0); this.colour = 1; }
  px(x, y) { if (x >= 0 && x < W && y >= 0 && y < H) this.buf[(y | 0) * W + (x | 0)] = this.colour; }
  box(x, y, w, h) { for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.px(x + i, y + j); }
  hline(x, y, w) { this.box(x, y, w, 1); }
  line(x0, y0, x1, y1) {
    const dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    let err = dx + dy;
    for (;;) {
      this.px(x0, y0);
      if (x0 === x1 && y0 === y1) break;
      const e2 = 2 * err;
      if (e2 >= dy) { err += dy; x0 += sx; }
      if (e2 <= dx) { err += dx; y0 += sy; }
    }
  }
  circle(cx, cy, r, fill = false) {
    for (let y = -r; y <= r; y++) {
      for (let x = -r; x <= r; x++) {
        const d = Math.sqrt(x * x + y * y);
        if (fill ? d <= r + 0.3 : Math.abs(d - r) < 0.55) this.px(cx + x, cy + y);
      }
    }
  }
  triangle(ax, ay, bx, by, cx, cy) {
    const minY = Math.min(ay, by, cy), maxY = Math.max(ay, by, cy);
    const minX = Math.min(ax, bx, cx), maxX = Math.max(ax, bx, cx);
    const side = (x, y, x1, y1, x2, y2) => (x - x2) * (y1 - y2) - (x1 - x2) * (y - y2);
    for (let y = minY; y <= maxY; y++) {
      for (let x = minX; x <= maxX; x++) {
        const d1 = side(x, y, ax, ay, bx, by), d2 = side(x, y, bx, by, cx, cy), d3 = side(x, y, cx, cy, ax, ay);
        const neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0;
        if (!(neg && pos)) this.px(x, y);
      }
    }
  }
  rbox(x, y, w, h, r) {
    for (let j = 0; j < h; j++) {
      for (let i = 0; i < w; i++) {
        const cx = i < r ? r - i : i >= w - r ? i - (w - r - 1) : 0;
        const cy = j < r ? r - j : j >= h - r ? j - (h - r - 1) : 0;
        if (cx * cx + cy * cy <= r * r + 1) this.px(x + i, y + j);
      }
    }
  }
  // Text at a baseline, like u8g2's drawStr; thresholded to 1 bit.
  str(x, y, text, font) {
    const c = this.tctx;
    c.clearRect(0, 0, W, H);
    c.font = font;
    c.fillStyle = "#fff";
    c.textBaseline = "alphabetic";
    c.fillText(text, x, y);
    const data = c.getImageData(0, 0, W, H).data;
    for (let i = 0; i < W * H; i++) if (data[i * 4 + 3] > 110) this.buf[i] = this.colour;
  }
  width(text, font) {
    this.tctx.font = font;
    return Math.round(this.tctx.measureText(text).width);
  }
  xbm(x, y, sprite, frame) {
    const stride = Math.ceil(sprite.width / 8);
    for (let j = 0; j < sprite.height; j++) {
      for (let i = 0; i < sprite.width; i++) {
        if (frame[j * stride + (i >> 3)] & (1 << (i & 7))) this.px(x + i, y + j);
      }
    }
  }
}

// --- Screens (same layout as the firmware) -------------------------------

function drawWifiBars(d, x, y, strength) {
  for (let i = 0; i < 4; i++) {
    const h = 2 + i * 2;
    if (i < strength) d.box(x + i * 4, y - h, 2, h);
  }
}

function drawHeart(d, x, y, large) {
  d.px(x + 1, y);
  d.px(x + 3, y);
  d.hline(x, y + 1, 5);
  d.hline(x + 1, y + 2, 3);
  d.px(x + 2, y + 3);
  if (large) {
    d.px(x, y + 2);
    d.px(x + 4, y + 2);
  }
}

function drawAlarm(d, now) {
  const phase = Math.floor(now / FRAME_MS) % ROBINE_SPRITE.frames.length;
  d.clear();
  const bounce = phase === 1 || phase === 3 ? -1 : 1;
  const ax = 2 + bounce;
  d.triangle(ax, 7, ax + 7, 1, ax + 7, 13);
  d.box(ax + 6, 5, 10, 5);
  d.str(25, 8, "JE T'AIME,", FONTS.small);
  const run = phase === 1 ? -1 : phase === 3 ? 1 : 0;
  d.xbm(38 + run, 10, ROBINE_SPRITE, ROBINE_SPRITE.frames[phase]);
  drawHeart(d, 21, 19 + (phase % 2), phase === 0 || phase === 3);
  drawHeart(d, 101, 14 - (phase % 2), phase === 1 || phase === 2);
  if (phase === 2) drawHeart(d, 111, 30, false);
  const message = "TU ME PROMÈNES";
  d.str(Math.round((W - d.width(message, FONTS.small)) / 2), 63, message, FONTS.small);
}

function drawMain(d, time) {
  d.clear();
  d.str(2, 10, "ROBINe WAKE", FONTS.body);
  drawWifiBars(d, 112, 10, 4);
  d.str(2, 40, time, FONTS.clock);
  d.circle(94, 21, 3, true);
  d.str(101, 25, "PRET", FONTS.body);
  d.str(88, 38, "REVEIL", FONTS.body);
  d.rbox(0, 50, 128, 14, 3);
  d.colour = 0;
  d.str(17, 61, "PRG  ARRETER", FONTS.body);
  d.colour = 1;
}

function drawCheck(d, x, y) {
  d.circle(x, y, 11);
  d.line(x - 6, y, x - 2, y + 5);
  d.line(x - 2, y + 5, x + 7, y - 6);
  d.line(x - 6, y + 1, x - 2, y + 6);
  d.line(x - 2, y + 6, x + 7, y - 5);
}

function drawFeedback(d, [eyebrow, title, detail]) {
  d.clear();
  drawCheck(d, 15, 22);
  d.str(33, 9, eyebrow, FONTS.small);
  d.str(33, 25, title, FONTS.title);
  d.str(33, 39, detail, FONTS.small);
  d.rbox(0, 50, 128, 14, 3);
  d.colour = 0;
  d.str(19, 60, "RETOUR AUTOMATIQUE", FONTS.small);
  d.colour = 1;
}

// --- Device ---------------------------------------------------------------

/**
 * Mounts the remote in `host`.
 * - `alarmActive()` tells whether a wake session is ringing;
 * - `press()` is called on a short PRG press and returns "dismissed" or "idle";
 * - `clock()` returns the time to display ("HH:MM").
 */
export function mountRemote(host, { alarmActive, press, clock }) {
  host.innerHTML = `
    <div class="remote-caption">
      <strong>Bedside remote</strong>
      <span>Emulated ESP32 · not in the 3D room</span>
    </div>
    <div class="remote-device">
      <span class="remote-usb" aria-hidden="true"></span>
      <button class="remote-prg" type="button" aria-label="PRG button: stop the alarm (hold 3 s to preview the alarm screen)"></button>
      <span class="remote-prg-label" aria-hidden="true">PRG</span>
      <div class="remote-window"><canvas class="remote-oled" width="${W}" height="${H}" role="img" aria-label="Remote OLED screen"></canvas></div>
    </div>
    <div class="remote-hint">Press PRG to stop the alarm · hold 3 s to preview</div>`;

  const canvas = host.querySelector(".remote-oled");
  const ctx = canvas.getContext("2d");
  const image = ctx.createImageData(W, H);
  const oled = new Oled();
  const button = host.querySelector(".remote-prg");

  let feedback = null; // { lines, until }
  let previewUntil = 0;
  let brightUntil = performance.now() + 1500; // startup brightness
  let holdTimer = null;
  let held = false;

  function onDown(e) {
    e.preventDefault();
    button.classList.add("pressed");
    held = false;
    holdTimer = setTimeout(() => {
      held = true;
      previewUntil = performance.now() + PREVIEW_MS;
    }, HOLD_MS);
  }
  function onUp() {
    if (!button.classList.contains("pressed")) return;
    button.classList.remove("pressed");
    clearTimeout(holdTimer);
    if (held) return;
    const result = press();
    feedback = { lines: FEEDBACK[result] ?? FEEDBACK.idle, until: performance.now() + FEEDBACK_MS };
    brightUntil = performance.now() + INTERACTION_BRIGHT_MS;
    previewUntil = 0;
  }
  button.addEventListener("pointerdown", onDown);
  button.addEventListener("pointerup", onUp);
  button.addEventListener("pointerleave", onUp);
  button.addEventListener("keydown", (e) => (e.key === " " || e.key === "Enter") && !e.repeat && onDown(e));
  button.addEventListener("keyup", (e) => (e.key === " " || e.key === "Enter") && onUp());

  function render() {
    const now = performance.now();
    if (feedback && now >= feedback.until) feedback = null;
    const alarmScreen = alarmActive() || now < previewUntil;
    if (feedback) drawFeedback(oled, feedback.lines);
    else if (alarmScreen) drawAlarm(oled, now);
    else drawMain(oled, clock());
    // SSD1306 contrast: dim at rest, full as soon as an alarm rings or after
    // an interaction.
    const bright = alarmScreen || feedback || now < brightUntil;
    host.classList.toggle("bright", Boolean(bright));
    for (let i = 0; i < W * H; i++) {
      const on = oled.buf[i];
      image.data[i * 4] = on ? 214 : 4;
      image.data[i * 4 + 1] = on ? 236 : 6;
      image.data[i * 4 + 2] = on ? 255 : 10;
      image.data[i * 4 + 3] = 255;
    }
    ctx.putImageData(image, 0, 0);
  }
  render();
  setInterval(render, 90);
}
