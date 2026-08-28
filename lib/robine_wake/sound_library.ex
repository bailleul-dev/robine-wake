defmodule RobineWake.SoundLibrary do
  @moduledoc false

  require Logger

  @sample_rate 44_100
  @duration_seconds 4
  @frequency 440
  @amplitude 11_000

  def ensure_default do
    path = Application.fetch_env!(:robine_wake, :default_sound_path)

    if valid_wave?(path) do
      :ok
    else
      write_wave(path)
    end
  end

  def valid_wave?(path) do
    match?({:ok, _metadata}, inspect_wave(path))
  end

  def inspect_wave(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, metadata} <- parse_wave(contents) do
      digest = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
      {:ok, Map.put(metadata, :sha256, digest)}
    end
  end

  def available?(sound_id) when is_binary(sound_id) do
    case path(sound_id) do
      {:ok, path} -> valid_sound_file?(path)
      {:error, _reason} -> false
    end
  end

  def available?(_sound_id), do: false

  def list do
    (custom_sounds() ++ bundled_sounds())
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{sound_source_rank(&1.source), &1.title})
  end

  def path("default"), do: {:ok, Application.fetch_env!(:robine_wake, :default_sound_path)}

  def path(sound_id) when is_binary(sound_id) do
    with :ok <- validate_sound_id(sound_id) do
      persistent_mp3 = Path.join(default_directory(), sound_id <> ".mp3")
      custom_wave = Path.join(default_directory(), sound_id <> ".wav")

      cond do
        File.regular?(persistent_mp3) ->
          {:ok, persistent_mp3}

        File.regular?(custom_wave) ->
          {:ok, custom_wave}

        bundled = bundled_sound(sound_id) ->
          {:ok, Path.join(bundled_directory(), bundled.filename)}

        true ->
          {:error, :sound_not_found}
      end
    end
  end

  def path(_sound_id), do: {:error, :invalid_sound_id}

  defp custom_sounds do
    directory = default_directory()

    directory
    |> Path.join("*.wav")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case inspect_wave(path) do
        {:ok, metadata} ->
          id = path |> Path.basename(".wav")
          title = id |> String.replace("_", " ") |> String.capitalize()

          [
            Map.merge(metadata, %{
              id: id,
              title: title,
              artist: nil,
              intensity: "custom",
              source: if(id == "default", do: "system", else: "custom"),
              version: 1
            })
          ]

        {:error, _reason} ->
          []
      end
    end)
  end

  defp bundled_sounds do
    manifest_path = Path.join(bundled_directory(), "manifest.json")

    with {:ok, contents} <- File.read(manifest_path),
         {:ok, entries} when is_list(entries) <- Jason.decode(contents) do
      Enum.flat_map(entries, &bundled_sound_entry/1)
    else
      _ -> []
    end
  end

  defp bundled_sound_entry(entry) do
    path = Path.join(bundled_directory(), entry["filename"] || "")

    if File.regular?(path) do
      [
        %{
          id: entry["id"],
          title: entry["title"],
          artist: entry["artist"],
          filename: entry["filename"],
          format: entry["format"],
          duration_ms: entry["duration_ms"],
          intensity: entry["intensity"],
          source: "bundled",
          sha256: entry["sha256"],
          bytes: File.stat!(path).size,
          version: 1
        }
      ]
    else
      []
    end
  end

  defp sound_source_rank("bundled"), do: 0
  defp sound_source_rank("system"), do: 1
  defp sound_source_rank(_source), do: 2

  defp bundled_sound(sound_id), do: Enum.find(bundled_sounds(), &(&1.id == sound_id))

  def import(sound_id, contents, claimed_sha256)
      when is_binary(sound_id) and is_binary(contents) and is_binary(claimed_sha256) do
    maximum = Application.fetch_env!(:robine_wake, :maximum_sound_bytes)

    with :ok <- validate_sound_id(sound_id),
         true <- byte_size(contents) > 44 and byte_size(contents) <= maximum,
         true <- String.match?(claimed_sha256, ~r/\A[0-9a-fA-F]{64}\z/),
         digest = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower),
         true <- Plug.Crypto.secure_compare(digest, String.downcase(claimed_sha256)),
         {:ok, destination} <- custom_sound_path(sound_id) do
      temporary = destination <> ".#{RobineWake.Id.generate()}.tmp"

      result =
        with :ok <- File.mkdir_p(Path.dirname(destination)),
             :ok <- File.write(temporary, contents, [:binary, :sync]),
             {:ok, metadata} <- inspect_wave(temporary),
             :ok <- File.chmod(temporary, 0o600),
             :ok <- File.rename(temporary, destination) do
          {:ok, Map.merge(metadata, %{id: sound_id, version: 1})}
        end

      if match?({:error, _reason}, result), do: File.rm(temporary)
      result
    else
      false -> {:error, :invalid_size_or_digest}
      {:error, reason} -> {:error, reason}
    end
  end

  def import(_sound_id, _contents, _claimed_sha256), do: {:error, :invalid_sound}

  defp write_wave(path) do
    samples = @sample_rate * @duration_seconds

    pcm =
      for index <- 0..(samples - 1), into: <<>> do
        envelope = min(1.0, index / (@sample_rate * 0.15))

        value =
          round(
            :math.sin(2 * :math.pi() * @frequency * index / @sample_rate) *
              @amplitude * envelope
          )

        <<value::little-signed-16>>
      end

    data_size = byte_size(pcm)
    byte_rate = @sample_rate * 2

    wave =
      <<"RIFF", 36 + data_size::little-32, "WAVE", "fmt ", 16::little-32, 1::little-16,
        1::little-16, @sample_rate::little-32, byte_rate::little-32, 2::little-16, 16::little-16,
        "data", data_size::little-32, pcm::binary>>

    temporary = path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(temporary, wave, [:binary, :sync]),
         :ok <- File.rename(temporary, path) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Could not generate the default alarm sound: #{inspect(reason)}")
        error
    end
  end

  defp parse_wave(
         <<"RIFF", riff_size::little-32, "WAVE", "fmt ", 16::little-32, audio_format::little-16,
           channels::little-16, sample_rate::little-32, byte_rate::little-32,
           block_align::little-16, bits_per_sample::little-16, "data", data_size::little-32,
           data::binary>>
       ) do
    expected_align = channels * div(bits_per_sample, 8)

    with :ok <- validate_pcm_format(audio_format, channels, sample_rate, bits_per_sample),
         :ok <- validate_wave_sizes(block_align, byte_rate, sample_rate, expected_align),
         :ok <- validate_data_sizes(data_size, data, riff_size) do
      peak = peak_sample(data)

      {:ok,
       %{
         format: :wav_pcm,
         channels: channels,
         sample_rate: sample_rate,
         bits_per_sample: bits_per_sample,
         duration_ms: div(data_size * 1_000, byte_rate),
         bytes: byte_size(data) + 44,
         normalized_peak_dbfs: peak_dbfs(peak)
       }}
    end
  end

  defp parse_wave(_contents), do: {:error, :invalid_wave}

  defp validate_pcm_format(1, channels, sample_rate, 16)
       when channels in [1, 2] and sample_rate in [44_100, 48_000],
       do: :ok

  defp validate_pcm_format(audio_format, _channels, _sample_rate, _bits) when audio_format != 1,
    do: {:error, :not_pcm}

  defp validate_pcm_format(_format, channels, _sample_rate, _bits) when channels not in [1, 2],
    do: {:error, :unsupported_channels}

  defp validate_pcm_format(_format, _channels, sample_rate, _bits)
       when sample_rate not in [44_100, 48_000],
       do: {:error, :unsupported_sample_rate}

  defp validate_pcm_format(_format, _channels, _sample_rate, _bits),
    do: {:error, :unsupported_bit_depth}

  defp validate_wave_sizes(block_align, byte_rate, sample_rate, expected_align)
       when block_align == expected_align and byte_rate == sample_rate * expected_align,
       do: :ok

  defp validate_wave_sizes(_block_align, _byte_rate, _sample_rate, _expected_align),
    do: {:error, :invalid_format_sizes}

  defp validate_data_sizes(data_size, data, riff_size)
       when data_size == byte_size(data) and riff_size == 36 + data_size,
       do: :ok

  defp validate_data_sizes(_data_size, _data, _riff_size),
    do: {:error, :invalid_file_sizes}

  defp custom_sound_path(sound_id) do
    with :ok <- validate_sound_id(sound_id) do
      {:ok, Path.join(default_directory(), sound_id <> ".wav")}
    end
  end

  defp valid_sound_file?(path) do
    case Path.extname(path) do
      ".wav" -> valid_wave?(path)
      ".mp3" -> File.regular?(path)
      _ -> false
    end
  end

  defp bundled_directory, do: Application.app_dir(:robine_wake, "priv/sounds")

  defp default_directory,
    do: Application.fetch_env!(:robine_wake, :default_sound_path) |> Path.dirname()

  defp validate_sound_id(sound_id) do
    if String.match?(sound_id, ~r/\A[a-zA-Z0-9_-]{1,64}\z/),
      do: :ok,
      else: {:error, :invalid_sound_id}
  end

  defp peak_sample(data) do
    for <<sample::little-signed-16 <- data>>, reduce: 0 do
      peak -> max(peak, abs(sample))
    end
  end

  defp peak_dbfs(0), do: -120.0
  defp peak_dbfs(peak), do: Float.round(20 * :math.log10(peak / 32_768), 2)
end
