defmodule RobineWakeDevWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :robine_wake

  @session_options [
    store: :cookie,
    key: "_robine_wake_dev",
    signing_salt: "host-emulator-session",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug Plug.Static,
    at: "/dev-assets/phoenix",
    from: {:phoenix, "priv/static"},
    only: ["phoenix.min.js"]

  plug Plug.Static,
    at: "/dev-assets/live-view",
    from: {:phoenix_live_view, "priv/static"},
    only: ["phoenix_live_view.min.js"]

  # Demo room: the WebGL viewer of the sound bar (hardware/robine_enclosure/
  # soundbar/viewer), served from the source tree on the host only.
  plug Plug.Static,
    at: "/room",
    from: "hardware/robine_enclosure/soundbar/viewer",
    only: ~w(index.html room.js decor.js assets)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], json_decoder: Jason
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug RobineWakeDevWeb.Router
end
