alias RobineWake.Audio.MeditationDSP

duration_seconds = 30
sample_rate = MeditationDSP.sample_rate()
frame_count = duration_seconds * sample_rate

destination =
  System.argv()
  |> Enum.reject(&(&1 == "--"))
  |> List.first()
  |> Kernel.||("artifacts/jardin-nocturne-30s.wav")

{raw_pcm, _state} =
  MeditationDSP.render(MeditationDSP.initial_state(0x524F_4249), frame_count)

frames =
  raw_pcm
  |> then(fn pcm ->
    for <<left::little-signed-16, right::little-signed-16 <- pcm>>, do: {left, right}
  end)
  |> Enum.with_index()
  |> Enum.map(fn {{left, right}, index} ->
    seconds = index / sample_rate
    cycle_position = :math.fmod(seconds, 10.0)

    phase_progress =
      if cycle_position < 4.0,
        do: cycle_position / 4.0,
        else: 1.0 - (cycle_position - 4.0) / 6.0

    smoothed = phase_progress * phase_progress * (3.0 - 2.0 * phase_progress)
    breathing_gain = 0.68 + 0.32 * smoothed
    fade_in = min(seconds / 1.5, 1.0)
    fade_out = min((duration_seconds - seconds) / 1.5, 1.0)
    envelope = breathing_gain * fade_in * fade_out
    {left * envelope, right * envelope}
  end)

peak =
  Enum.reduce(frames, 1.0, fn {left, right}, current ->
    max(current, max(abs(left), abs(right)))
  end)

normalization = 29_000 / peak

pcm =
  for {left, right} <- frames, into: <<>> do
    left = round(left * normalization) |> min(32_767) |> max(-32_768)
    right = round(right * normalization) |> min(32_767) |> max(-32_768)
    <<left::little-signed-16, right::little-signed-16>>
  end

data_size = byte_size(pcm)
byte_rate = sample_rate * 2 * 2

wave =
  <<"RIFF", 36 + data_size::little-32, "WAVE", "fmt ", 16::little-32, 1::little-16, 2::little-16,
    sample_rate::little-32, byte_rate::little-32, 4::little-16, 16::little-16, "data",
    data_size::little-32, pcm::binary>>

File.mkdir_p!(Path.dirname(destination))
File.write!(destination, wave, [:binary])
IO.puts(destination)
