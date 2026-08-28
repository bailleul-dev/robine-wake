import Config

config :logger, level: :warning

config :robine_wake, RobineWakeDevWeb.Endpoint, server: false

config :robine_wake,
  camera_enabled: true,
  data_path: "tmp/robine_wake_test.json",
  critical_event_path: "tmp/robine_wake_critical_events_test.json",
  auth_path: "tmp/robine_wake_auth_test.json",
  dev_emulator_enabled: false,
  admin_password: "test-only-password",
  password_iterations: 1_000,
  web_enabled: false,
  hue_driver: RobineWake.Hue.Driver.Test,
  scheduler_interval_ms: 50,
  exit_grace_ms: 0,
  exit_confirmation_ms: 100,
  max_session_ms: 500_000,
  audio_retry_delays_ms: [0, 0, 0, 0]
