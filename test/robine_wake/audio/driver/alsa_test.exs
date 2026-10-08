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
end
