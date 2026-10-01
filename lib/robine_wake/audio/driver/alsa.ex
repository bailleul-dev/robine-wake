defmodule RobineWake.Audio.Driver.Alsa do
  @moduledoc "ALSA adapter intended for a configured HiFiBerry output."
  @behaviour RobineWake.Audio.Driver

  @minimum_audible_db -45.0
  @maximum_safe_db -6.0
  # Music receivers attenuate in software below this hardware level; it is
  # separate from (and may exceed) the wake-audio ceiling above.
  @maximum_music_db -3.0
  alias RobineWake.Audio.MeditationDSP

  @breathing_sound_id "breathing_meditation_ambience"
  @meditation_recording_id "storm_rain_lasonotheque_2719"

  @impl true
  def capabilities do
    case System.find_executable("aplay") do
      nil ->
        %{state: :unavailable, reason: :aplay_not_found}

      path ->
        %{
          state: :available,
          command: path,
          mp3_command: System.find_executable("mpg123"),
          meditation_ambience: :recorded_stereo_with_procedural_fallback,
          device: device()
        }
    end
  end

  @impl true
  def prepare(@breathing_sound_id) do
    case recorded_meditation_command() do
      {:ok, _executable, _args} -> :ok
      {:error, _reason} -> require_executable("aplay", :aplay_not_found)
    end
  end

  def prepare(sound_id) do
    with {:ok, path} <- RobineWake.SoundLibrary.path(sound_id) do
      case Path.extname(path) do
        ".wav" -> require_executable("aplay", :aplay_not_found)
        ".mp3" -> require_executable("mpg123", :mpg123_not_found)
        _ -> {:error, :unsupported_audio_format}
      end
    end
  end

  @impl true
  def play(_session_id, @breathing_sound_id) do
    case recorded_meditation_command() do
      {:ok, executable, args} ->
        player = spawn(fn -> player_loop(executable, args) end)
        {:ok, player}

      {:error, _reason} ->
        case System.find_executable("aplay") do
          nil -> {:error, :meditation_audio_unavailable}
          executable -> start_meditation_player(executable)
        end
    end
  end

  def play(_session_id, sound_id) do
    with {:ok, path} <- RobineWake.SoundLibrary.path(sound_id),
         {:ok, executable, args} <- playback_command(path) do
      player = spawn(fn -> player_loop(executable, args) end)
      {:ok, player}
    end
  end

  defp start_meditation_player(executable) do
    args = meditation_args(device())
    player = spawn(fn -> meditation_player(executable, args) end)
    {:ok, player}
  end

  @impl true
  def set_gain(gain) when gain in 0..100 do
    case System.find_executable("amixer") do
      nil ->
        {:error, :amixer_not_found}

      amixer ->
        {_output, status} =
          System.cmd(amixer, amixer_args(gain), stderr_to_stdout: true)

        if status == 0, do: :ok, else: {:error, {:amixer_exit, status}}
    end
  end

  @impl true
  def set_music_level(decibels) do
    case System.find_executable("amixer") do
      nil ->
        {:error, :amixer_not_found}

      amixer ->
        {_output, status} =
          System.cmd(amixer, music_level_args(decibels), stderr_to_stdout: true)

        if status == 0, do: :ok, else: {:error, {:amixer_exit, status}}
    end
  end

  @impl true
  def stop(player) when is_pid(player) do
    send(player, :stop)
    :ok
  end

  def stop(_), do: :ok

  @impl true
  def status, do: capabilities()

  @doc false
  def amixer_gain(0), do: "0%"

  def amixer_gain(gain) when gain in 1..100 do
    ceiling = Application.fetch_env!(:robine_wake, :audio_safety_ceiling)
    bounded_gain = min(gain, ceiling)
    ratio = (bounded_gain - 1) / max(ceiling - 1, 1)
    decibels = @minimum_audible_db + ratio * (@maximum_safe_db - @minimum_audible_db)
    :erlang.float_to_binary(decibels, decimals: 1) <> "dB"
  end

  @doc false
  def amixer_args(gain) when gain in 0..100 do
    ["-D", mixer_device(), "--", "sset", mixer_control(), amixer_gain(gain)]
  end

  @doc false
  def music_level_args(decibels) do
    level = :erlang.float_to_binary(min(decibels / 1, @maximum_music_db), decimals: 1) <> "dB"
    ["-D", mixer_device(), "--", "sset", mixer_control(), level]
  end

  @doc false
  def meditation_args(device) do
    [
      "--quiet",
      "--device",
      device,
      "--format",
      "S16_LE",
      "--channels",
      "2",
      "--rate",
      Integer.to_string(MeditationDSP.sample_rate()),
      "--file-type",
      "raw"
    ]
  end

  defp device do
    case Application.get_env(:robine_wake, :alsa_device, "default") do
      "auto" -> detected_hifiberry_device() || "default"
      configured -> configured
    end
  end

  @doc false
  def output_device, do: device()

  @doc false
  def mixer_device do
    case device() do
      "plughw:" <> card -> "hw:" <> card
      other -> other
    end
  end

  defp mixer_control,
    do: Application.get_env(:robine_wake, :alsa_mixer_control, "Digital")

  defp detected_hifiberry_device do
    case File.read("/proc/asound/cards") do
      {:ok, cards} -> find_hifiberry_device(cards)
      _error -> nil
    end
  end

  defp find_hifiberry_device(cards) do
    cards
    |> String.split("\n")
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(&hifiberry_card/1)
  end

  defp hifiberry_card([header, details]) do
    if String.contains?(String.downcase(header <> details), "hifiberry") do
      extract_alsa_card(header)
    end
  end

  defp extract_alsa_card(header) do
    case Regex.run(~r/^\s*(\d+)\s+\[/, header) do
      [_, card] -> "plughw:" <> card
      _no_match -> nil
    end
  end

  defp playback_command(path) do
    case Path.extname(path) do
      ".wav" ->
        executable_command("aplay", :aplay_not_found, ["--quiet", "--device", device(), path])

      ".mp3" ->
        executable_command("mpg123", :mpg123_not_found, [
          "--quiet",
          "--audiodevice",
          device(),
          path
        ])

      _ ->
        {:error, :unsupported_audio_format}
    end
  end

  defp recorded_meditation_command do
    with {:ok, path} <- RobineWake.SoundLibrary.path(@meditation_recording_id) do
      playback_command(path)
    end
  end

  defp executable_command(name, missing_reason, args) do
    case System.find_executable(name) do
      nil -> {:error, missing_reason}
      executable -> {:ok, executable, args}
    end
  end

  defp require_executable(name, reason) do
    if System.find_executable(name), do: :ok, else: {:error, reason}
  end

  defp player_loop(executable, args) do
    Process.flag(:trap_exit, true)

    case MuonTrap.Daemon.start_link(executable, args,
           stderr_to_stdout: true,
           log_output: :debug,
           log_prefix: "Alarm audio: ",
           delay_to_sigkill: 500
         ) do
      {:ok, daemon} -> wait_for_player(daemon, executable, args)
      {:error, _reason} -> :ok
    end
  end

  defp meditation_player(executable, args) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        args: args
      ])

    seed = :erlang.unique_integer([:positive, :monotonic])
    meditation_loop(port, MeditationDSP.initial_state(seed))
  catch
    :error, _reason -> :ok
  end

  defp meditation_loop(port, dsp_state) do
    receive do
      :stop ->
        safe_close_port(port)

      {^port, {:exit_status, _status}} ->
        :ok

      {^port, {:data, _output}} ->
        meditation_loop(port, dsp_state)
    after
      0 ->
        {pcm, next_dsp_state} = MeditationDSP.render(dsp_state, 1_024)

        if Port.command(port, pcm) do
          meditation_loop(port, next_dsp_state)
        end
    end
  catch
    :error, _reason -> :ok
  end

  defp safe_close_port(port) do
    Port.close(port)
  catch
    :error, _reason -> :ok
  end

  defp wait_for_player(daemon, executable, args) do
    receive do
      :stop ->
        safe_stop_daemon(daemon)

      {:EXIT, ^daemon, :normal} ->
        player_loop(executable, args)

      {:EXIT, ^daemon, _reason} ->
        :ok
    end
  end

  defp safe_stop_daemon(daemon) do
    if Process.alive?(daemon), do: GenServer.stop(daemon, :normal, 1_500)
  catch
    :exit, _reason -> :ok
  end
end
