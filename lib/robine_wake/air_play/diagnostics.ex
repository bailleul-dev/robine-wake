defmodule RobineWake.AirPlay.Diagnostics do
  @moduledoc """
  Switches the AirPlay receiver into a diagnostic mode, and back, without a
  reflash.

  The firmware ships `shairport-sync-diag`, a launcher that runs the same
  Shairport Sync binary with a configuration enabling its own diagnostics and
  with its stderr appended to a file in `/tmp`. The binary also carries an
  optional per-block instrumentation (patch 0002 of the system package),
  enabled through the environment, which logs the size and decoded peak of
  the incoming audio blocks and can dump them raw. That is enough to tell a
  source that sends silence from a receiver that loses the audio.

  Everything written goes to `/tmp`, an 81 MB tmpfs shared with the network
  and D-Bus runtime files: `enable/1` refuses to start below a free-space
  margin, the raw block dump is capped by the binary, and `capture_pcm/1`
  returns to normal operation on its own.

  Typical session from the IEx shell on the target:

      RobineWake.AirPlay.Diagnostics.enable()
      # play from the phone, then:
      RobineWake.AirPlay.Diagnostics.summary()
      RobineWake.AirPlay.Diagnostics.log(40)
      RobineWake.AirPlay.Diagnostics.disable()

  See `docs/knowledges/airplay-diagnostics.md`.
  """

  require Logger

  alias RobineWake.AirPlay

  @config_file "/tmp/shairport-diag.conf"
  @log_file "/tmp/shairport-diag.log"
  @blocks_file "/tmp/shairport-blocks.bin"
  @pcm_file "/tmp/shairport-pcm.raw"

  @minimum_free_bytes 20 * 1024 * 1024
  @default_verbosity 2
  @default_pcm_seconds 60
  @silent_block_bytes 16

  @backup_key {__MODULE__, :executable}

  @type block :: %{
          number: non_neg_integer(),
          codec: String.t(),
          bytes: non_neg_integer(),
          ret: integer(),
          samples: non_neg_integer(),
          channels: non_neg_integer(),
          peak: float()
        }

  @doc """
  Restarts the receiver in diagnostic mode.

  Options:

    * `:verbosity` — Shairport Sync `log_verbosity`, 1 to 3 (default 2; 3 is
      very chatty and prints every RTSP message)
    * `:blocks` — log every 50th incoming block with its decoded peak
      (default `true`)
    * `:dump` — also keep the first 3000 raw blocks in `#{@blocks_file}`
      (default `false`)
    * `:pcm` — send the decoded PCM to `#{@pcm_file}` instead of the
      amplifier (default `false`); prefer `capture_pcm/1`, which stops by itself

  The previous captures are deleted first.
  """
  @spec enable(keyword()) :: {:ok, map()} | {:error, term()}
  def enable(opts \\ []) do
    with {:ok, verbosity} <- verbosity(opts),
         :ok <- check_free_space(),
         {:ok, base} <- read_base_config(),
         :ok <- File.write(@config_file, config_text(base, verbosity)) do
      clear_captures()
      remember_executable()

      Application.put_env(
        :robine_wake,
        :airplay_executable,
        Application.fetch_env!(:robine_wake, :airplay_diagnostics_executable)
      )

      Application.put_env(:robine_wake, :airplay_environment, environment(opts))
      restart_receiver()
      Logger.info("AirPlay diagnostics enabled: #{inspect(environment(opts))}")
      {:ok, status()}
    end
  end

  @doc """
  Returns the receiver to normal operation. The capture files stay in `/tmp`
  until `clear_captures/0` or the next `enable/1`.
  """
  @spec disable() :: {:ok, map()}
  def disable do
    case :persistent_term.get(@backup_key, nil) do
      nil -> :ok
      executable -> Application.put_env(:robine_wake, :airplay_executable, executable)
    end

    Application.put_env(:robine_wake, :airplay_environment, [])
    restart_receiver()
    Logger.info("AirPlay diagnostics disabled")
    {:ok, status()}
  end

  @doc """
  Captures the decoded PCM (48 kHz or 44.1 kHz, S32_LE, stereo) for `seconds`
  instead of playing it, then returns to normal operation. Nothing is audible
  during the capture. Measure the result with `pcm_peak_dbfs/0`.
  """
  @spec capture_pcm(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def capture_pcm(seconds \\ @default_pcm_seconds, opts \\ []) when seconds > 0 do
    with {:ok, status} <- enable(Keyword.put(opts, :pcm, true)) do
      _ =
        Task.start(fn ->
          Process.sleep(seconds * 1_000)
          disable()
        end)

      {:ok, status}
    end
  end

  @doc "Whether the receiver currently runs through the diagnostic launcher."
  @spec active?() :: boolean()
  def active? do
    Application.get_env(:robine_wake, :airplay_executable) ==
      Application.get_env(:robine_wake, :airplay_diagnostics_executable)
  end

  @spec status() :: map()
  def status do
    %{
      active: active?(),
      receiver: AirPlay.status(),
      environment: Application.get_env(:robine_wake, :airplay_environment, []),
      files:
        for path <- [@config_file, @log_file, @blocks_file, @pcm_file], File.exists?(path) do
          %{path: path, bytes: File.stat!(path).size}
        end,
      tmp_free_bytes: tmp_free_bytes()
    }
  end

  @doc "The last `count` lines of the receiver log."
  @spec log(pos_integer()) :: [String.t()]
  def log(count \\ 40) do
    case File.read(@log_file) do
      {:ok, content} -> content |> String.split("\n") |> Enum.take(-count)
      {:error, _reason} -> []
    end
  end

  @doc "Every per-block line of the receiver log, parsed."
  @spec blocks() :: [block()]
  def blocks do
    case File.read(@log_file) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&parse_block_line/1)
        |> Enum.reject(&is_nil/1)

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Summarises the parsed blocks: a source sending digital silence shows tiny,
  constant block sizes and a zero decoded peak.
  """
  @spec summary() :: map()
  def summary, do: summarize(blocks())

  @doc "Peak level of the PCM capture in dBFS, or `nil` without a capture."
  @spec pcm_peak_dbfs() :: float() | nil
  def pcm_peak_dbfs do
    if File.exists?(@pcm_file) do
      @pcm_file
      |> File.stream!([], 65_536)
      |> Enum.reduce(0, fn chunk, peak -> max(peak, pcm_peak(chunk)) end)
      |> peak_to_dbfs()
    end
  end

  @doc "Deletes the capture files."
  @spec clear_captures() :: :ok
  def clear_captures do
    Enum.each([@log_file, @blocks_file, @pcm_file], &File.rm/1)
  end

  @doc false
  @spec paths() :: map()
  def paths,
    do: %{config: @config_file, log: @log_file, blocks: @blocks_file, pcm: @pcm_file}

  # Pure helpers, exposed for tests.

  @doc false
  @spec config_text(String.t(), 1..3) :: String.t()
  def config_text(base, verbosity) when verbosity in 1..3 do
    stripped = Regex.replace(~r/diagnostics\s*=\s*\{.*?\};\s*/s, base, "")

    String.trim_trailing(stripped) <>
      "\n\n// Added by RobineWake.AirPlay.Diagnostics\ndiagnostics =\n{\n" <>
      "  log_verbosity = #{verbosity};\n  statistics = \"yes\";\n};\n"
  end

  @doc false
  @spec environment(keyword()) :: [{String.t(), String.t()}]
  def environment(opts) do
    [{"SPS_DIAG_CONF", @config_file}, {"SPS_DIAG_LOG", @log_file}] ++
      if(Keyword.get(opts, :blocks, true), do: [{"SPS_BLOCK_DIAG", "1"}], else: []) ++
      if(Keyword.get(opts, :dump, false), do: [{"SPS_BLOCK_DUMP", @blocks_file}], else: []) ++
      if(Keyword.get(opts, :pcm, false), do: [{"SPS_DIAG_PCM", @pcm_file}], else: [])
  end

  @doc false
  @spec parse_block_line(String.t()) :: block() | nil
  def parse_block_line(line) do
    pattern =
      ~r/BLOCK (?<number>\d+): codec "(?<codec>[^"]*)" bytes (?<bytes>\d+) ret (?<ret>-?\d+) format -?\d+ samples (?<samples>\d+) channels (?<channels>\d+) peak (?<peak>[\d.]+)/

    case Regex.named_captures(pattern, line) do
      nil ->
        nil

      captures ->
        %{
          number: String.to_integer(captures["number"]),
          codec: captures["codec"],
          bytes: String.to_integer(captures["bytes"]),
          ret: String.to_integer(captures["ret"]),
          samples: String.to_integer(captures["samples"]),
          channels: String.to_integer(captures["channels"]),
          peak: String.to_float(captures["peak"])
        }
    end
  end

  @doc false
  @spec summarize([block()]) :: map()
  def summarize([]), do: %{blocks: 0, verdict: :no_blocks}

  def summarize(blocks) do
    sizes = Enum.map(blocks, & &1.bytes)
    peak = blocks |> Enum.map(& &1.peak) |> Enum.max()
    failures = Enum.count(blocks, &(&1.ret != 0))

    verdict =
      cond do
        failures == length(blocks) -> :decoding_fails
        Enum.max(sizes) <= @silent_block_bytes and peak == 0.0 -> :source_sends_silence
        peak == 0.0 -> :decoded_silence
        true -> :audio_present
      end

    %{
      blocks: length(blocks),
      codecs: blocks |> Enum.map(& &1.codec) |> Enum.uniq(),
      bytes: %{min: Enum.min(sizes), max: Enum.max(sizes)},
      peak: peak,
      decode_failures: failures,
      verdict: verdict
    }
  end

  @doc false
  @spec pcm_peak(binary()) :: non_neg_integer()
  def pcm_peak(binary) do
    for <<sample::little-signed-32 <- binary>>, reduce: 0 do
      peak -> max(peak, abs(sample))
    end
  end

  @doc false
  @spec peak_to_dbfs(non_neg_integer()) :: float()
  def peak_to_dbfs(0), do: -200.0
  def peak_to_dbfs(peak), do: Float.round(20 * :math.log10(peak / 2_147_483_648), 1)

  defp verbosity(opts) do
    case Keyword.get(opts, :verbosity, @default_verbosity) do
      level when level in 1..3 -> {:ok, level}
      other -> {:error, {:invalid_verbosity, other}}
    end
  end

  defp read_base_config do
    path = Application.fetch_env!(:robine_wake, :airplay_config_path)

    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:config_unreadable, path, reason}}
    end
  end

  defp check_free_space do
    case tmp_free_bytes() do
      free when is_integer(free) and free < @minimum_free_bytes -> {:error, {:tmp_full, free}}
      _free -> :ok
    end
  end

  defp tmp_free_bytes do
    case System.cmd("df", ["-k", "/tmp"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> List.last()
        |> String.split()
        |> Enum.at(3)
        |> then(fn
          nil -> nil
          kilobytes -> String.to_integer(kilobytes) * 1024
        end)

      _other ->
        nil
    end
  rescue
    _exception -> nil
  end

  defp remember_executable do
    if not active?() do
      :persistent_term.put(
        @backup_key,
        Application.fetch_env!(:robine_wake, :airplay_executable)
      )
    end
  end

  defp restart_receiver do
    :ok = AirPlay.suspend()
    :ok = AirPlay.resume()
  end
end
