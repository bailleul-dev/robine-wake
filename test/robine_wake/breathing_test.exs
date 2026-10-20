defmodule RobineWake.BreathingTest do
  use RobineWake.DomainCase

  alias RobineWake.GuideLight.Driver.Test, as: GuideLightDriver

  defp requests do
    # A call is processed after every cast queued before it.
    _ = GuideLight.status()
    GuideLightDriver.requests()
  end

  defp played?(sound) do
    Enum.any?(Audio.status().commands, &match?({:play, _session, ^sound}, &1))
  end

  test "parses the cadence like the ESP32 and counts whole breaths" do
    assert {:ok, %{hold_empty_ms: 0, inhale_ms: 4_000, hold_full_ms: 0, exhale_ms: 6_000}} =
             Breathing.parse_cadence(" 0-4-0-6 ")

    assert {:ok, %{inhale_ms: 4_500, exhale_ms: 5_500}} = Breathing.parse_cadence("0-4.5-0-5.5")

    for text <- ["", "4-6", "0-0-0-6", "0-4-0-0", "0-4-0-6-1", "0-x-0-6", "0-61-0-6", nil] do
      assert Breathing.parse_cadence(text) == :error, inspect(text)
    end

    {:ok, coherence} = Breathing.parse_cadence("0-4-0-6")
    assert Breathing.session_ms(coherence, 5) == 300_000
    {:ok, square} = Breathing.parse_cadence("4-4-4-4")
    # 5 minutes at 16 s a breath: 19 breaths, the last one finished.
    assert Breathing.session_ms(square, 5) == 304_000
  end

  test "breathes on the strip with the ambience, then stops both" do
    assert {:ok,
            %{
              active: true,
              cadence: "0-4-0-6",
              inhale_ms: 4_000,
              exhale_ms: 6_000,
              duration_minutes: 5,
              remaining_seconds: 300,
              volume_percent: 2,
              light: %{active: true},
              audio: %{active: true}
            }} = Breathing.start("0-4-0-6", 5, 2)

    assert [
             {"light.program", %{program: "breathing", cadence: "0-4-0-6", duration_ms: 300_000}}
           ] = requests()

    assert played?("breathing_meditation_ambience")

    assert {:ok, %{active: true, volume_percent: 1}} = Breathing.set_volume(1)
    assert %{gain: 1} = Audio.status()

    assert {:ok, %{active: false}} = Breathing.stop()
    assert List.last(requests()) == {"light.program", %{program: "off"}}
    assert %{active_session: nil} = Audio.status()
  end

  test "rejects a bad cadence, duration or volume" do
    assert {:error, :invalid_cadence} = Breathing.start("4-6", 5, 2)
    assert {:error, :invalid_breathing_duration} = Breathing.start("0-4-0-6", 0, 2)
    assert {:error, :invalid_breathing_duration} = Breathing.start("0-4-0-6", 61, 2)
    assert {:error, :invalid_breathing_volume} = Breathing.start("0-4-0-6", 5, 101)
    assert {:error, :breathing_not_active} = Breathing.set_volume(10)
    assert requests() == []
  end

  test "ends with the last breath: the strip goes dark on its own" do
    assert {:ok, %{active: true}} = Breathing.start("0-4-0-6", 1, 2)

    %{session: %{token: token}} = :sys.get_state(Breathing)
    send(Breathing, {:complete, token})

    assert %{active: false} = Breathing.status()
    assert [{"light.program", %{program: "breathing"}}] = requests()
    assert %{active_session: nil} = Audio.status()
  end

  test "an alarm takes over the strip from the breathing session" do
    {:ok, alarm} = Settings.create_alarm(%{label: "Test", local_time: "12:00"})
    assert {:ok, %{active: true}} = Breathing.start("0-4-0-6", 5, 2)

    assert {:ok, _pid} = WakeSession.start(alarm)
    assert %{active: false} = Breathing.status()
    assert {"light.program", %{program: "dawn"}} = List.last(requests())

    assert {:error, :wake_session_active} = Breathing.start("0-4-0-6", 5, 2)
  end

  test "keeps the ambience when the ESP32 is unreachable" do
    GuideLightDriver.set_result({:error, {:guide_light_unreachable, :timeout}})

    assert {:ok, %{active: true, light: %{active: false}, audio: %{active: true}}} =
             Breathing.start("0-4-0-6", 5, 2)

    assert played?("breathing_meditation_ambience")

    # The `off` of the stop ends the outage for the next tests.
    GuideLightDriver.set_result(:ok)
    assert {:ok, %{active: false}} = Breathing.stop()
    assert %{state: :available} = GuideLight.status()
  end
end
