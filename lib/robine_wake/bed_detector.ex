defmodule RobineWake.BedDetector do
  @moduledoc "Low-cost grayscale foreground detector for the MVP."

  @default %{pixel_threshold: 28, occupied_ratio: 0.12, vacant_ratio: 0.04}

  def observe(frame, background, opts \\ %{})

  def observe(%{quality: :unusable} = frame, _background, _opts),
    do: unknown(frame, :unusable_image)

  def observe(%{pixels: pixels, width: width, height: height} = frame, background, opts)
      when is_binary(pixels) and is_binary(background) and
             byte_size(pixels) == byte_size(background) and
             byte_size(pixels) == width * height do
    config = Map.merge(@default, Map.new(opts))
    indices = roi_indices(width, height, Map.get(frame, :roi))
    {different, total_delta, count} = compare(pixels, background, indices, config.pixel_threshold)

    ratio = safe_div(different, count)
    motion = safe_div(total_delta, count * 255)

    {state, confidence} =
      cond do
        ratio >= config.occupied_ratio ->
          {:occupied, confidence_above(ratio, config.occupied_ratio)}

        ratio <= config.vacant_ratio ->
          {:vacant, confidence_below(ratio, config.vacant_ratio)}

        true ->
          {:unknown, 0.5}
      end

    %{
      state: state,
      confidence: Float.round(confidence, 3),
      motion_score: Float.round(motion, 3),
      foreground_ratio: Float.round(ratio, 3),
      quality: Map.get(frame, :quality, :good),
      captured_at_monotonic: Map.get(frame, :captured_at_monotonic),
      profile_revision: Map.get(frame, :profile_revision, 1)
    }
  end

  def observe(frame, _background, _opts), do: unknown(frame, :invalid_frame)

  defp compare(pixels, background, indices, threshold) do
    Enum.reduce(indices, {0, 0, 0}, fn index, {different, delta_sum, count} ->
      delta = abs(:binary.at(pixels, index) - :binary.at(background, index))
      {different + if(delta >= threshold, do: 1, else: 0), delta_sum + delta, count + 1}
    end)
  end

  defp roi_indices(width, height, nil), do: 0..(width * height - 1)

  defp roi_indices(width, height, %{polygon: points}) when is_list(points) do
    points = Enum.map(points, &point/1)

    if length(points) >= 3 and Enum.all?(points, &match?({_, _}, &1)) do
      for row <- 0..(height - 1),
          column <- 0..(width - 1),
          inside_polygon?({column + 0.5, row + 0.5}, points),
          do: row * width + column
    else
      []
    end
  end

  defp roi_indices(width, height, %{x: x, y: y, width: roi_width, height: roi_height}) do
    for row <- y..min(y + roi_height - 1, height - 1),
        column <- x..min(x + roi_width - 1, width - 1),
        row >= 0 and column >= 0,
        do: row * width + column
  end

  defp roi_indices(_width, _height, _invalid), do: []

  defp point([x, y]) when is_number(x) and is_number(y), do: {x, y}
  defp point(%{x: x, y: y}) when is_number(x) and is_number(y), do: {x, y}
  defp point(_), do: :invalid

  defp inside_polygon?({x, y}, points) do
    points
    |> Enum.zip(tl(points) ++ [hd(points)])
    |> Enum.reduce(false, fn {{x1, y1}, {x2, y2}}, inside ->
      crosses =
        y1 > y != y2 > y and
          x < (x2 - x1) * (y - y1) / (y2 - y1) + x1

      if crosses, do: not inside, else: inside
    end)
  end

  defp unknown(frame, reason) do
    %{
      state: :unknown,
      confidence: 0.0,
      motion_score: 0.0,
      foreground_ratio: 0.0,
      quality: Map.get(frame, :quality, :unusable),
      reason: reason,
      captured_at_monotonic: Map.get(frame, :captured_at_monotonic),
      profile_revision: Map.get(frame, :profile_revision, 1)
    }
  end

  defp safe_div(_a, 0), do: 0.0
  defp safe_div(a, b), do: a / b

  defp confidence_above(ratio, threshold),
    do: min(1.0, 0.5 + (ratio - threshold) / max(0.01, 1.0 - threshold))

  defp confidence_below(ratio, threshold),
    do: min(1.0, 0.75 + (threshold - ratio) / max(0.01, threshold) * 0.25)
end
