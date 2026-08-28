defmodule RobineWake.Camera.Driver.Rpi do
  @moduledoc "Raspberry Pi libcamera adapter producing grayscale frames from YUV420."
  @behaviour RobineWake.Camera.Driver

  @width 320
  @height 240

  @impl true
  def capabilities do
    case executable() do
      nil ->
        %{state: :unavailable, reason: :rpicam_still_not_found}

      command ->
        %{
          state: device_state(),
          kind: :libcamera_ir,
          command: command,
          formats: [:grayscale8],
          resolution: %{width: @width, height: @height}
        }
    end
  end

  @impl true
  def health do
    Map.put(capabilities(), :device_present, camera_device_present?())
  end

  @impl true
  def capture(opts) do
    width = Keyword.get(opts, :width, @width)
    height = Keyword.get(opts, :height, @height)

    with command when is_binary(command) <- executable(),
         true <- camera_device_present?(),
         {output, 0} <-
           System.cmd(command, [
             "--nopreview",
             "--immediate",
             "--timeout",
             "1",
             "--width",
             Integer.to_string(width),
             "--height",
             Integer.to_string(height),
             "--encoding",
             "yuv420",
             "--output",
             "-"
           ]),
         true <- byte_size(output) >= width * height do
      luma = binary_part(output, 0, width * height)

      {:ok,
       %{
         pixels: luma,
         width: width,
         height: height,
         quality: image_quality(luma),
         captured_at_monotonic: RobineWake.Clock.monotonic_ms(),
         profile_revision: 1
       }}
    else
      nil -> {:error, :rpicam_still_not_found}
      false -> {:error, :camera_not_detected}
      {_output, status} -> {:error, {:capture_exit, status}}
    end
  end

  defp executable,
    do: System.find_executable("rpicam-still") || System.find_executable("libcamera-still")

  defp camera_device_present?,
    do: File.exists?("/dev/media0") or File.exists?("/dev/video0")

  defp device_state, do: if(camera_device_present?(), do: :available, else: :unavailable)

  defp image_quality(pixels) do
    {sum, dark, bright} =
      for <<value <- pixels>>, reduce: {0, 0, 0} do
        {sum, dark, bright} ->
          {sum + value, dark + if(value < 4, do: 1, else: 0),
           bright + if(value > 251, do: 1, else: 0)}
      end

    count = byte_size(pixels)
    mean = sum / max(count, 1)
    saturated_ratio = (dark + bright) / max(count, 1)

    cond do
      saturated_ratio > 0.7 -> :unusable
      mean < 8 or mean > 247 -> :poor
      true -> :good
    end
  end
end
