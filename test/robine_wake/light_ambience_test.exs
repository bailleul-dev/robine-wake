defmodule RobineWake.LightAmbienceTest do
  use RobineWake.DomainCase

  alias RobineWake.Bluetooth.Command
  alias RobineWake.GuideLight.Driver.Test, as: GuideLightDriver

  @storm "storm_rain_lasonotheque_2719"

  defp requests do
    _ = GuideLight.status()
    GuideLightDriver.requests()
  end

  defp played?(sound) do
    Enum.any?(Audio.status().commands, &match?({:play, _session, ^sound}, &1))
  end

  # Moves the session `ms` into its program, then lets it tick.
  defp advance(ms) do
    :sys.replace_state(LightAmbience, fn %{session: session} = state ->
      %{state | session: %{session | started_ms: session.started_ms - ms}}
    end)

    %{session: %{token: token}} = :sys.get_state(LightAmbience)
    send(LightAmbience, {:tick, token})
    LightAmbience.status()
  end

  defp program(body),
    do: Command.execute(%{"v" => 1, "op" => "light.program", "body" => body})

  test "the volume holds with the light, and falls over the sunset" do
    assert LightAmbience.timeline(%{"program" => "dawn", "duration_ms" => 600_000}) ==
             {600_000, 0}

    assert LightAmbience.timeline(%{"program" => "sunset", "duration_ms" => 600_000}) ==
             {0, 600_000}

    assert LightAmbience.timeline(%{"program" => "reading", "duration_ms" => 600_000}) ==
             {600_000, 1_800_000}
  end

  test "a sunset plays the storm, softer and softer, then stops with the dark" do
    assert {:ok, _status} =
             LightAmbience.start(%{"program" => "sunset", "duration_ms" => 600_000}, %{
               sound_id: @storm,
               volume: 40
             })

    assert [{"light.program", %{program: "sunset", duration_ms: 600_000}}] = requests()
    assert played?(@storm)
    assert %{gain: 40} = Audio.status()

    assert %{active: true, gain_percent: 20} = advance(300_000)
    assert %{gain: 20} = Audio.status()

    assert %{active: false} = advance(300_000)
    assert %{active_session: nil} = Audio.status()
  end

  test "a reading light keeps its volume, then fades with its sunset" do
    body = %{"program" => "reading", "duration_ms" => 600_000, "sunset_ms" => 600_000}
    assert {:ok, _status} = LightAmbience.start(body, %{sound_id: @storm, volume: 40})

    assert %{gain_percent: 40} = advance(590_000)
    assert %{gain_percent: 30} = advance(160_000)
  end

  test "off, a new program or an alarm stop the ambience" do
    ambience = %{sound_id: @storm, volume: 2}
    dawn = %{"program" => "dawn", "duration_ms" => 600_000}

    assert {:ok, _status} = LightAmbience.start(dawn, ambience)
    assert {:ok, _status} = LightAmbience.start(%{"program" => "off"})
    assert %{active: false} = LightAmbience.status()
    assert %{active_session: nil} = Audio.status()

    assert {:ok, _status} = LightAmbience.start(dawn, ambience)
    assert {:ok, _status} = LightAmbience.start(%{"program" => "sunset", "duration_ms" => 1})
    assert %{active: false} = LightAmbience.status()

    {:ok, alarm} = Settings.create_alarm(%{label: "Test", local_time: "12:00"})
    assert {:ok, _status} = LightAmbience.start(dawn, ambience)
    assert {:ok, _pid} = WakeSession.start(alarm)
    assert %{active: false} = LightAmbience.status()
    assert {:error, :wake_session_active} = LightAmbience.start(dawn, ambience)
  end

  test "the command takes an ambience, and ends a breathing session first" do
    assert {:ok, %{active: true}} = Breathing.start("0-4-0-6", 5, 2)

    assert %{"status" => "ok"} =
             program(%{
               "program" => "reading",
               "duration_ms" => 600_000,
               "ambience" => %{"sound_id" => @storm, "volume_percent" => 30}
             })

    assert %{active: false} = Breathing.status()
    # The ESP32 never sees the ambience.
    assert {"light.program", %{program: "reading", duration_ms: 600_000} = body} =
             List.last(requests())

    refute Map.has_key?(body, :ambience)

    assert %{"status" => "ok", "body" => %{"volume_percent" => 10}} =
             Command.execute(%{
               "v" => 1,
               "op" => "light.ambience.volume",
               "body" => %{"volume_percent" => 10}
             })

    assert %{"body" => %{"light_ambience" => %{"active" => true, "sound_id" => @storm}}} =
             Command.execute(%{"v" => 1, "op" => "state.get"})

    assert %{"error" => %{"code" => "sound_not_found"}} =
             program(%{
               "program" => "sunset",
               "duration_ms" => 600_000,
               "ambience" => %{"sound_id" => "nope"}
             })
  end
end
