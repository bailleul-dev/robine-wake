defmodule RobineWake.BedDetectorTest do
  use ExUnit.Case, async: false

  alias RobineWake.BedDetector

  setup do
    :ok = RobineWake.Camera.reset()
    :ok
  end

  test "classifies a stable background as vacant" do
    background = :binary.copy(<<10>>, 16)
    frame = %{pixels: background, width: 4, height: 4, quality: :good}

    assert %{state: :vacant, confidence: confidence, foreground_ratio: ratio} =
             BedDetector.observe(frame, background)

    assert confidence >= 0.75
    assert ratio == 0.0
  end

  test "classifies foreground mass as occupied" do
    background = :binary.copy(<<0>>, 16)
    pixels = <<255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
    frame = %{pixels: pixels, width: 4, height: 4, quality: :good}

    assert %{state: :occupied, foreground_ratio: ratio} = BedDetector.observe(frame, background)
    assert ratio == 0.25
  end

  test "unusable and malformed frames are unknown" do
    assert %{state: :unknown, reason: :unusable_image} =
             BedDetector.observe(%{quality: :unusable}, <<>>, %{})

    assert %{state: :unknown, reason: :invalid_frame} =
             BedDetector.observe(%{pixels: <<0>>, width: 2, height: 2}, <<0>>, %{})
  end

  test "ignores pixels outside the region of interest" do
    background = :binary.copy(<<0>>, 16)
    pixels = <<255, 255, 0, 0, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>

    frame = %{
      pixels: pixels,
      width: 4,
      height: 4,
      quality: :good,
      roi: %{x: 2, y: 0, width: 2, height: 4}
    }

    assert %{state: :vacant, foreground_ratio: ratio} = BedDetector.observe(frame, background)
    assert ratio == 0.0
  end

  test "ignores pixels outside a polygonal bed region" do
    background = :binary.copy(<<0>>, 16)
    pixels = <<255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0>>

    frame = %{
      pixels: pixels,
      width: 4,
      height: 4,
      quality: :good,
      roi: %{polygon: [[2, 0], [4, 0], [4, 4], [2, 4]]}
    }

    assert %{state: :vacant, foreground_ratio: ratio} = BedDetector.observe(frame, background)
    assert ratio == 0.0
  end

  test "drops duplicated camera frames" do
    background = :binary.copy(<<0>>, 16)
    frame = %{pixels: background, width: 4, height: 4, quality: :good, captured_at_monotonic: 10}

    assert {:ok, _observation} = RobineWake.Camera.submit_frame(frame, background)
    assert {:error, :stale_frame} = RobineWake.Camera.submit_frame(frame, background)
    assert %{dropped_frames: 1} = RobineWake.Camera.status()
  end

  test "camera analysis becomes degraded two seconds after the last frame" do
    background = :binary.copy(<<0>>, 16)
    calibration = %{pixels: background, width: 4, height: 4}
    :ok = RobineWake.Camera.set_background(calibration)

    frame = %{
      pixels: background,
      width: 4,
      height: 4,
      quality: :good,
      captured_at_monotonic: RobineWake.Clock.monotonic_ms() - 2_001
    }

    assert {:ok, _observation} = RobineWake.Camera.submit_frame(frame, background)

    assert %{analysis_health: %{state: :degraded, reason: :stale_frame}} =
             RobineWake.Camera.status()
  end

  test "camera pipeline publishes a detector observation" do
    background = :binary.copy(<<0>>, 16)
    pixels = :binary.copy(<<255>>, 16)

    assert {:ok, %{state: :occupied}} =
             RobineWake.Camera.submit_frame(
               %{pixels: pixels, width: 4, height: 4, quality: :good},
               background
             )

    assert %{last_observation: %{state: :occupied}, frames: frames} =
             RobineWake.Camera.status()

    assert frames >= 1
  end
end
