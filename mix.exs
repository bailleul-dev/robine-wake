defmodule RobineWake.MixProject do
  use Mix.Project

  @app :robine_wake
  @version "0.1.0"
  @all_targets [:rpi3, :rpi0]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.20",
      archives: [nerves_bootstrap: "~> 1.17"],
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      releases: [{@app, release()}, robine_wake_demo: demo_release()],
      default_release: @app,
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :crypto, :inets, :ssl],
      mod: {RobineWake.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [coveralls: :test, "coveralls.html": :test, verify: :test],
      preferred_targets: [credo: :host, run: :host, test: :host, verify: :host]
    ]
  end

  defp elixirc_paths(env) do
    common = if env == :test, do: ["lib", "test/support"], else: ["lib"]
    if Mix.target() == :host, do: ["lib_host" | common], else: ["lib_target" | common]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.12"},
      {:nerves_time_zones, "~> 0.3.8"},
      {:phoenix, "~> 1.8.0", targets: :host},
      {:phoenix_html, "~> 4.3", targets: :host},
      {:phoenix_live_view, "~> 1.2.0", targets: :host},
      {:websock_adapter, "~> 0.5", targets: :host},
      {:lazy_html, ">= 0.1.0", only: :test, targets: :host},
      {:excoveralls, "~> 0.18", only: :test},
      {:stream_data, "~> 1.2", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false, targets: :host},
      {:nerves, "~> 1.14", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:ring_logger, "~> 0.11.0"},
      {:muontrap, "~> 1.8"},
      {:toolshed, "~> 0.5.0"},
      {:nerves_runtime, "~> 0.13.12"},
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},
      {:circuits_spi, "~> 2.0", targets: @all_targets},
      {:circuits_uart, "~> 1.5", targets: @all_targets},
      {:blue_heron, "~> 0.5.4", targets: @all_targets, runtime: false},
      {:nerves_system_rpi3,
       path: "nerves_system_rpi3", nerves: [compile: true], runtime: false, targets: :rpi3},
      {:nerves_system_rpi0,
       path: "nerves_system_rpi0", nerves: [compile: true], runtime: false, targets: :rpi0}
    ]
  end

  def release do
    [
      overwrite: true,
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end

  # Demo deployment on a standard server (host target, `ROBINE_DEMO=1`): a
  # plain OTP release without the Nerves firmware steps. See the Dockerfile.
  def demo_release do
    [
      include_erts: true,
      steps: [:assemble],
      strip_beams: true,
      applications: [robine_wake: :permanent]
    ]
  end

  defp aliases do
    [
      verify: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "cmd mix hex.audit",
        "coveralls.html",
        "run scripts/mvp_report.exs"
      ]
    ]
  end
end
