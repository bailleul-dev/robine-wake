defmodule RobineWake.Audio.Driver.AlsaTest do
  use ExUnit.Case, async: true

  alias RobineWake.Audio.Driver.Alsa

  test "maps logical alarm gain to the audible HiFiBerry dB window" do
    assert Alsa.amixer_gain(0) == "0%"
    assert Alsa.amixer_gain(1) == "-45.0dB"
    assert Alsa.amixer_gain(15) == "-39.5dB"
    assert Alsa.amixer_gain(70) == "-17.8dB"
    assert Alsa.amixer_gain(80) == "-13.9dB"
  end

  test "clamps a driver-level gain above the application safety ceiling" do
    assert Alsa.amixer_gain(100) == "-6.0dB"
  end

  test "terminates amixer option parsing before a negative dB value" do
    assert ["-D", _device, "--", "sset", "Digital", "-39.5dB"] = Alsa.amixer_args(15)
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
