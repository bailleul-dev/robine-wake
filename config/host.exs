import Config

config :nerves_runtime, Nerves.Runtime.KV, backend: Nerves.Runtime.KV.Mock
config :nerves_time_zones, data_dir: "tmp/nerves_time_zones"

config :robine_wake,
  audio_driver: RobineWake.Audio.Driver.Host,
  camera_driver: RobineWake.Camera.Driver.Host,
  dev_emulator_enabled: true,
  dev_emulator_port: 4111,
  web_port: 4110,
  admin_username: "admin"
