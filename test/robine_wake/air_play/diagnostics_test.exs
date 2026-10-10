defmodule RobineWake.AirPlay.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias RobineWake.AirPlay.Diagnostics

  @base """
  general =
  {
    name = "Robine Wake Bedroom";
  };

  alsa =
  {
    output_device = "plughw:0";
  };
  """

  describe "config_text/2" do
    test "appends a diagnostics group with the requested verbosity" do
      text = Diagnostics.config_text(@base, 3)

      assert String.starts_with?(text, "general =")
      assert text =~ "diagnostics =\n{\n  log_verbosity = 3;\n  statistics = \"yes\";\n};\n"
    end

    test "replaces an existing diagnostics group instead of duplicating it" do
      base = @base <> "diagnostics =\n{\n  log_verbosity = 1;\n};\n"
      text = Diagnostics.config_text(base, 2)

      assert length(Regex.scan(~r/diagnostics\s*=/, text)) == 1
      assert text =~ "log_verbosity = 2;"
      refute text =~ "log_verbosity = 1;"
    end
  end

  describe "environment/1" do
    test "logs blocks by default and adds the captures on request" do
      assert Diagnostics.environment([]) == [
               {"SPS_DIAG_CONF", "/tmp/shairport-diag.conf"},
               {"SPS_DIAG_LOG", "/tmp/shairport-diag.log"},
               {"SPS_BLOCK_DIAG", "1"}
             ]

      environment = Diagnostics.environment(blocks: false, dump: true, pcm: true)

      refute List.keymember?(environment, "SPS_BLOCK_DIAG", 0)
      assert {"SPS_BLOCK_DUMP", "/tmp/shairport-blocks.bin"} in environment
      assert {"SPS_DIAG_PCM", "/tmp/shairport-pcm.raw"} in environment
    end
  end

  describe "block lines" do
    @silent_line ~s(         1.085 "player.c:1340" BLOCK 51: codec "aac" bytes 13 ret 0 format 8 samples 1024 channels 2 peak 0.000000)
    @audio_line ~s(         0.659 "player.c:1340" BLOCK 851: codec "aac" bytes 609 ret 0 format 8 samples 1024 channels 2 peak 0.111097)
    @failed_line ~s(         0.020 "player.c:1340" BLOCK 1351: codec "alac" bytes 827 ret -11 format -1 samples 0 channels 0 peak 0.000000)

    test "parses the instrumentation line and ignores the others" do
      assert %{number: 851, codec: "aac", bytes: 609, ret: 0, samples: 1024, peak: 0.111097} =
               Diagnostics.parse_block_line(@audio_line)

      assert Diagnostics.parse_block_line(~s|"player.c:4136" Av Sync Error (ms) / Net Sync PPM|) ==
               nil
    end

    test "a stream of tiny silent blocks is blamed on the source" do
      blocks = Enum.map([@silent_line, @silent_line], &Diagnostics.parse_block_line/1)

      assert %{verdict: :source_sends_silence, bytes: %{min: 13, max: 13}, peak: +0.0} =
               Diagnostics.summarize(blocks)
    end

    test "real audio and decoder failures are told apart" do
      assert %{verdict: :audio_present, decode_failures: 0} =
               Diagnostics.summarize([Diagnostics.parse_block_line(@audio_line)])

      assert %{verdict: :decoding_fails, decode_failures: 1, codecs: ["alac"]} =
               Diagnostics.summarize([Diagnostics.parse_block_line(@failed_line)])

      assert Diagnostics.summarize([]) == %{blocks: 0, verdict: :no_blocks}
    end
  end

  describe "PCM measurement" do
    test "finds the peak of little-endian 32-bit samples" do
      samples = <<0::little-signed-32, -1_073_741_824::little-signed-32, 1000::little-signed-32>>

      assert Diagnostics.pcm_peak(samples) == 1_073_741_824
      assert Diagnostics.peak_to_dbfs(1_073_741_824) == -6.0
      assert Diagnostics.peak_to_dbfs(0) == -200.0
    end
  end
end
