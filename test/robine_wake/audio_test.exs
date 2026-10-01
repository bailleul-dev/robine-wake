defmodule RobineWake.Audio.FlakyDriver do
  @behaviour RobineWake.Audio.Driver

  @impl true
  def capabilities, do: %{state: :available, device: "flaky-test"}

  @impl true
  def prepare(_sound_id), do: :ok

  @impl true
  def play(session_id, sound_id) do
    Agent.get_and_update(__MODULE__, fn state ->
      next = %{state | attempts: state.attempts + 1}

      if state.remaining_failures > 0 do
        {{:error, :injected_failure}, %{next | remaining_failures: state.remaining_failures - 1}}
      else
        {{:ok, {:test, session_id, sound_id}}, next}
      end
    end)
  end

  @impl true
  def set_gain(_gain), do: :ok

  @impl true
  def set_music_level(decibels) do
    Agent.get_and_update(__MODULE__, fn
      %{music_level_failures: failures} = state when failures > 0 ->
        {{:error, :card_not_ready}, %{state | music_level_failures: failures - 1}}

      state ->
        {:ok, %{state | music_levels: [decibels | state.music_levels]}}
    end)
  end

  @impl true
  def stop(_handle), do: :ok

  @impl true
  def status, do: capabilities()
end

defmodule RobineWake.Audio.AirPlayRecorder do
  def suspend, do: record(:suspend)
  def resume, do: record(:resume)

  def commands, do: Agent.get(__MODULE__, &Enum.reverse/1)

  defp record(command) do
    Agent.update(__MODULE__, &[command | &1])
    :ok
  end
end

defmodule RobineWake.Audio.BrokenReceiver do
  def suspend, do: exit(:timeout)
  def resume, do: raise("receiver crashed")
end

defmodule RobineWake.AudioTest do
  use ExUnit.Case, async: false

  alias RobineWake.Audio
  alias RobineWake.Audio.AirPlayRecorder
  alias RobineWake.Audio.FlakyDriver

  setup do
    original_driver = Application.fetch_env!(:robine_wake, :audio_driver)
    original_delays = Application.fetch_env!(:robine_wake, :audio_retry_delays_ms)
    original_receivers = Application.fetch_env!(:robine_wake, :music_receivers)

    {:ok, agent} =
      Agent.start_link(
        fn ->
          %{remaining_failures: 0, attempts: 0, music_levels: [], music_level_failures: 0}
        end,
        name: FlakyDriver
      )

    {:ok, airplay_agent} =
      Agent.start_link(fn -> [] end, name: AirPlayRecorder)

    Application.put_env(:robine_wake, :audio_driver, FlakyDriver)
    Application.put_env(:robine_wake, :audio_retry_delays_ms, [0, 0, 0, 0])
    Application.put_env(:robine_wake, :music_receivers, [AirPlayRecorder])
    restart_audio()

    on_exit(fn ->
      Application.put_env(:robine_wake, :audio_driver, original_driver)
      Application.put_env(:robine_wake, :audio_retry_delays_ms, original_delays)
      Application.put_env(:robine_wake, :music_receivers, original_receivers)
      restart_audio()
      if Process.alive?(agent), do: Agent.stop(agent)
      if Process.alive?(airplay_agent), do: Agent.stop(airplay_agent)
    end)

    :ok
  end

  test "retries three times after an immediate playback failure" do
    Agent.update(FlakyDriver, fn state ->
      %{state | remaining_failures: 3, attempts: 0}
    end)

    assert :ok = Audio.play("session-a", "default")
    assert Agent.get(FlakyDriver, & &1.attempts) == 4
    assert AirPlayRecorder.commands() == [:suspend]
    assert :ok = Audio.stop("session-a")
    assert AirPlayRecorder.commands() == [:suspend, :resume]
  end

  test "publishes the final error after all playback attempts fail" do
    Agent.update(FlakyDriver, fn state ->
      %{state | remaining_failures: 4, attempts: 0}
    end)

    assert {:error, :injected_failure} = Audio.play("session-b", "default")
    assert Agent.get(FlakyDriver, & &1.attempts) == 4
    assert AirPlayRecorder.commands() == [:suspend, :resume]
    assert %{last_error: :injected_failure, active_session: nil} = Audio.status()
  end

  test "an older or unrelated session cannot replace or stop active audio" do
    assert :ok = Audio.play("session-current", "default")
    assert {:error, :stale_session} = Audio.play("session-old", "default")
    assert :ok = Audio.stop("session-old")
    assert %{active_session: "session-current"} = Audio.status()
    assert :ok = Audio.stop("session-current")
  end

  test "restores the music level at startup and whenever wake audio releases ALSA" do
    assert Agent.get(FlakyDriver, & &1.music_levels) == [-3.0]

    assert :ok = Audio.play("session-d", "default")
    assert Agent.get(FlakyDriver, & &1.music_levels) == [-3.0]

    assert :ok = Audio.stop("session-d")
    assert Agent.get(FlakyDriver, & &1.music_levels) == [-3.0, -3.0]
  end

  test "retries the music level until the sound card is ready" do
    Agent.update(FlakyDriver, &%{&1 | music_levels: [], music_level_failures: 2})
    restart_audio()

    assert_eventually(fn -> Agent.get(FlakyDriver, & &1.music_levels) == [-3.0] end)
  end

  test "a failing music receiver never prevents wake audio" do
    Application.put_env(:robine_wake, :music_receivers, [
      RobineWake.Audio.BrokenReceiver,
      AirPlayRecorder
    ])

    assert :ok = Audio.play("session-c", "default")
    assert AirPlayRecorder.commands() == [:suspend]
    assert :ok = Audio.stop("session-c")
    assert AirPlayRecorder.commands() == [:suspend, :resume]
  end

  defp assert_eventually(assertion, attempts \\ 40)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      assert true
    else
      Process.sleep(100)
      assert_eventually(assertion, attempts - 1)
    end
  end

  defp assert_eventually(_assertion, 0), do: flunk("condition was not met before timeout")

  defp restart_audio do
    :ok = Supervisor.terminate_child(RobineWake.Supervisor, RobineWake.Audio)
    {:ok, _pid} = Supervisor.restart_child(RobineWake.Supervisor, RobineWake.Audio)
    :ok
  end
end
