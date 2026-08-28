defmodule RobineWake.Audio.RainDSPTest do
  use ExUnit.Case, async: true

  alias RobineWake.Audio.RainDSP

  test "renders every physical rain family deterministically" do
    state = RainDSP.initial_state(0x5241_494E, intensity: 20.0, wetness: 1.0)

    {first, next} = render(state, RainDSP.sample_rate() * 2)

    {repeat, _repeat_next} =
      render(
        RainDSP.initial_state(0x5241_494E, intensity: 20.0, wetness: 1.0),
        RainDSP.sample_rate() * 2
      )

    assert first == repeat
    assert next.index == RainDSP.sample_rate() * 2

    for component <- RainDSP.components() -- [:rain_wood] do
      samples = Map.fetch!(first, component)
      assert Enum.any?(samples, fn {left, right} -> left != 0.0 or right != 0.0 end)
    end

    assert MapSet.new(RainDSP.components()) ==
             seen_components(RainDSP.initial_state(456_789, intensity: 50.0), 5 * 48_000)
  end

  test "exposes a 48 kHz reference engine and validates its environment" do
    assert RainDSP.sample_rate() == 48_000
    assert_raise ArgumentError, fn -> RainDSP.initial_state(1, intensity: 0) end
    assert_raise ArgumentError, fn -> RainDSP.initial_state(1, wetness: 1.1) end
  end

  test "keeps the bed diffuse while localized impacts vary between channels" do
    {frames, _state} = render(RainDSP.initial_state(123_456), RainDSP.sample_rate())

    leaf = Map.fetch!(frames, :rain_leaf)
    bed = Map.fetch!(frames, :rain_bed)

    assert Enum.any?(leaf, fn {left, right} -> abs(left - right) > 0.000_1 end)
    assert Enum.count(bed, fn {left, right} -> left != 0.0 and right != 0.0 end) > 47_000
  end

  defp render(state, count) do
    Enum.reduce(1..count, {%{}, state}, fn _, {components, current} ->
      {frame, next} = RainDSP.frame(current)

      components =
        Enum.reduce(frame, components, fn {name, stereo}, acc ->
          Map.update(acc, name, [stereo], &[stereo | &1])
        end)

      {components, next}
    end)
    |> then(fn {components, next} ->
      {Map.new(components, fn {name, samples} -> {name, Enum.reverse(samples)} end), next}
    end)
  end

  defp seen_components(state, count) do
    Enum.reduce(1..count, {MapSet.new(), state}, fn _, {seen, current} ->
      {frame, next} = RainDSP.frame(current)

      seen =
        Enum.reduce(frame, seen, fn
          {_name, {left, right}}, acc when left == 0.0 and right == 0.0 -> acc
          {name, _stereo}, acc -> MapSet.put(acc, name)
        end)

      {seen, next}
    end)
    |> elem(0)
  end
end
