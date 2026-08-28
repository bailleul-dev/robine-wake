alias RobineWake.Audio.MeditationDSP

defmodule RobineWake.Scripts.PlayMeditationDSP do
  @channels 2
  @bytes_per_sample 2
  @frame_bytes @channels * @bytes_per_sample
  @chunk_frames 4_096

  def run(argv) do
    argv = Enum.reject(argv, &(&1 == "--"))

    {options, positional} =
      OptionParser.parse!(argv,
        strict: [
          duration: :integer,
          volume: :float,
          seed: :string,
          layer: :string,
          output: :string,
          metrics: :string
        ]
      )

    if positional != [], do: fail("unexpected arguments: #{Enum.join(positional, " ")}")

    duration = Keyword.get(options, :duration, 60)
    volume = Keyword.get(options, :volume, 0.6)
    seed = options |> Keyword.get(:seed, "0x524F4249") |> parse_seed!()
    {layer_name, layers} = options |> Keyword.get(:layer, "rain") |> parse_layers!()
    requested_output = Keyword.get(options, :output)
    requested_metrics = Keyword.get(options, :metrics)

    if duration < 1 or duration > 3_600,
      do: fail("duration must be between 1 and 3600 seconds")

    if volume < 0.0 or volume > 1.0,
      do: fail("volume must be between 0.0 and 1.0")

    output = requested_output || default_path()
    metrics = render_wave!(output, duration, seed, layers)

    if requested_metrics do
      File.mkdir_p!(Path.dirname(requested_metrics))
      File.write!(requested_metrics, Jason.encode_to_iodata!(metrics, pretty: true))
      IO.puts("Métriques: #{requested_metrics}")
    end

    IO.puts(
      "DSP #{layer_name} · #{duration}s · #{MeditationDSP.sample_rate()} Hz stéréo · volume #{volume}"
    )
  end

  defp render_wave!(path, duration, seed, layers) do
    sample_rate = MeditationDSP.sample_rate()
    frame_count = duration * sample_rate
    data_size = frame_count * @frame_bytes
    File.mkdir_p!(Path.dirname(path))

    File.open!(path, [:write, :binary], fn file ->
      IO.binwrite(file, wave_header(sample_rate, data_size))

      render_chunks(
        file,
        MeditationDSP.initial_state(seed),
        frame_count,
        layers,
        empty_metrics(),
        frame_count
      )
    end)
  end

  defp render_chunks(_file, _state, 0, _layers, metrics, total_frames),
    do: finalize_metrics(metrics, total_frames)

  defp render_chunks(file, state, remaining, layers, metrics, total_frames) do
    frames = min(remaining, @chunk_frames)
    {pcm, next_state} = MeditationDSP.render(state, frames, layers)
    IO.binwrite(file, pcm)

    render_chunks(
      file,
      next_state,
      remaining - frames,
      layers,
      accumulate_metrics(pcm, metrics),
      total_frames
    )
  end

  defp wave_header(sample_rate, data_size) do
    byte_rate = sample_rate * @frame_bytes

    <<"RIFF", 36 + data_size::little-32, "WAVE", "fmt ", 16::little-32, 1::little-16,
      @channels::little-16, sample_rate::little-32, byte_rate::little-32, @frame_bytes::little-16,
      16::little-16, "data", data_size::little-32>>
  end

  defp parse_seed!("0x" <> hexadecimal) do
    case Integer.parse(hexadecimal, 16) do
      {seed, ""} -> seed
      _error -> fail("seed must be an integer or a hexadecimal value such as 0x524F4249")
    end
  end

  defp parse_seed!(decimal) do
    case Integer.parse(decimal) do
      {seed, ""} -> seed
      _error -> fail("seed must be an integer or a hexadecimal value such as 0x524F4249")
    end
  end

  defp parse_layers!("full"), do: {"complet", [:pad, :rain]}
  defp parse_layers!("air"), do: {"air", [:air]}
  defp parse_layers!("pad"), do: {"bourdon", [:pad]}
  defp parse_layers!("rain"), do: {"pluie isolée", [:rain]}
  defp parse_layers!("bed"), do: {"lit distant", [:rain_bed]}
  defp parse_layers!("leaf"), do: {"impacts foliaires", [:rain_leaf]}
  defp parse_layers!("splash"), do: {"splash", [:rain_splash]}
  defp parse_layers!("direct"), do: {"pluie directe", [:rain_direct]}
  defp parse_layers!("drip"), do: {"égouttement", [:rain_drip]}
  defp parse_layers!("wood"), do: {"bois et sol", [:rain_wood]}

  defp parse_layers!(_value),
    do: fail("layer must be one of: rain, bed, leaf, splash, direct, drip, wood, air, pad, full")

  defp empty_metrics do
    %{
      samples: 0,
      square_sum: 0.0,
      peak: 0,
      cross_sum: 0.0,
      left_square_sum: 0.0,
      right_square_sum: 0.0,
      transient_count: 0,
      refractory: 0,
      previous_mono: 0
    }
  end

  defp accumulate_metrics(pcm, metrics) do
    Enum.reduce(
      for(<<left::little-signed-16, right::little-signed-16 <- pcm>>, do: {left, right}),
      metrics,
      fn {left, right}, acc ->
        mono = div(left + right, 2)
        high_pass = abs(mono - acc.previous_mono)
        transient = high_pass > 1_900 and acc.refractory == 0

        %{
          acc
          | samples: acc.samples + 2,
            square_sum: acc.square_sum + left * left + right * right,
            peak: max(acc.peak, max(abs(left), abs(right))),
            cross_sum: acc.cross_sum + left * right,
            left_square_sum: acc.left_square_sum + left * left,
            right_square_sum: acc.right_square_sum + right * right,
            transient_count: acc.transient_count + if(transient, do: 1, else: 0),
            refractory: if(transient, do: 576, else: max(acc.refractory - 1, 0)),
            previous_mono: mono
        }
      end
    )
  end

  defp finalize_metrics(metrics, total_frames) do
    rms = :math.sqrt(metrics.square_sum / max(metrics.samples, 1)) / 32_768
    peak = metrics.peak / 32_768

    correlation =
      metrics.cross_sum /
        max(:math.sqrt(metrics.left_square_sum * metrics.right_square_sum), 1.0)

    %{
      sample_rate_hz: MeditationDSP.sample_rate(),
      duration_seconds: total_frames / MeditationDSP.sample_rate(),
      rms_dbfs: decibels(rms),
      peak_dbfs: decibels(peak),
      crest_factor_db: decibels(peak / max(rms, 1.0e-12)),
      stereo_correlation: Float.round(correlation, 4),
      detected_transients_per_second:
        Float.round(metrics.transient_count * MeditationDSP.sample_rate() / total_frames, 3)
    }
  end

  defp decibels(value), do: Float.round(20.0 * :math.log10(max(value, 1.0e-12)), 3)

  defp default_path, do: Path.join("tmp", "meditation-dsp-preview.wav")

  defp fail(message) do
    IO.puts(:stderr, "DSP preview error: #{message}")
    System.halt(2)
  end
end

RobineWake.Scripts.PlayMeditationDSP.run(System.argv())
