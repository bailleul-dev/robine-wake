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

if host_target? do
  config :robine_wake, RobineWakeDevWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: parse_integer.("ROBINE_DEV_PORT", 4111)]
end
