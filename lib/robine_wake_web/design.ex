defmodule RobineWakeWeb.Design do
  @moduledoc false

  def product_css do
    """
    :root {
      color-scheme: dark;
      --night-950: #070914;
      --night-900: #0d1022;
      --night-850: #12162c;
      --night-800: #181d37;
      --line: rgba(196, 205, 255, .13);
      --line-strong: rgba(196, 205, 255, .24);
      --text: #f7f5ff;
      --muted: #a9adc7;
      --moon: #f5cf87;
      --moon-soft: #ffe7b7;
      --lavender: #aaa7ff;
      --mint: #78d9bc;
      --rose: #ff8ca3;
      font-family: Inter, ui-rounded, "SF Pro Rounded", system-ui, -apple-system, sans-serif;
    }
    * { box-sizing: border-box; }
    [hidden] { display: none !important; }
    html { scroll-behavior: smooth; }
    body {
      min-height: 100vh;
      margin: 0;
      color: var(--text);
      background:
        radial-gradient(circle at 12% -8%, rgba(100, 97, 190, .34), transparent 31rem),
        radial-gradient(circle at 90% 5%, rgba(58, 111, 143, .18), transparent 26rem),
        var(--night-950);
    }
    body::before {
      content: "";
      position: fixed;
      inset: 0;
      pointer-events: none;
      opacity: .36;
      background-image:
        radial-gradient(circle at 14% 12%, #fff 0 1px, transparent 1.5px),
        radial-gradient(circle at 78% 18%, #fff 0 1px, transparent 1.5px),
        radial-gradient(circle at 62% 8%, #fff 0 1px, transparent 1.5px),
        radial-gradient(circle at 91% 31%, #fff 0 1px, transparent 1.5px);
      background-size: 23rem 19rem, 31rem 27rem, 29rem 22rem, 37rem 31rem;
    }
    button, input, select { font: inherit; }
    button, a, summary, input, select { -webkit-tap-highlight-color: transparent; }
    button:focus-visible, a:focus-visible, summary:focus-visible, input:focus-visible, select:focus-visible {
      outline: 3px solid rgba(170, 167, 255, .55);
      outline-offset: 2px;
    }
    .shell { width: min(1180px, calc(100% - 2rem)); margin: 0 auto; padding: 1.5rem 0 4rem; position: relative; }
    .topbar { display: flex; align-items: center; justify-content: space-between; gap: 1rem; margin-bottom: 1.25rem; }
    .brand { display: flex; align-items: center; gap: .8rem; }
    .brand-mark { width: 2.7rem; height: 2.7rem; border-radius: 50%; position: relative; background: var(--moon); box-shadow: 0 0 30px rgba(245, 207, 135, .2); }
    .brand-mark::after { content: ""; position: absolute; width: 2.35rem; height: 2.35rem; border-radius: 50%; background: #11152b; top: -.22rem; right: -.22rem; }
    .brand strong { display: block; font-size: 1.05rem; letter-spacing: -.02em; }
    .brand small { color: var(--muted); font-size: .76rem; }
    .status-pill { display: inline-flex; align-items: center; gap: .55rem; min-height: 2.65rem; padding: .7rem .9rem; color: inherit; border: 1px solid var(--line); border-radius: 999px; background: rgba(14, 18, 38, .72); backdrop-filter: blur(18px); text-transform: capitalize; cursor: pointer; }
    .status-pill::before { content: ""; width: .55rem; height: .55rem; border-radius: 50%; background: currentColor; box-shadow: 0 0 14px currentColor; }
    .app-tabs { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: .35rem; width: min(34rem, 100%); margin: 0 auto 1.25rem; padding: .35rem; border: 1px solid var(--line); border-radius: 1.1rem; background: rgba(11, 14, 31, .72); backdrop-filter: blur(20px); }
    .app-tab { min-height: 3rem; padding: .65rem .8rem; color: var(--muted); border: 0; background: transparent; }
    .app-tab span { margin-right: .42rem; color: var(--lavender); font-size: 1.15rem; }
    .app-tab.active { color: #17182a; background: var(--moon); box-shadow: 0 8px 24px rgba(245,207,135,.15); }
    .app-tab.active span { color: #6f5330; }
    .app-screen { display: none; animation: screen-in .3s ease both; }
    .app-screen.active { display: block; }
    @keyframes screen-in { from { opacity: 0; transform: translateY(.35rem); } to { opacity: 1; transform: none; } }
    .screen-heading { padding: clamp(1.5rem, 5vw, 3.5rem) clamp(.25rem, 3vw, 2rem) 1rem; }
    .screen-heading h1, .evening-hero h1 { margin: 0; font-size: clamp(2.4rem, 7vw, 4.7rem); line-height: .95; letter-spacing: -.065em; }
    .screen-heading > p:last-child, .evening-hero > p:last-child { max-width: 39rem; color: var(--muted); font-size: 1.05rem; line-height: 1.6; }
    .hero { min-height: 21rem; position: relative; overflow: hidden; display: grid; grid-template-columns: 1.35fr .65fr; align-items: end; gap: 2rem; padding: clamp(1.5rem, 5vw, 4rem); border: 1px solid var(--line); border-radius: 2rem; background: linear-gradient(135deg, rgba(29, 31, 66, .95), rgba(11, 17, 36, .96)); box-shadow: 0 28px 80px rgba(0, 0, 0, .32); }
    .hero::before { content: ""; position: absolute; width: 21rem; height: 21rem; border-radius: 50%; right: -4rem; top: -8rem; background: radial-gradient(circle at 35% 35%, #fff7d9 0, var(--moon) 25%, #c78f54 72%); box-shadow: 0 0 80px rgba(245, 207, 135, .22); opacity: .93; }
    .hero::after { content: ""; position: absolute; left: -10%; right: -10%; bottom: -8rem; height: 13rem; border-radius: 50% 50% 0 0; background: linear-gradient(180deg, #20284b, #10152c); border-top: 1px solid rgba(255,255,255,.08); }
    .hero-copy, .next-wake { position: relative; z-index: 2; }
    .eyebrow { margin: 0 0 .7rem; color: var(--moon); font-size: .72rem; font-weight: 800; letter-spacing: .18em; text-transform: uppercase; }
    .hero-time { margin: 0; font-size: clamp(4.2rem, 11vw, 8.5rem); line-height: .84; letter-spacing: -.075em; font-weight: 650; }
    .hero-date { margin: 1.2rem 0 0; color: #c7c9dc; font-size: 1.05rem; }
    .next-wake { align-self: end; padding: 1.25rem; border: 1px solid rgba(255,255,255,.13); border-radius: 1.25rem; background: rgba(7, 9, 20, .5); backdrop-filter: blur(18px); }
    .next-wake span { color: var(--muted); font-size: .78rem; text-transform: uppercase; letter-spacing: .13em; }
    .next-wake strong { display: block; margin: .25rem 0; color: var(--moon-soft); font-size: clamp(2rem, 5vw, 3.4rem); letter-spacing: -.055em; }
    .next-wake p { margin: 0; color: #d5d6e5; }
    .clock-warning { margin: 1rem 0 0; padding: 1rem 1.1rem; border: 1px solid rgba(245,207,135,.3); border-radius: 1rem; background: rgba(86,63,30,.35); color: var(--moon-soft); }
    .evening-hero { position: relative; min-height: 22rem; overflow: hidden; display: flex; flex-direction: column; justify-content: end; padding: clamp(1.7rem, 5vw, 4rem); border: 1px solid rgba(255,140,163,.18); border-radius: 2rem; background: radial-gradient(circle at 78% 28%, rgba(255,140,163,.18), transparent 18rem), linear-gradient(135deg, rgba(46,29,60,.96), rgba(10,15,34,.98)); box-shadow: 0 28px 80px rgba(0,0,0,.3); }
    .evening-hero > *:not(.breathing-orb) { position: relative; z-index: 2; }
    .breathing-orb { position: absolute; right: clamp(1rem, 8vw, 7rem); top: 2.2rem; width: clamp(9rem, 22vw, 15rem); aspect-ratio: 1; display: grid; place-items: center; border-radius: 50%; background: radial-gradient(circle, rgba(255,200,185,.86), rgba(255,140,163,.38) 36%, rgba(170,167,255,.06) 68%, transparent 70%); filter: drop-shadow(0 0 38px rgba(255,140,163,.2)); }
    .breathing-orb span { width: 48%; aspect-ratio: 1; border-radius: 50%; background: radial-gradient(circle at 35% 30%, #fff4dc, #f0a77f 48%, #b75f7a); box-shadow: 0 0 42px rgba(245,207,135,.35); animation: breathe 10s ease-in-out infinite; }
    @keyframes breathe { 0%,100% { transform: scale(.72); opacity: .75; } 40% { transform: scale(1.18); opacity: 1; } }
    .dashboard { display: grid; grid-template-columns: repeat(12, minmax(0, 1fr)); gap: 1rem; margin-top: 1rem; }
    .panel { grid-column: span 6; padding: clamp(1.15rem, 2.5vw, 1.65rem); border: 1px solid var(--line); border-radius: 1.5rem; background: rgba(16, 20, 42, .83); backdrop-filter: blur(18px); box-shadow: 0 18px 55px rgba(0, 0, 0, .16); }
    .panel.full { grid-column: 1 / -1; }
    .panel.span-7 { grid-column: span 7; }
    .panel.span-5 { grid-column: span 5; }
    .panel-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; margin-bottom: 1.2rem; }
    .panel h2 { margin: 0; font-size: clamp(1.25rem, 2vw, 1.65rem); letter-spacing: -.035em; }
    .panel-kicker { display: block; margin-bottom: .35rem; color: var(--lavender); font-size: .69rem; font-weight: 800; letter-spacing: .16em; text-transform: uppercase; }
    .panel-kicker.rose { color: var(--rose); }
    .breathing-panel { overflow: hidden; background: radial-gradient(circle at 92% 5%, rgba(255,140,163,.1), transparent 18rem), rgba(16,20,42,.86); }
    .breathing-badge { padding: .45rem .7rem; color: var(--moon-soft); border: 1px solid rgba(245,207,135,.22); border-radius: 999px; background: rgba(245,207,135,.08); font-size: .72rem; }
    .breathing-badge.active { color: #d9fff3; border-color: rgba(120,217,188,.28); background: rgba(120,217,188,.1); }
    .breathing-active { margin: .3rem 0 1.2rem; padding: 1rem; border: 1px solid rgba(170,167,255,.22); border-radius: 1.25rem; background: rgba(9,12,28,.62); }
    .breathing-active[hidden] { display: none; }
    .phase-visual { display: flex; align-items: center; gap: 1rem; }
    .phase-visual strong, .phase-visual small { display: block; }
    .phase-visual strong { margin-bottom: .2rem; font-size: 1.35rem; }
    .phase-orb { flex: 0 0 auto; width: 4.5rem; height: 4.5rem; border-radius: 50%; transition: .25s ease; }
    .phase-orb.inhale { background: radial-gradient(circle at 35% 30%, #f5cf87, #f5b75b 58%, #9b593f); box-shadow: 0 0 32px rgba(245,183,91,.38); transform: scale(1.05); }
    .phase-orb.exhale { background: radial-gradient(circle at 35% 30%, #efafae, #e0698f 58%, #843d62); box-shadow: 0 0 32px rgba(224,105,143,.34); transform: scale(.82); }
    .phase-legends { display: grid; grid-template-columns: 1fr 1fr; gap: .75rem; margin: 1.2rem 0; }
    .phase-legends > div { display: flex; align-items: center; gap: .75rem; padding: .9rem; border: 1px solid var(--line); border-radius: 1rem; background: rgba(7,10,24,.42); }
    .phase-legends span strong, .phase-legends span small { display: block; }
    .phase-legends i { flex: 0 0 auto; width: 1.05rem; height: 1.05rem; border-radius: 50%; }
    .inhale-dot { background: #f5b75b; box-shadow: 0 0 14px rgba(245,183,91,.48); }
    .exhale-dot { background: #e0698f; box-shadow: 0 0 14px rgba(224,105,143,.44); }
    .evening-controls { display: grid; grid-template-columns: 1.4fr .8fr 1.2fr; gap: .9rem; margin-top: 1.25rem; }
    .volume-control output { justify-self: end; margin-top: -1.75rem; }
    .breathing-actions { margin-top: 1.25rem; }
    .panel-copy, .muted, small { color: var(--muted); line-height: 1.55; }
    .form-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: .9rem; }
    .field { display: grid; align-content: start; gap: .42rem; color: #d8d9e7; font-size: .84rem; font-weight: 650; }
    .field.wide { grid-column: span 2; }
    input, select { width: 100%; min-height: 3.15rem; padding: .75rem .85rem; color: var(--text); border: 1px solid var(--line-strong); border-radius: .85rem; background: rgba(6, 9, 22, .72); transition: border-color .18s, background .18s, transform .18s; }
    input:hover, select:hover { border-color: rgba(196,205,255,.38); }
    input:focus, select:focus { border-color: var(--lavender); background: rgba(11,14,31,.95); }
    input[type="checkbox"] { width: 1.2rem; min-height: 1.2rem; accent-color: var(--lavender); }
    input[type="file"] { padding: .65rem; }
    fieldset { border: 0; padding: 0; margin: 0; }
    legend { margin-bottom: .45rem; color: #d8d9e7; font-size: .84rem; font-weight: 650; }
    .days { display: flex; flex-wrap: wrap; gap: .4rem; }
    .day { position: relative; }
    .day input { position: absolute; opacity: 0; pointer-events: none; }
    .day span { display: grid; place-items: center; width: 2.65rem; height: 2.65rem; border: 1px solid var(--line-strong); border-radius: 50%; color: var(--muted); background: rgba(7,9,20,.54); cursor: pointer; transition: .18s ease; }
    .day input:checked + span { color: #12152a; background: var(--moon); border-color: var(--moon); box-shadow: 0 6px 20px rgba(245,207,135,.16); }
    .day input:focus-visible + span { outline: 3px solid rgba(170,167,255,.55); outline-offset: 2px; }
    details.settings { margin-top: 1rem; border-top: 1px solid var(--line); padding-top: 1rem; }
    details.settings summary { cursor: pointer; color: var(--moon-soft); font-weight: 750; list-style: none; }
    details.settings summary::after { content: "+"; float: right; font-size: 1.25rem; }
    details.settings[open] summary::after { content: "−"; }
    details.settings .form-grid { margin-top: 1rem; }
    .switch { min-height: 3.15rem; display: flex; align-items: center; gap: .65rem; padding: .75rem .85rem; border: 1px solid var(--line-strong); border-radius: .85rem; background: rgba(6,9,22,.72); }
    .actions { display: flex; flex-wrap: wrap; gap: .65rem; align-items: center; }
    .form-actions { justify-content: flex-end; margin-top: 1rem; padding-top: 1rem; border-top: 1px solid var(--line); }
    button, .button-link { min-height: 2.9rem; display: inline-flex; align-items: center; justify-content: center; padding: .72rem 1rem; border: 1px solid var(--line-strong); border-radius: .85rem; color: var(--text); background: #232947; cursor: pointer; font-weight: 760; text-decoration: none; transition: transform .16s, background .16s, border-color .16s; }
    button:hover, .button-link:hover { transform: translateY(-1px); background: #2c3459; border-color: rgba(196,205,255,.38); }
    button.primary { color: #17182a; background: var(--moon); border-color: var(--moon); }
    button.secondary { color: #17182a; background: var(--lavender); border-color: var(--lavender); }
    button.ghost { background: transparent; }
    button.danger { color: #ffdce4; background: rgba(127,43,67,.36); border-color: rgba(255,140,163,.3); }
    .session-banner { grid-column: 1 / -1; display: grid; grid-template-columns: 1fr auto; align-items: center; gap: 1rem; padding: 1.25rem 1.4rem; border: 1px solid rgba(245,207,135,.28); border-radius: 1.4rem; background: linear-gradient(120deg, rgba(78,58,31,.76), rgba(38,32,54,.9)); }
    #session[hidden] { display: none; }
    .session-banner h2 { margin: 0 0 .25rem; }
    .alarm-list { display: grid; gap: .75rem; }
    .alarm { display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: 1rem; padding: 1rem; border: 1px solid var(--line); border-radius: 1.1rem; background: linear-gradient(120deg, rgba(7,10,24,.62), rgba(19,23,47,.66)); }
    .alarm-time { min-width: 5rem; color: var(--moon-soft); font-size: 1.65rem; font-weight: 650; letter-spacing: -.04em; }
    .alarm strong { font-size: 1rem; }
    .alarm-meta { display: flex; flex-wrap: wrap; gap: .35rem .7rem; margin-top: .35rem; color: var(--muted); font-size: .76rem; }
    .sound-route { display: flex; align-items: center; gap: .4rem; margin-top: .55rem; color: #cfd1e2; font-size: .75rem; }
    .sound-route span { max-width: 13rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .sound-route i { color: var(--lavender); font-style: normal; }
    .alarm .actions button { min-height: 2.45rem; padding: .5rem .7rem; font-size: .78rem; }
    .alarm.disabled { opacity: .55; }
    .empty-state { display: grid; place-items: center; min-height: 10rem; padding: 1.5rem; border: 1px dashed var(--line-strong); border-radius: 1.1rem; color: var(--muted); text-align: center; }
    .timeline { display: grid; gap: .55rem; }
    .timeline-item { display: grid; grid-template-columns: .65rem 1fr; gap: .75rem; padding: .65rem 0; border-bottom: 1px solid var(--line); }
    .timeline-item::before { content: ""; width: .55rem; height: .55rem; margin-top: .35rem; border-radius: 50%; background: var(--lavender); box-shadow: 0 0 12px rgba(170,167,255,.34); }
    .system-row { display: flex; justify-content: space-between; gap: 1rem; padding: .8rem 0; border-bottom: 1px solid var(--line); }
    .system-row span { color: var(--muted); }
    .diagnostic-list { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .65rem; margin-top: 1rem; }
    .diagnostic-item { display: grid; grid-template-columns: 1fr auto; gap: .25rem 1rem; padding: .9rem 1rem; border: 1px solid var(--line); border-radius: 1rem; background: rgba(8,11,25,.36); }
    .diagnostic-item strong { align-self: start; }
    .diagnostic-item small { grid-column: 1 / -1; color: var(--muted); overflow-wrap: anywhere; }
    #diagnostics-panel:focus { outline: 3px solid rgba(170,167,255,.45); outline-offset: 4px; }
    .privacy-note { display: flex; gap: .75rem; align-items: flex-start; padding: .9rem; margin: 1rem 0; border-radius: 1rem; color: #cfd1e2; background: rgba(120,217,188,.07); border: 1px solid rgba(120,217,188,.15); }
    .privacy-note::before { content: ""; flex: 0 0 auto; width: .75rem; height: .9rem; margin-top: .25rem; border: 2px solid var(--mint); border-radius: .2rem .2rem .4rem .4rem; }
    .healthy, .available, .trusted { color: var(--mint); }
    .degraded, .unknown { color: var(--moon); }
    .unhealthy, .unavailable { color: var(--rose); }
    #alarm-preview, #form-error { margin: .8rem 0 0; }
    #form-error { color: var(--rose); }
    dialog { width: min(58rem, calc(100% - 1.25rem)); max-height: calc(100dvh - 1.25rem); padding: 0; color: var(--text); border: 1px solid var(--line-strong); border-radius: 1.75rem; background: #10142a; box-shadow: 0 40px 120px rgba(0,0,0,.62); }
    dialog::backdrop { background: rgba(3,5,14,.78); backdrop-filter: blur(10px); }
    .alarm-editor { display: grid; grid-template-rows: auto minmax(0,1fr); max-height: calc(100dvh - 1.25rem); }
    .editor-head { position: sticky; top: 0; z-index: 3; display: flex; align-items: center; justify-content: space-between; gap: 1rem; padding: 1.25rem 1.4rem; border-bottom: 1px solid var(--line); background: rgba(16,20,42,.94); backdrop-filter: blur(20px); }
    .editor-head h2 { margin: .15rem 0 0; font-size: clamp(1.5rem,3vw,2rem); letter-spacing: -.045em; }
    .icon-button { width: 2.8rem; min-height: 2.8rem; padding: 0; border-radius: 50%; font-size: 1.35rem; }
    .editor-form { overflow-y: auto; padding: 1.4rem; }
    .editor-section { padding: 1.2rem; margin-bottom: 1rem; border: 1px solid var(--line); border-radius: 1.25rem; background: rgba(7,10,24,.42); }
    .section-title { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; margin-bottom: 1rem; }
    .section-title h3 { margin: 0; font-size: 1.05rem; }
    .section-title p { margin: .25rem 0 0; color: var(--muted); font-size: .8rem; }
    .time-field input { min-height: 5rem; color: var(--moon-soft); font-size: clamp(2rem,7vw,3.4rem); font-weight: 650; letter-spacing: -.055em; text-align: center; }
    .editor-basics { display: grid; grid-template-columns: 1fr 1.3fr 1fr; gap: .9rem; align-items: end; }
    .schedule-row { display: grid; grid-template-columns: 1.5fr 1fr; gap: 1rem; margin-top: 1rem; align-items: end; }
    .sound-journey { display: grid; grid-template-columns: 1fr auto 1fr; gap: .8rem; align-items: stretch; }
    .sound-phase { position: relative; padding: 1rem; border: 1px solid var(--line-strong); border-radius: 1.1rem; background: rgba(15,19,40,.88); }
    .sound-phase.strong { border-color: rgba(255,140,163,.3); background: linear-gradient(145deg, rgba(69,26,45,.4), rgba(15,19,40,.9)); }
    .phase-label { display: flex; align-items: center; gap: .65rem; margin-bottom: .8rem; }
    .phase-number { display: grid; place-items: center; width: 1.75rem; height: 1.75rem; border-radius: 50%; color: #13152a; background: var(--moon); font-size: .75rem; font-weight: 850; }
    .strong .phase-number { background: var(--rose); }
    .phase-label strong { display: block; }
    .phase-label small { display: block; }
    .journey-arrow { align-self: center; color: var(--lavender); font-size: 1.4rem; }
    .control-grid { display: grid; grid-template-columns: repeat(3,minmax(0,1fr)); gap: .9rem; }
    .range-field output { color: var(--moon-soft); font-variant-numeric: tabular-nums; }
    input[type="range"] { min-height: 2rem; padding: 0; border: 0; accent-color: var(--moon); background: transparent; }
    .behavior-grid { display: grid; grid-template-columns: 1.2fr .8fr .8fr; gap: .9rem; }
    .editor-actions { position: sticky; bottom: -1.4rem; z-index: 2; display: flex; justify-content: space-between; gap: 1rem; margin: 1.4rem -1.4rem -1.4rem; padding: 1rem 1.4rem; border-top: 1px solid var(--line); background: rgba(16,20,42,.96); backdrop-filter: blur(20px); }
    .editor-actions > div { display: flex; gap: .65rem; }
    .sound-library-grid { display: grid; grid-template-columns: repeat(2,minmax(0,1fr)); gap: .6rem; }
    .sound-chip { padding: .75rem; border: 1px solid var(--line); border-radius: .9rem; background: rgba(7,10,24,.45); }
    .sound-chip strong, .sound-chip small { display: block; }
    .sound-chip em { display: inline-block; margin-top: .35rem; color: var(--lavender); font-size: .68rem; font-style: normal; text-transform: uppercase; letter-spacing: .1em; }
    .footer { padding: 2rem 0 0; color: #777d9c; text-align: center; font-size: .78rem; }
    @media (max-width: 900px) {
      .hero { grid-template-columns: 1fr; min-height: 25rem; }
      .next-wake { max-width: 20rem; }
      .panel, .panel.span-7, .panel.span-5 { grid-column: 1 / -1; }
      .form-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .editor-basics, .control-grid, .behavior-grid { grid-template-columns: 1fr 1fr; }
      .evening-controls { grid-template-columns: 1fr 1fr; }
      .volume-control { grid-column: 1 / -1; }
      .time-field { grid-column: 1 / -1; }
    }
    @media (max-width: 620px) {
      .shell { width: min(100% - 1rem, 1180px); padding: .7rem 0 7rem; }
      .topbar { padding: .35rem; }
      .brand small { display: none; }
      .status-pill { min-height: 2.35rem; padding: .55rem .7rem; font-size: .8rem; }
      .app-tabs { position: fixed; z-index: 20; left: .5rem; right: .5rem; bottom: .5rem; width: auto; margin: 0; padding: .3rem; border-radius: 1.25rem; background: rgba(10,13,29,.9); box-shadow: 0 16px 50px rgba(0,0,0,.55); }
      .app-tab { min-height: 3.75rem; display: grid; place-items: center; align-content: center; gap: .05rem; padding: .35rem .15rem; border-radius: .95rem; font-size: .7rem; }
      .app-tab span { margin: 0; font-size: 1.25rem; line-height: 1; }
      .hero { min-height: 23rem; padding: 1.35rem; border-radius: 1.4rem; }
      .hero-time { font-size: clamp(4rem, 24vw, 6rem); }
      .hero::before { width: 14rem; height: 14rem; right: -5rem; top: -4rem; }
      .dashboard { gap: .65rem; }
      .evening-hero { min-height: 26rem; padding: 1.35rem; border-radius: 1.4rem; }
      .breathing-orb { right: -1.5rem; top: 1rem; width: 12rem; }
      .phase-legends, .evening-controls { grid-template-columns: 1fr; }
      .volume-control { grid-column: auto; }
      .breathing-actions { display: grid; grid-template-columns: 1fr; }
      .breathing-actions button { width: 100%; }
      .panel { padding: 1rem; border-radius: 1.2rem; }
      .form-grid { grid-template-columns: 1fr; }
      dialog { width: 100%; max-width: none; height: 100dvh; max-height: 100dvh; margin: 0; border-radius: 0; border-left: 0; border-right: 0; }
      .alarm-editor { max-height: 100dvh; }
      .editor-form { padding: .85rem; }
      .editor-basics, .schedule-row, .control-grid, .behavior-grid, .sound-journey { grid-template-columns: 1fr; }
      .journey-arrow { justify-self: center; transform: rotate(90deg); }
      .editor-actions { bottom: -.85rem; margin: 1rem -.85rem -.85rem; padding: .8rem; }
      .editor-actions, .editor-actions > div { display: grid; grid-template-columns: 1fr; }
      .editor-actions > div { grid-template-columns: .8fr 1.2fr; }
      .editor-actions button { width: 100%; }
      .sound-library-grid { grid-template-columns: 1fr; }
      .field.wide { grid-column: auto; }
      .session-banner { grid-template-columns: 1fr; }
      .alarm { grid-template-columns: 1fr; }
      .alarm-time { font-size: 2rem; }
      .alarm .actions { display: grid; grid-template-columns: 1fr 1fr; }
      .alarm .actions button { width: 100%; }
      .form-actions { display: grid; grid-template-columns: 1fr; }
      .form-actions button { width: 100%; }
      table { display: block; overflow-x: auto; }
      .diagnostic-list { grid-template-columns: 1fr; }
    }
    @media (prefers-reduced-motion: reduce) { * { scroll-behavior: auto !important; transition: none !important; } }
    """
  end

  def setup_css do
    """
    #{product_css()}
    body { display: grid; place-items: center; padding: 1rem; }
    .setup-shell { width: min(100%, 34rem); }
    .setup-hero { text-align: center; margin-bottom: 1.4rem; }
    .setup-hero .brand-mark { margin: 0 auto 1rem; }
    .setup-hero h1 { margin: 0; font-size: clamp(2rem, 8vw, 3.3rem); letter-spacing: -.055em; }
    .setup-hero p { color: var(--muted); }
    .setup-card { padding: clamp(1.25rem, 5vw, 2rem); border: 1px solid var(--line); border-radius: 1.5rem; background: rgba(16,20,42,.9); box-shadow: 0 28px 80px rgba(0,0,0,.32); }
    .setup-card button { width: 100%; margin-top: 1rem; }
    .setup-note { margin-top: 1rem; color: var(--muted); font-size: .8rem; text-align: center; }
    #message { min-height: 1.5rem; color: var(--moon-soft); }
    """
  end
end
