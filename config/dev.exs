import Config

config :logger, level: :info

if Mix.target() == :host do
  config :robine_wake,
    data_path: "data/robine_wake_dev.json"
end
