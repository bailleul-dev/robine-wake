defmodule RobineWake.Audio.RainDSP do
  @moduledoc """
  Stateful, deterministic synthesis of rain falling through a wet leafy canopy.

  The engine combines a diffuse, band-limited bed with marked stochastic events.
  Event families remain separate so they can be inspected and calibrated locally.
  """

  import Bitwise

  @sample_rate 48_000
  @two_pi 2.0 * :math.pi()
  @uint32_mask 0xFFFF_FFFF
  @drip_pans {-0.82, -0.48, -0.17, 0.22, 0.53, 0.79}

  @components [:rain_bed, :rain_leaf, :rain_splash, :rain_direct, :rain_drip, :rain_wood]

  @type component ::
          :rain_bed | :rain_leaf | :rain_splash | :rain_direct | :rain_drip | :rain_wood

  @type voice :: tuple()

  @type state :: map()

  def sample_rate, do: @sample_rate
  def components, do: @components

  @spec initial_state(integer(), keyword()) :: state()
  def initial_state(seed, options \\ []) do
    intensity = Keyword.get(options, :intensity, 3.5)
    wetness = Keyword.get(options, :wetness, 0.62)

    unless is_number(intensity) and intensity > 0.0 and intensity <= 50.0 do
      raise ArgumentError, "rain intensity must be in ]0, 50] mm/h"
    end

    unless is_number(wetness) and wetness >= 0.0 and wetness <= 1.0 do
      raise ArgumentError, "canopy wetness must be between 0 and 1"
    end

    %{
      index: 0,
      random: nonzero_seed(seed),
      intensity: intensity * 1.0,
      wetness: wetness * 1.0,
      macro_noise: 0.0,
      bed_near_left: 0.0,
      bed_near_right: 0.0,
      bed_far_left: 0.0,
      bed_far_right: 0.0,
      leaf: [],
      splash: [],
      direct: [],
      drip: [],
      wood: []
    }
  end

  @doc "Returns one stereo frame per rain component and the next engine state."
  @spec frame(state()) :: {%{component() => {float(), float()}}, state()}
  def frame(state) do
    {weather_noise, random} = white_noise(state.random)
    {bed_noise_left, random} = white_noise(random)
    {bed_noise_right, random} = white_noise(random)

    macro_noise = state.macro_noise * 0.9996 + weather_noise * 0.0004
    seconds = state.index / @sample_rate

    weather =
      clamp(
        0.84 + 0.16 * :math.sin(@two_pi * seconds / 17.3) +
          0.08 * :math.sin(@two_pi * seconds / 5.7) + macro_noise * 2.2,
        0.42,
        1.35
      )

    target_wetness = clamp(0.42 + state.intensity / 13.0, 0.0, 1.0)
    wetness_rate = if target_wetness > state.wetness, do: 0.000_001_7, else: 0.000_000_25
    wetness = state.wetness + (target_wetness - state.wetness) * wetness_rate

    # Two correlated low-pass paths form the distant forest bed.  Most energy is
    # deliberately kept below 3 kHz; the residual high band only restores air.
    common_bed_noise = (bed_noise_left + bed_noise_right) * 0.5
    bed_input_left = common_bed_noise * 0.82 + bed_noise_left * 0.18
    bed_input_right = common_bed_noise * 0.82 + bed_noise_right * 0.18
    bed_near_left = state.bed_near_left + 0.095 * (bed_input_left - state.bed_near_left)
    bed_near_right = state.bed_near_right + 0.095 * (bed_input_right - state.bed_near_right)
    bed_far_left = state.bed_far_left + 0.021 * (bed_input_left - state.bed_far_left)
    bed_far_right = state.bed_far_right + 0.021 * (bed_input_right - state.bed_far_right)

    bed_gain = 0.040 * :math.sqrt(state.intensity / 3.5) * weather

    bed_left =
      (bed_far_left * 1.05 + (bed_near_left - bed_far_left) * 0.38 +
         (bed_input_left - bed_near_left) * 0.002) * bed_gain

    bed_right =
      (bed_far_right * 1.05 + (bed_near_right - bed_far_right) * 0.38 +
         (bed_input_right - bed_near_right) * 0.002) * bed_gain

    {event_random, random} = uniform(random)
    rates = event_rates(state.intensity, wetness, weather)
    {family, random} = select_event(event_random, rates, random)

    state = %{state | random: random}
    state = if family, do: start_voice(state, family), else: state

    {{leaf_left, leaf_right}, leaf} = render_voices(state.leaf)
    {{splash_left, splash_right}, splash} = render_voices(state.splash)
    {{direct_left, direct_right}, direct} = render_voices(state.direct)
    {{drip_left, drip_right}, drip} = render_voices(state.drip)
    {{wood_left, wood_right}, wood} = render_voices(state.wood)

    components = %{
      rain_bed: {bed_left, bed_right},
      rain_leaf: {leaf_left, leaf_right},
      rain_splash: {splash_left, splash_right},
      rain_direct: {direct_left, direct_right},
      rain_drip: {drip_left, drip_right},
      rain_wood: {wood_left, wood_right}
    }

    next = %{
      state
      | index: state.index + 1,
        wetness: wetness,
        macro_noise: macro_noise,
        bed_near_left: bed_near_left,
        bed_near_right: bed_near_right,
        bed_far_left: bed_far_left,
        bed_far_right: bed_far_right,
        leaf: leaf,
        splash: splash,
        direct: direct,
        drip: drip,
        wood: wood
    }

    {components, next}
  end

  defp event_rates(intensity, wetness, weather) do
    scale = :math.sqrt(intensity / 3.5) * weather

    [
      leaf: 13.5 * scale,
      splash: 7.0 * scale * (0.72 + 0.28 * wetness),
      direct: 2.7 * scale,
      drip: 0.85 * scale * wetness * wetness,
      wood: 0.35 * scale * (0.65 + 0.35 * wetness)
    ]
  end

  defp select_event(random, rates, seed) do
    scaled = random * @sample_rate

    family =
      Enum.reduce_while(rates, 0.0, fn {family, rate}, cumulative ->
        next = cumulative + rate

        if scaled < next,
          do: {:halt, family},
          else: {:cont, next}
      end)

    {if(is_atom(family), do: family), seed}
  end

  defp start_voice(state, family) do
    {size_random, random} = uniform(state.random)
    {tone_random, random} = uniform(random)
    {pan_random, random} = uniform(random)
    {distance_random, random} = uniform(random)

    diameter = diameter(family, size_random)
    energy = :math.pow(diameter / 4.5, 1.35)
    profile = voice_profile(family, tone_random, energy)
    pan = event_pan(family, pan_random)
    distance = 0.55 + distance_random * 0.45
    noise_seed = random
    {_unused, random} = uniform(random)
    voice = make_voice(profile, pan, distance, tone_random, noise_seed)

    key = family_key(family)
    %{state | random: random} |> Map.update!(key, &[voice | &1])
  end

  defp diameter(:drip, random), do: 3.2 + 2.5 * :math.sqrt(random)
  defp diameter(:wood, random), do: 1.8 + 2.7 * random
  defp diameter(:leaf, random), do: 0.65 + 2.5 * :math.pow(random, 1.8)
  defp diameter(:splash, random), do: 0.25 + 1.15 * random
  defp diameter(:direct, random), do: 0.5 + 2.8 * :math.pow(random, 1.7)

  defp voice_profile(:leaf, random, energy) do
    base = 1_650.0 + random * 1_450.0

    {0.019 + 0.025 * energy, base, 0.9940, base * (1.72 + 0.22 * random), 0.9890, 0.10, 3.00,
     0.955}
  end

  defp voice_profile(:splash, random, energy) do
    base = 3_400.0 + random * 3_600.0
    {0.010 + 0.018 * energy, base, 0.9850, base * 1.41, 0.9780, 0.02, 3.20, 0.975}
  end

  defp voice_profile(:direct, random, energy) do
    base = 2_250.0 + random * 2_800.0
    {0.013 + 0.027 * energy, base, 0.9890, base * 1.83, 0.9820, 0.06, 2.80, 0.940}
  end

  defp voice_profile(:drip, random, energy) do
    base = 520.0 + random * 780.0

    {0.024 + 0.035 * energy, base, 0.9955, base * (2.15 + 0.45 * random), 0.9915, 0.07, 2.00,
     0.965}
  end

  defp voice_profile(:wood, random, energy) do
    base = 310.0 + random * 620.0

    {0.007 + 0.012 * energy, base, 0.9940, base * (2.0 + 0.35 * random), 0.9880, 0.20, 0.25,
     0.900}
  end

  defp make_voice(
         {amplitude, frequency1, decay1, frequency2, decay2, modal_mix, attack_mix, attack_decay},
         pan,
         distance,
         phase,
         noise_seed
       ) do
    phase1 = phase * @two_pi
    phase2 = :math.fmod(phase1 * 1.618 + 0.71, @two_pi)

    {amplitude, phase1, @two_pi * frequency1 / @sample_rate, decay1, amplitude * 0.46, phase2,
     @two_pi * min(frequency2, 18_000.0) / @sample_rate, decay2, modal_mix, pan, distance,
     amplitude * attack_mix, attack_decay, noise_seed, 0.0}
  end

  defp render_voices(voices) do
    Enum.reduce(voices, {{0.0, 0.0}, []}, fn voice, {{left, right}, active} ->
      {sample, next_voice} = render_voice(voice)
      pan = elem(voice, 9)
      distance = elem(voice, 10)
      left_gain = :math.sqrt((1.0 - pan) * 0.5) * distance
      right_gain = :math.sqrt((1.0 + pan) * 0.5) * distance

      next_active =
        if max(max(elem(next_voice, 0), elem(next_voice, 4)), elem(next_voice, 11)) >
             0.000_035,
           do: [next_voice | active],
           else: active

      {{left + sample * left_gain, right + sample * right_gain}, next_active}
    end)
  end

  defp render_voice(
         {amp1, phase1, step1, decay1, amp2, phase2, step2, decay2, modal_mix, pan, distance,
          attack, attack_decay, noise_seed, noise_memory}
       ) do
    {noise, next_noise_seed} = white_noise(noise_seed)
    modal = (:math.sin(phase1) * amp1 + :math.sin(phase2) * amp2) * modal_mix
    coloured_noise = noise * 0.10 + noise_memory * 0.90
    transient = coloured_noise * attack
    sample = modal + transient

    next =
      {amp1 * decay1, :math.fmod(phase1 + step1, @two_pi), step1, decay1, amp2 * decay2,
       :math.fmod(phase2 + step2, @two_pi), step2, decay2, modal_mix, pan, distance,
       attack * attack_decay, attack_decay, next_noise_seed, coloured_noise}

    {sample, next}
  end

  defp event_pan(:drip, random) do
    index = min(trunc(random * tuple_size(@drip_pans)), tuple_size(@drip_pans) - 1)
    elem(@drip_pans, index)
  end

  defp event_pan(:wood, random), do: -0.75 + trunc(random * 5) * 0.375
  defp event_pan(_family, random), do: -0.92 + random * 1.84

  defp family_key(:leaf), do: :leaf
  defp family_key(:splash), do: :splash
  defp family_key(:direct), do: :direct
  defp family_key(:drip), do: :drip
  defp family_key(:wood), do: :wood

  defp white_noise(seed) do
    {uniform, next} = uniform(seed)
    {uniform * 2.0 - 1.0, next}
  end

  defp uniform(seed) do
    x1 = bxor(seed, seed <<< 13 &&& @uint32_mask)
    x2 = bxor(x1, x1 >>> 17)
    next = bxor(x2, x2 <<< 5 &&& @uint32_mask) &&& @uint32_mask
    {next / @uint32_mask, nonzero_seed(next)}
  end

  defp clamp(value, minimum, maximum), do: value |> max(minimum) |> min(maximum)
  defp nonzero_seed(0), do: 0xA341_316C
  defp nonzero_seed(seed), do: seed &&& @uint32_mask
end
