defmodule RobineWake.BluetoothAudioTest do
  use ExUnit.Case, async: false

  alias RobineWake.BluetoothAudio

  @child RobineWake.BluetoothAudio

  setup do
    original = %{
      enabled: Application.fetch_env!(:robine_wake, :bluetooth_audio_enabled),
      restart_delay: Application.fetch_env!(:robine_wake, :bluetooth_audio_restart_delay_ms)
    }

    on_exit(fn ->
      :ok = Supervisor.terminate_child(RobineWake.Supervisor, @child)
      Application.put_env(:robine_wake, :bluetooth_audio_enabled, original.enabled)

      Application.put_env(
        :robine_wake,
        :bluetooth_audio_restart_delay_ms,
        original.restart_delay
      )

      {:ok, _pid} = Supervisor.restart_child(RobineWake.Supervisor, @child)
    end)

    :ok
  end

  test "is disabled on the host and accepts alarm arbitration calls" do
    restart(enabled: false)

    assert %{state: :disabled, protocol: :a2dp_sink} = BluetoothAudio.status()
    assert :ok = BluetoothAudio.suspend()
    assert :ok = BluetoothAudio.resume()
  end

  test "reports a missing stack and keeps retrying without crashing" do
    restart(enabled: true)
    pid = Process.whereis(@child)

    assert_eventually(fn ->
      match?(
        %{state: :starting, reason: {:executable_not_found, _path}},
        BluetoothAudio.status()
      )
    end)

    assert :ok = BluetoothAudio.suspend()
    assert :ok = BluetoothAudio.resume()
    assert Process.whereis(@child) == pid
  end

  test "advertises every open codec as an A2DP sink" do
    assert BluetoothAudio.bluealsa_args() == [
             "--profile=a2dp-sink",
             "--loglevel=info",
             "--codec=aac",
             "--codec=aptx",
             "--codec=aptx-hd"
           ]

    assert %{codecs: ["sbc", "aac", "aptx", "aptx-hd"]} = BluetoothAudio.status()
  end

  test "plays through software volume under a fixed hardware ceiling" do
    assert BluetoothAudio.player_args("plughw:0") == [
             "--pcm=plughw:0",
             "--volume=software",
             "--single-audio",
             "--loglevel=info"
           ]

    assert BluetoothAudio.mixer_args("hw:0", "Digital", -20) ==
             ["-D", "hw:0", "--", "sset", "Digital", "-20.0dB"]
  end

  defp restart(enabled: enabled) do
    :ok = Supervisor.terminate_child(RobineWake.Supervisor, @child)
    Application.put_env(:robine_wake, :bluetooth_audio_enabled, enabled)
    Application.put_env(:robine_wake, :bluetooth_audio_restart_delay_ms, 10)
    {:ok, _pid} = Supervisor.restart_child(RobineWake.Supervisor, @child)
  end

  defp assert_eventually(assertion, attempts \\ 50)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      assert true
    else
      Process.sleep(10)
      assert_eventually(assertion, attempts - 1)
    end
  end

  defp assert_eventually(_assertion, 0), do: flunk("condition was not met before timeout")
end
