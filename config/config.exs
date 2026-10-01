import Config

Application.start(:nerves_bootstrap)

config :elixir, :time_zone_database, Zoneinfo.TimeZoneDatabase
config :nerves_time_zones, default_time_zone: "Europe/Paris"
config :nerves, :firmware, rootfs_overlay: "rootfs_overlay"
config :nerves, source_date_epoch: "1787097600"

config :robine_wake,
  target: Mix.target(),
  clock: RobineWake.Clock.System,
  audio_driver: RobineWake.Audio.Driver.Host,
  camera_driver: RobineWake.Camera.Driver.Host,
  camera_enabled: false,
  # Keep remote dismissal implemented, but require the physical button in this build.
  remote_dismiss_enabled: false,
  network_driver: RobineWake.Network.Driver.Host,
  hue_driver: RobineWake.Hue.Driver.HTTP,
  hue_request_timeout_ms: 5_000,
  data_path: "data/robine_wake.json",
  auth_path: "data/robine_wake_auth.json",
  web_enabled: true,
  web_ip: {127, 0, 0, 1},
  web_port: 4000,
  mcp_allowed_origins: [],
  mcp_max_requests_per_minute: 120,
  dev_emulator_enabled: false,
  dev_emulator_port: 4111,
  admin_username: "admin",
  default_sound_path: "data/sounds/default.wav",
  maximum_sound_bytes: 5_000_000,
  alsa_device: "default",
  alsa_mixer_control: "Digital",
  music_receivers: [RobineWake.AirPlay, RobineWake.BluetoothAudio],
  airplay_enabled: false,
  airplay_name: "Robine Wake Bedroom",
  airplay_executable: "/usr/bin/shairport-sync",
  airplay_config_path: "/etc/shairport-sync.conf",
  airplay_restart_delay_ms: 2_000,
  bluetooth_audio_enabled: false,
  bluetooth_audio_name: "Robine Wake Bedroom",
  bluetooth_audio_mixer_db: -6.0,
  bluetooth_audio_restart_delay_ms: 2_000,
  bluetooth_audio_storage_path: "/data/bluetooth",
  bluetooth_audio_executables: %{
    dbus_daemon: "/usr/bin/dbus-daemon",
    dbus_uuidgen: "/usr/bin/dbus-uuidgen",
    bluetoothd: "/usr/libexec/bluetooth/bluetoothd",
    bluealsa: "/usr/bin/bluealsa",
    player: "/usr/bin/bluealsa-aplay",
    bluetoothctl: "/usr/bin/bluetoothctl"
  },
  bluetooth_enabled: false,
  lora_enabled: false,
  lora_driver: nil,
  lora_options: [],
  audio_safety_ceiling: 100,
  password_iterations: 100_000,
  telemetry_event_limit: 500,
  telemetry_retention_days: 7,
  critical_event_path: "data/robine_wake_critical_events.json",
  firmware_public_key_path: "rootfs_overlay/etc/robine-wake/fwup-key.pub",
  scheduler_interval_ms: 1_000,
  camera_interval_ms: 500,
  initial_time_quality: :trusted,
  auto_confirm_ntp: false,
  exit_grace_ms: 5_000,
  exit_confirmation_ms: 30_000,
  exit_confidence: 0.75,
  gentle_plateau_ms: 300_000,
  max_session_ms: 5_400_000,
  catch_up_seconds: 300,
  session_retention_days: 30,
  audio_retry_delays_ms: [0, 250, 1_000, 3_000]

config :robine_wake, RobineWakeDevWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: 4111],
  secret_key_base: "robine-wake-host-emulator-secret-key-base-only-for-local-development-2026",
  live_view: [signing_salt: "host-emulator"],
  pubsub_server: RobineWakeDev.PubSub,
  render_errors: [formats: [html: RobineWakeDevWeb.ErrorHTML], layout: false],
  server: true,
  check_origin: false

if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end

import_config "#{config_env()}.exs"
