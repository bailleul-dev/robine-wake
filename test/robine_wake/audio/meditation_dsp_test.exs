defmodule RobineWake.Audio.MeditationDSPTest do
  use ExUnit.Case, async: true

  alias RobineWake.Audio.MeditationDSP

  test "renders bounded, evolving stereo PCM deterministically" do
    state = MeditationDSP.initial_state(12_345)
    {first, next} = MeditationDSP.render(state, 2_048)
    {second, _next} = MeditationDSP.render(next, 2_048)
    {repeat, _repeat_next} = MeditationDSP.render(MeditationDSP.initial_state(12_345), 2_048)

    assert byte_size(first) == 2_048 * 2 * 2
    assert first == repeat
    refute first == second

    frames = for <<left::little-signed-16, right::little-signed-16 <- first>>, do: {left, right}
    assert Enum.any?(frames, fn {left, right} -> left != 0 or right != 0 end)
    assert Enum.any?(frames, fn {left, right} -> left != right end)

    assert Enum.all?(frames, fn {left, right} ->
             left in -32_768..32_767 and right in -32_768..32_767
           end)
  end

  test "isolates each soundscape layer without changing the production mix" do
    state = MeditationDSP.initial_state(12_345)
    {production, _state} = MeditationDSP.render(state, 2_048)
    {full, _state} = MeditationDSP.render(state, 2_048, [:pad, :rain])
    {rain, _state} = MeditationDSP.render(state, 2_048, [:rain])
    {air, _state} = MeditationDSP.render(state, 2_048, [:air])
    {pad, _state} = MeditationDSP.render(state, 2_048, [:pad])
    {leaf, _state} = MeditationDSP.render(state, 48_000, [:rain_leaf])

    assert production == full
    refute rain == production
    refute rain == air
    refute rain == pad
    refute rain == :binary.copy(<<0>>, byte_size(rain))
    refute leaf == :binary.copy(<<0>>, byte_size(leaf))
  end

  test "rejects an empty or unknown layer selection" do
    state = MeditationDSP.initial_state(12_345)
    empty = List.delete([:rain], :rain)

    assert_raise ArgumentError, fn -> MeditationDSP.render(state, 100, empty) end
    assert_raise ArgumentError, fn -> MeditationDSP.render(state, 100, [:ocean]) end
  end
end
