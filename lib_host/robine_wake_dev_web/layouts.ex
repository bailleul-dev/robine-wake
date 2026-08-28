defmodule RobineWakeDevWeb.Layouts do
  use RobineWakeDevWeb, :html

  def root(assigns) do
    assigns = assign(assigns, :csrf_token, Plug.CSRFProtection.get_csrf_token())

    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={@csrf_token} />
        <link rel="icon" href="data:," />
        <title>Robine Wake · Hardware Lab</title>
        <style>
          :root { color-scheme:dark; --night:#070914; --surface:#11152b; --surface-2:#171c36; --line:rgba(196,205,255,.14); --text:#f7f5ff; --muted:#a9adc7; --moon:#f5cf87; --lavender:#aaa7ff; --mint:#78d9bc; --rose:#ff8ca3; font-family:Inter,ui-rounded,"SF Pro Rounded",system-ui,sans-serif; }
          * { box-sizing:border-box; }
          body { margin:0; min-height:100vh; color:var(--text); background:radial-gradient(circle at 12% -8%,rgba(100,97,190,.34),transparent 32rem),radial-gradient(circle at 92% 6%,rgba(58,111,143,.18),transparent 25rem),var(--night); }
          body::before { content:""; position:fixed; inset:0; pointer-events:none; opacity:.3; background-image:radial-gradient(circle at 14% 12%,#fff 0 1px,transparent 1.5px),radial-gradient(circle at 78% 18%,#fff 0 1px,transparent 1.5px); background-size:23rem 19rem,31rem 27rem; }
          main { width:min(1180px,calc(100% - 2rem)); margin:0 auto; padding:1.5rem 0 4rem; position:relative; }
          header { min-height:15rem; position:relative; overflow:hidden; display:flex; align-items:flex-end; justify-content:space-between; gap:2rem; padding:clamp(1.5rem,4vw,3rem); margin-bottom:1rem; border:1px solid var(--line); border-radius:2rem; background:linear-gradient(135deg,rgba(29,31,66,.96),rgba(11,17,36,.97)); box-shadow:0 28px 80px rgba(0,0,0,.28); }
          header::after { content:""; position:absolute; width:14rem; height:14rem; right:-3rem; top:-5rem; border-radius:50%; background:radial-gradient(circle at 35% 35%,#fff7d9,var(--moon) 28%,#bd8550 74%); box-shadow:0 0 70px rgba(245,207,135,.22); }
          header > * { position:relative; z-index:1; }
          h1 { margin:.15rem 0 .5rem; font-size:clamp(2.25rem,5vw,4.5rem); line-height:.95; letter-spacing:-.06em; max-width:13ch; }
          h2 { margin:.1rem 0 1rem; color:var(--text); font-size:1.25rem; letter-spacing:-.025em; }
          p { line-height:1.55; } .muted { color:var(--muted); } .eyebrow { color:var(--moon); font-weight:850; text-transform:uppercase; letter-spacing:.16em; font-size:.7rem; }
          .grid { display:grid; grid-template-columns:repeat(12,minmax(0,1fr)); gap:1rem; }
          .card { grid-column:span 4; padding:clamp(1.1rem,2.5vw,1.55rem); border:1px solid var(--line); border-radius:1.45rem; background:rgba(16,20,42,.84); backdrop-filter:blur(18px); box-shadow:0 18px 55px rgba(0,0,0,.16); }
          .wide { grid-column:span 8; } .full { grid-column:1/-1; }
          .status-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:.65rem; }
          .status { padding:.85rem; color:var(--muted); background:rgba(7,10,24,.56); border-radius:.9rem; border:1px solid var(--line); }
          header > .status { min-width:10rem; background:rgba(7,9,20,.55); backdrop-filter:blur(18px); }
          .status strong { display:block; color:var(--text); font-size:1.05rem; margin-top:.2rem; text-transform:capitalize; }
          .status strong.good,.good { color:var(--mint); } .status strong.warn,.warn { color:var(--moon); } .status strong.bad,.bad { color:var(--rose); }
          .controls { display:flex; flex-wrap:wrap; gap:.55rem; }
          button,a { -webkit-tap-highlight-color:transparent; }
          button { min-height:2.75rem; border:1px solid rgba(196,205,255,.22); border-radius:.8rem; background:#232947; color:var(--text); padding:.65rem .85rem; font:inherit; font-weight:750; cursor:pointer; transition:.16s ease; }
          button:hover { transform:translateY(-1px); background:#2c3459; } button.primary { color:#17182a; background:var(--moon); border-color:var(--moon); } button.danger { color:#ffdce4; background:rgba(127,43,67,.38); border-color:rgba(255,140,163,.3); }
          button:focus-visible,a:focus-visible,input:focus-visible { outline:3px solid rgba(170,167,255,.55); outline-offset:2px; }
          input { width:6rem; min-height:2.75rem; border:1px solid rgba(196,205,255,.24); border-radius:.75rem; background:rgba(6,9,22,.75); color:white; padding:.65rem; font:inherit; }
          form.inline { display:flex; gap:.5rem; align-items:center; flex-wrap:wrap; }
          .bed { position:relative; min-height:280px; overflow:hidden; border-radius:1.15rem; background:radial-gradient(circle at 82% 15%,rgba(245,207,135,.22),transparent 22%),linear-gradient(160deg,#111731,#080b19); border:1px solid var(--line); }
          .bed::before { content:""; position:absolute; left:12%; right:12%; bottom:12%; height:58%; border:2px solid rgba(170,167,255,.42); border-radius:2.6rem 2.6rem 1rem 1rem; background:linear-gradient(160deg,rgba(89,94,156,.22),rgba(25,31,63,.55)); box-shadow:inset 0 0 45px rgba(170,167,255,.08); }
          .bed::after { content:"IR scan · local memory only"; position:absolute; right:1rem; top:1rem; color:var(--rose); font-size:.64rem; font-weight:850; letter-spacing:.12em; text-transform:uppercase; }
          .person { position:absolute; z-index:1; left:34%; top:35%; width:32%; height:38%; border-radius:48% 52% 40% 42%; background:linear-gradient(135deg,var(--lavender),#7378ca); box-shadow:0 0 38px rgba(170,167,255,.32); opacity:.9; transition:.3s ease; }
          .person::before { content:""; position:absolute; width:2.8rem; height:2.8rem; border-radius:50%; top:-1.1rem; left:-.8rem; background:#c5c3ff; }
          .person.vacant { opacity:0; transform:translateY(-1rem); } .person.unknown { background:var(--moon); opacity:.32; } .person.offline { background:var(--rose); opacity:.15; }
          .bed-label { position:absolute; left:1rem; bottom:1rem; z-index:2; padding:.45rem .65rem; border:1px solid var(--line); border-radius:999px; background:rgba(7,9,20,.74); text-transform:capitalize; }
          table { width:100%; border-collapse:collapse; margin-top:1rem; } th,td { text-align:left; padding:.8rem .5rem; border-bottom:1px solid var(--line); vertical-align:middle; } th { color:var(--muted); font-size:.68rem; text-transform:uppercase; letter-spacing:.11em; }
          code { color:var(--lavender); } .message { min-height:1.5rem; margin:.2rem 0 .8rem; color:var(--moon); }
          a { color:var(--moon); text-underline-offset:.2rem; }
          @media(max-width:850px){.card,.wide{grid-column:1/-1}header{min-height:19rem;display:flex;align-items:flex-end}.status-grid{grid-template-columns:1fr 1fr}}
          @media(max-width:580px){main{width:calc(100% - 1rem);padding-top:.5rem}header{display:block;min-height:22rem;padding:1.25rem;border-radius:1.4rem}header>.status{position:absolute;left:1.25rem;bottom:1.25rem}.card{padding:1rem;border-radius:1.2rem}.status-grid{grid-template-columns:1fr}.controls{display:grid;grid-template-columns:1fr 1fr}.controls button{width:100%}table{display:block;overflow-x:auto}.bed{min-height:230px}}
          @media(prefers-reduced-motion:reduce){*{transition:none!important}}
        </style>
      </head>
      <body>
        {@inner_content}
        <script src="/dev-assets/phoenix/phoenix.min.js"></script>
        <script src="/dev-assets/live-view/phoenix_live_view.min.js"></script>
        <script>
          const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
          const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {params: {_csrf_token: csrfToken}});
          liveSocket.connect(); window.liveSocket = liveSocket;
        </script>
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    {@inner_content}
    """
  end
end
