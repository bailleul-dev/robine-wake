import Config

parse_integer = fn variable, default ->
  case System.get_env(variable) do
    nil ->
      default

    value ->
      case Integer.parse(value) do
        {integer, ""} -> integer
        _ -> raise "#{variable} must be an integer"
      end
  end
end

host_target? = config_target() == :host
default_web_port = if host_target?, do: 4110, else: 4000

config :robine_wake,
  web_port: parse_integer.("ROBINE_WEB_PORT", default_web_port),
  dev_emulator_port: parse_integer.("ROBINE_DEV_PORT", 4111),
  admin_username:
    System.get_env("ROBINE_ADMIN_USERNAME") ||
      Application.get_env(:robine_wake, :admin_username, "admin"),
  admin_password:
    System.get_env("ROBINE_ADMIN_PASSWORD") ||
      Application.get_env(:robine_wake, :admin_password),
  alsa_device:
    System.get_env("ROBINE_ALSA_DEVICE") ||
      Application.get_env(:robine_wake, :alsa_device, "default"),
  alsa_mixer_control:
    System.get_env("ROBINE_ALSA_MIXER_CONTROL") ||
      Application.get_env(:robine_wake, :alsa_mixer_control, "Digital")

# Guide light reached over Wi-Fi instead of the UART, e.g.
# ROBINE_GUIDE_LIGHT_URL=http://robine-wake-a1b2c3.local:4000
if url = System.get_env("ROBINE_GUIDE_LIGHT_URL") do
  config :robine_wake, guide_light: [driver: RobineWake.GuideLight.Driver.HTTP, url: url]
end

if host_target? do
  config :robine_wake, RobineWakeDevWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: parse_integer.("ROBINE_DEV_PORT", 4111)]
end

# Demo deployment (host target only): the real server with emulated hardware,
# an accelerated clock, and one public port serving the app and the 3D room.
if host_target? and System.get_env("ROBINE_DEMO") in ["1", "true"] do
  demo_secret =
    System.get_env("ROBINE_DEMO_SECRET") || Base.encode64(:crypto.strong_rand_bytes(32))

  config :robine_wake,
    clock: RobineWakeDev.Clock.Scaled,
    hue_driver: RobineWake.Hue.Driver.Emulated,
    audio_driver: RobineWake.Audio.Driver.Emulated,
    initial_time_quality: :trusted,
    remote_dismiss_enabled: true,
    web_enabled: false,
    demo_access_code: System.get_env("ROBINE_DEMO_ACCESS_CODE"),
    demo_secret: demo_secret,
    demo_reset_hours: parse_integer.("ROBINE_DEMO_RESET_HOURS", 6),
    demo_room_dir:
      System.get_env("ROBINE_ROOM_DIR") || "hardware/robine_enclosure/soundbar/viewer",
    boot_children: [RobineWakeDev.Clock.Scaled, RobineWakeDev.Hardware],
    demo_children: [
      RobineWakeDev.VirtualRemote,
      RobineWakeDev.Demo,
      {Bandit,
       scheme: :http,
       plug: RobineWakeDemoWeb.Router,
       ip: {0, 0, 0, 0},
       port: parse_integer.("PORT", 8080)}
    ]
end
