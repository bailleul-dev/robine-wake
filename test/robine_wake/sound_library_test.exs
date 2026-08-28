defmodule RobineWake.SoundLibraryTest do
  use ExUnit.Case, async: false

  test "generates a valid bounded PCM wave file atomically" do
    original = Application.fetch_env!(:robine_wake, :default_sound_path)
    path = "tmp/test-sounds/default.wav"
    Application.put_env(:robine_wake, :default_sound_path, path)
    File.rm(path)

    on_exit(fn -> Application.put_env(:robine_wake, :default_sound_path, original) end)

    assert :ok = RobineWake.SoundLibrary.ensure_default()
    assert RobineWake.SoundLibrary.valid_wave?(path)
    assert {:ok, metadata} = RobineWake.SoundLibrary.inspect_wave(path)
    assert metadata.sample_rate == 44_100
    assert metadata.channels == 1
    assert metadata.bits_per_sample == 16
    assert metadata.duration_ms == 4_000
    assert byte_size(metadata.sha256) == 64
    assert {:ok, %{size: size}} = File.stat(path)
    assert size > 350_000 and size < 360_000
    refute File.exists?(path <> ".tmp")
  end

  test "rejects a file that only mimics a RIFF header" do
    path = "tmp/test-sounds/invalid.wav"
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, <<"RIFF", 0::little-32, "WAVE", "not valid PCM">>)

    refute RobineWake.SoundLibrary.valid_wave?(path)
    assert {:error, :invalid_wave} = RobineWake.SoundLibrary.inspect_wave(path)
  end

  test "imports a digest-verified PCM sound atomically and lists its measured metadata" do
    original = Application.fetch_env!(:robine_wake, :default_sound_path)
    directory = "tmp/imported-sounds-#{System.unique_integer([:positive])}"
    source = Path.join(directory, "default.wav")
    Application.put_env(:robine_wake, :default_sound_path, source)

    on_exit(fn -> Application.put_env(:robine_wake, :default_sound_path, original) end)

    assert :ok = RobineWake.SoundLibrary.ensure_default()
    contents = File.read!(source)
    digest = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)

    assert {:ok, metadata} = RobineWake.SoundLibrary.import("gentle_bell", contents, digest)
    assert metadata.id == "gentle_bell"
    assert metadata.normalized_peak_dbfs < 0
    assert metadata.sha256 == digest
    assert {:ok, %{mode: mode}} = File.stat(Path.join(directory, "gentle_bell.wav"))
    assert Bitwise.band(mode, 0o777) == 0o600
    ids = Enum.map(RobineWake.SoundLibrary.list(), & &1.id)
    assert "default" in ids
    assert "gentle_bell" in ids
    assert "jungle_sunrise" in ids
    assert "storm_rain_lasonotheque_2719" in ids
    assert "wake_up_call" in ids
    assert RobineWake.SoundLibrary.available?("storm_rain_lasonotheque_2719")
    assert RobineWake.SoundLibrary.available?("gentle_bell")
  end

  test "does not publish invalid digests, paths, or wave data" do
    original = Application.fetch_env!(:robine_wake, :default_sound_path)
    directory = "tmp/rejected-sounds-#{System.unique_integer([:positive])}"
    Application.put_env(:robine_wake, :default_sound_path, Path.join(directory, "default.wav"))

    on_exit(fn -> Application.put_env(:robine_wake, :default_sound_path, original) end)

    assert {:error, :invalid_size_or_digest} =
             RobineWake.SoundLibrary.import("bad_digest", String.duplicate("x", 64), "short")

    assert {:error, :invalid_sound_id} =
             RobineWake.SoundLibrary.import(
               "../escape",
               String.duplicate("x", 64),
               String.duplicate("0", 64)
             )

    contents = String.duplicate("x", 64)
    digest = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
    assert {:error, :invalid_wave} = RobineWake.SoundLibrary.import("not_audio", contents, digest)
    refute File.exists?(Path.join(directory, "not_audio.wav"))
    assert Path.wildcard(Path.join(directory, "*.tmp")) == []
  end

  test "prefers a persistent MP3 over the bundled copy" do
    original = Application.fetch_env!(:robine_wake, :default_sound_path)
    directory = "tmp/persistent-sounds-#{System.unique_integer([:positive])}"
    persistent = Path.join(directory, "storm_rain_lasonotheque_2719.mp3")
    Application.put_env(:robine_wake, :default_sound_path, Path.join(directory, "default.wav"))
    File.mkdir_p!(directory)
    File.write!(persistent, "persistent recording")

    on_exit(fn -> Application.put_env(:robine_wake, :default_sound_path, original) end)

    assert {:ok, ^persistent} =
             RobineWake.SoundLibrary.path("storm_rain_lasonotheque_2719")
  end
end
