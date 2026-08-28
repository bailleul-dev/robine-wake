defmodule RobineWake.Audio.MeditationDSP do
  @moduledoc "Procedural stereo soundscape used by guided evening sessions."

  import Bitwise

  alias RobineWake.Audio.RainDSP

  @sample_rate RainDSP.sample_rate()
  @two_pi 2.0 * :math.pi()
  @pcm_scale 28_000
  @uint32_mask 0xFFFF_FFFF
  @rain_components RainDSP.components()
  @production_layers [:pad, :rain]
  @layers [:air, :pad, :rain] ++ @rain_components

  @type pink_state :: {float(), float(), float(), float(), float(), float(), float()}
  @type state :: %{
          index: non_neg_integer(),
          random_left: non_neg_integer(),
          random_right: non_neg_integer(),
          pink_left: pink_state(),
          pink_right: pink_state(),
          wind_left: float(),
          wind_right: float(),
          rain: RainDSP.state()
        }

  def sample_rate, do: @sample_rate

  @doc false
  @spec initial_state(integer()) :: state()
  def initial_state(seed \\ 0x4D45_4449) do
    left = nonzero_seed(seed)
    right = nonzero_seed(bxor(left, 0x9E37_79B9))

    %{
      index: 0,
      random_left: left,
      random_right: right,
      pink_left: empty_pink(),
      pink_right: empty_pink(),
      wind_left: 0.0,
      wind_right: 0.0,
      rain: RainDSP.initial_state(bxor(left, 0x5241_494E))
    }
  end

  @doc false
  @spec render(state(), pos_integer()) :: {binary(), state()}
  def render(state, frame_count) when frame_count > 0 do
    render(state, frame_count, @production_layers)
  end

  @doc "Renders selected soundscape layers; production uses all layers."
  @spec render(state(), pos_integer(), [atom()]) :: {binary(), state()}
  def render(state, frame_count, layers)
      when frame_count > 0 and is_list(layers) do
    if layers == [] or Enum.any?(layers, &(&1 not in @layers)) do
      raise ArgumentError,
            "layers must contain one or more of: " <> Enum.join(@layers, ", ")
    end

    render_frames(frame_count, state, MapSet.new(layers), [])
  end

  defp render_frames(0, state, _layers, frames),
    do: {frames |> Enum.reverse() |> IO.iodata_to_binary(), state}

  defp render_frames(remaining, state, layers, frames) do
    {white_left, random_left} = white_noise(state.random_left)
    {white_right, random_right} = white_noise(state.random_right)
    {pink_left, pink_state_left} = pink_noise(white_left, state.pink_left)
    {pink_right, pink_state_right} = pink_noise(white_right, state.pink_right)

    # Long smoothing and a stronger filtered component keep the wind dark and
    # broad instead of turning into a bright hiss on a small bedroom speaker.
    wind_left = state.wind_left * 0.986 + pink_left * 0.014
    wind_right = state.wind_right * 0.983 + pink_right * 0.017
    seconds = state.index / @sample_rate

    cycle_position = :math.fmod(seconds, 10.0)

    breathing_progress =
      if cycle_position < 4.0,
        do: cycle_position / 4.0,
        else: 1.0 - (cycle_position - 4.0) / 6.0

    breathing_curve =
      breathing_progress * breathing_progress * (3.0 - 2.0 * breathing_progress)

    wind_tide = 0.72 + 0.20 * :math.sin(@two_pi * seconds / 31.0)
    stereo_tide = 0.06 * :math.sin(@two_pi * seconds / 47.0)

    # The cue remains clear, but leaves less distance between inhale and exhale.
    air_breath = 0.44 + 0.56 * breathing_curve

    air_left =
      (pink_left * 0.30 + wind_left * 0.70) * (wind_tide + stereo_tide) * air_breath

    air_right =
      (pink_right * 0.30 + wind_right * 0.70) * (wind_tide - stereo_tide) * air_breath

    rain_breath = 0.82 + 0.18 * breathing_curve
    {rain_components, rain_state} = RainDSP.frame(state.rain)
    {rain_left, rain_right} = rain_mix(rain_components, layers)

    # An open D/A sonority deliberately avoids a major/minor emotional cue.
    pad_tide = 0.72 + 0.18 * :math.sin(@two_pi * seconds / 73.0)
    d3 = :math.sin(@two_pi * 146.832 * seconds)
    a3 = :math.sin(@two_pi * 220.000 * seconds + 0.31)
    d4 = :math.sin(@two_pi * 293.665 * seconds + 1.07)

    slow_halo =
      :math.sin(@two_pi * 440.000 * seconds + 0.4) *
        (0.5 + 0.5 * :math.sin(@two_pi * seconds / 59.0))

    pad_left = pad_tide * (d3 * 0.16 + a3 * 0.085 + d4 * 0.035) + slow_halo * 0.018
    pad_right = pad_tide * (d3 * 0.145 + a3 * 0.10 - d4 * 0.03) - slow_halo * 0.018

    left =
      pcm(
        layer(layers, :air, air_left * 0.78) +
          layer(layers, :pad, pad_left) +
          rain_left * rain_breath * 7.0
      )

    right =
      pcm(
        layer(layers, :air, air_right * 0.78) +
          layer(layers, :pad, pad_right) +
          rain_right * rain_breath * 7.0
      )

    next = %{
      state
      | index: state.index + 1,
        random_left: random_left,
        random_right: random_right,
        pink_left: pink_state_left,
        pink_right: pink_state_right,
        wind_left: wind_left,
        wind_right: wind_right,
        rain: rain_state
    }

    render_frames(remaining - 1, next, layers, [
      <<left::little-signed-16, right::little-signed-16>> | frames
    ])
  end

  defp layer(layers, name, value), do: if(MapSet.member?(layers, name), do: value, else: 0.0)

  defp rain_mix(components, layers) do
    enabled =
      if MapSet.member?(layers, :rain),
        do: @rain_components,
        else: Enum.filter(@rain_components, &MapSet.member?(layers, &1))

    Enum.reduce(enabled, {0.0, 0.0}, fn component, {left, right} ->
      {component_left, component_right} = Map.fetch!(components, component)
      {left + component_left, right + component_right}
    end)
  end

  defp pink_noise(
         white,
         {old0, old1, old2, old3, old4, old5, old6}
       ) do
    b0 = 0.99886 * old0 + white * 0.0555179
    b1 = 0.99332 * old1 + white * 0.0750759
    b2 = 0.96900 * old2 + white * 0.1538520
    b3 = 0.86650 * old3 + white * 0.3104856
    b4 = 0.55000 * old4 + white * 0.5329522
    b5 = -0.7616 * old5 - white * 0.0168980
    pink = (b0 + b1 + b2 + b3 + b4 + b5 + old6 + white * 0.5362) * 0.11
    b6 = white * 0.115926
    {pink, {b0, b1, b2, b3, b4, b5, b6}}
  end

  defp white_noise(seed) do
    x1 = bxor(seed, seed <<< 13 &&& @uint32_mask)
    x2 = bxor(x1, x1 >>> 17)
    next = bxor(x2, x2 <<< 5 &&& @uint32_mask) &&& @uint32_mask
    {next / @uint32_mask * 2.0 - 1.0, nonzero_seed(next)}
  end

  defp pcm(value) do
    value
    |> Kernel.*(@pcm_scale)
    |> round()
    |> min(32_767)
    |> max(-32_768)
  end

  defp nonzero_seed(0), do: 0xA341_316C
  defp nonzero_seed(seed), do: seed &&& @uint32_mask
  defp empty_pink, do: {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}
end
