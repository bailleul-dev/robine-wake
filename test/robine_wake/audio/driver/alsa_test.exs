defmodule RobineWake.Audio.Driver.AlsaTest do
  use ExUnit.Case, async: true

  alias RobineWake.Audio.Driver.Alsa

  test "maps logical alarm gain to the audible HiFiBerry dB window" do
    assert Alsa.amixer_gain(0) == "0%"
    assert Alsa.amixer_gain(1) == "-45.0dB"
    assert Alsa.amixer_gain(15) == "-38.6dB"
    assert Alsa.amixer_gain(70) == "-13.6dB"
    assert Alsa.amixer_gain(80) == "-9.1dB"
  end

  test "clamps a driver-level gain above the application safety ceiling" do
    assert Alsa.amixer_gain(100) == "0.0dB"
  end

  test "terminates amixer option parsing before a negative dB value" do
    assert ["-D", _device, "--", "sset", "Digital", "-38.6dB"] = Alsa.amixer_args(15)
  end

  test "sets the music level in dB and never above the music maximum" do
    assert ["-D", _device, "--", "sset", "Digital", "-6.0dB"] = Alsa.music_level_args(-6)
    assert ["-D", _device, "--", "sset", "Digital", "0.0dB"] = Alsa.music_level_args(3.0)
  end

  test "configures the procedural stereo meditation stream" do
    assert [
             "--quiet",
             "--device",
             "plughw:0",
             "--format",
             "S16_LE",
             "--channels",
             "2",
             "--rate",
             "48000",
             "--file-type",
             "raw"
           ] = Alsa.meditation_args("plughw:0")
  end

  test "watches the playback substreams of the configured card" do
    assert Alsa.pcm_status_glob("plughw:0") == "/proc/asound/card0/pcm*p/sub*/status"
    assert Alsa.pcm_status_glob("hw:1,0") == "/proc/asound/card1/pcm*p/sub*/status"
    assert Alsa.pcm_status_glob("default") == "/proc/asound/card*/pcm*p/sub*/status"
  end

  @tag :tmp_dir
  test "the output is released only when every substream is closed", %{tmp_dir: dir} do
    closed = Path.join(dir, "closed")
    running = Path.join(dir, "running")
    File.write!(closed, "closed\n")
    File.write!(running, "state: RUNNING\nowner_pid   : 1032\n")

    assert Alsa.output_released?([closed])
    assert Alsa.output_released?([closed, Path.join(dir, "missing")])
    refute Alsa.output_released?([closed, running])
  end
end
