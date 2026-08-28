defmodule RobineWake.HueTest do
  use RobineWake.DomainCase

  alias RobineWake.Hue.Driver.Test, as: HueDriver

  test "pairs locally and exposes Hue rooms without returning credentials" do
    assert {:error, :hue_link_button_required} = Hue.pair("button-required")

    assert {:ok, %{configured: true, state: :available, target_count: 1}} =
             Hue.pair("192.168.1.42")

    assert [%{"id" => "bedroom-group", "name" => "Chambre"}] = Hue.targets()
    assert %{"application_key" => "test-application-key"} = Settings.hue_bridge()
    refute Map.has_key?(Hue.status(), :application_key)
  end

  test "keeps the last discovered rooms when a refresh temporarily fails" do
    assert {:ok, _status} = Hue.pair("192.168.1.42")
    HueDriver.set_targets_result({:error, :temporary_discovery_failure})

    assert {:error, :temporary_discovery_failure} = Hue.refresh()
    assert [%{"id" => "bedroom-group", "name" => "Chambre"}] = Hue.targets()
  end

  test "recovers a room saved in an alarm when discovery is unavailable" do
    assert {:ok, _status} = Hue.pair("192.168.1.42")

    assert {:ok, _alarm} =
             Settings.create_alarm(%{
               local_time: "07:00",
               days_of_week: [1],
               light_profile: %{
                 enabled: true,
                 target_id: "saved-bedroom-group",
                 target_name: "Chambre enregistrée"
               }
             })

    :ok = Hue.reset()
    HueDriver.set_targets_result({:error, :temporary_discovery_failure})

    assert {:error, :temporary_discovery_failure} = Hue.refresh()

    assert [%{"id" => "saved-bedroom-group", "name" => "Chambre enregistrée"}] = Hue.targets()

    assert {:ok, %{active: true}} = Hue.start_breathing("saved-bedroom-group", 3, 60)
    assert {:ok, %{active: false}} = Hue.stop_breathing()
  end

  test "runs a wake transition, snoozes, and restores the previous light state" do
    assert {:ok, _status} = Hue.pair("192.168.1.42")

    profile = %{
      enabled: true,
      target_id: "bedroom-group",
      start_brightness: 2,
      end_brightness: 65,
      ramp_seconds: 600
    }

    Hue.start_wake("session-1", profile)
    assert eventually(fn -> length(HueDriver.commands()) >= 3 end)

    assert [
             {:get, "bedroom-group"},
             {:set, "bedroom-group",
              %{
                "color" => %{"xy" => %{"x" => 0.65, "y" => 0.34}},
                "dimming" => %{"brightness" => 2}
              } = start},
             {:set, "bedroom-group",
              %{
                "color_temperature" => %{"mirek" => 455},
                "dimming" => %{"brightness" => 7.0},
                "dynamics" => %{"duration" => 108_000}
              }}
           ] = HueDriver.commands()

    assert start["on"] == %{"on" => true}

    Hue.snooze("session-1")

    assert eventually(fn ->
             Enum.any?(HueDriver.commands(), &match?({:set, _, %{"on" => %{"on" => false}}}, &1))
           end)

    Hue.finish_wake("session-1", :restore)

    assert eventually(fn ->
             List.last(HueDriver.commands()) ==
               {:set, "bedroom-group",
                %{
                  "color" => %{"xy" => %{"x" => 0.31, "y" => 0.33}},
                  "dimming" => %{"brightness" => 42.0},
                  "on" => %{"on" => false}
                }}
           end)
  end

  test "reproduces a natural sunrise from deep orange to cool daylight" do
    assert {:ok, _status} = Hue.pair("192.168.1.42")

    profile = %{
      enabled: true,
      target_id: "bedroom-group",
      start_brightness: 2,
      end_brightness: 65,
      ramp_seconds: 100
    }

    Hue.start_wake("sunrise-session", profile)

    %{sessions: %{"sunrise-session" => %{sunrise_token: token}}} = :sys.get_state(Hue)

    Enum.each(1..3, fn expected_stage ->
      send(Hue, {:sunrise_stage, "sunrise-session", token})

      assert eventually(fn ->
               get_in(:sys.get_state(Hue), [:sessions, "sunrise-session", :sunrise_stage_index]) ==
                 expected_stage
             end)
    end)

    sunrise_commands =
      HueDriver.commands()
      |> Enum.filter(fn
        {:set, "bedroom-group", %{"color_temperature" => _}} -> true
        _ -> false
      end)

    assert Enum.map(sunrise_commands, fn {:set, _, changes} ->
             {
               get_in(changes, ["color_temperature", "mirek"]),
               get_in(changes, ["dimming", "brightness"]),
               get_in(changes, ["dynamics", "duration"])
             }
           end) == [
             {455, 7.0, 18_000},
             {370, 19.6, 27_000},
             {250, 41.1, 30_000},
             {182, 65.0, 25_000}
           ]

    Hue.finish_wake("sunrise-session", :restore)
  end

  test "alternates strong wake colors every three seconds" do
    assert {:ok, _status} = Hue.pair("192.168.1.42")

    profile = %{
      enabled: true,
      target_id: "bedroom-group",
      start_brightness: 2,
      end_brightness: 65,
      ramp_seconds: 600
    }

    Hue.start_wake("strong-session", profile)
    Hue.strong_wake("strong-session")

    assert eventually(fn ->
             Enum.any?(HueDriver.commands(), fn
               {:set, "bedroom-group",
                %{
                  "color" => %{"xy" => %{"x" => 0.675, "y" => 0.322}},
                  "dimming" => %{"brightness" => 65},
                  "dynamics" => %{"duration" => 650}
                }} ->
                 true

               _ ->
                 false
             end)
           end)

    %{sessions: %{"strong-session" => %{strong_token: token}}} = :sys.get_state(Hue)
    send(Hue, {:strong_wake_color, "strong-session", token})

    assert eventually(fn ->
             Enum.any?(HueDriver.commands(), fn
               {:set, "bedroom-group", %{"color" => %{"xy" => %{"x" => 0.153, "y" => 0.048}}}} ->
                 true

               _ ->
                 false
             end)
           end)

    send(Hue, {:strong_wake_color, "strong-session", token})

    assert eventually(fn ->
             Enum.any?(HueDriver.commands(), fn
               {:set, "bedroom-group", %{"color" => %{"xy" => %{"x" => 0.313, "y" => 0.329}}}} ->
                 true

               _ ->
                 false
             end)
           end)

    Hue.finish_wake("strong-session", :restore)
  end

  test "runs native 4/6 breathing transitions and restores the light on stop" do
    assert {:ok, _status} = Hue.pair("192.168.1.42")

    assert {:ok,
            %{
              active: true,
              phase: :inhale,
              duration_minutes: 10,
              inhale_seconds: 4,
              exhale_seconds: 6,
              inhale_color: "golden_amber",
              exhale_color: "twilight_rose",
              cycle_count: 0,
              phase_duration_ms: 4_000,
              phase_elapsed_ms: phase_elapsed_ms,
              audio: %{active: true, kind: "meditation_ambience", low_gain: 60, high_gain: 60}
            }} =
             Hue.start_breathing("bedroom-group")

    assert phase_elapsed_ms in 0..100

    assert %{active_session: audio_session, gain: 60} = Audio.status()
    assert is_binary(audio_session)

    assert eventually(fn -> length(HueDriver.commands()) >= 4 end)

    assert [
             {:get, "bedroom-group"},
             {:set, "bedroom-group",
              %{
                "color" => %{"xy" => %{"x" => 0.5, "y" => 0.3}},
                "dimming" => %{"brightness" => 1},
                "dynamics" => %{"duration" => 0},
                "on" => %{"on" => true}
              }},
             {:set, "bedroom-group",
              %{
                "color" => %{"xy" => %{"x" => 0.56, "y" => 0.42}},
                "dynamics" => %{"duration" => 750},
                "on" => %{"on" => true}
              }},
             {:set, "bedroom-group",
              %{
                "dimming" => %{"brightness" => 30},
                "dynamics" => %{"duration" => 4_000},
                "on" => %{"on" => true}
              }}
           ] = HueDriver.commands()

    %{breathing: %{token: token}} = :sys.get_state(Hue)
    send(Hue, {:breathing_light_dispatch, token, :exhale, System.monotonic_time(:millisecond)})
    send(Hue, {:breathing_phase, token})

    assert eventually(fn ->
             Enum.any?(HueDriver.commands(), fn
               {:set, "bedroom-group",
                %{
                  "color" => %{"xy" => %{"x" => 0.5, "y" => 0.3}},
                  "dynamics" => %{"duration" => 750},
                  "on" => %{"on" => true}
                }} ->
                 true

               _ ->
                 false
             end)
           end)

    assert eventually(fn ->
             Enum.any?(HueDriver.commands(), fn
               {:set, "bedroom-group",
                %{
                  "dimming" => %{"brightness" => 1},
                  "dynamics" => %{"duration" => 6_000},
                  "on" => %{"on" => true}
                }} ->
                 true

               _ ->
                 false
             end)
           end)

    assert %{breathing: %{active: true, phase: :exhale}} = Hue.status()

    send(Hue, {:breathing_phase, token})

    assert eventually(fn ->
             match?(%{phase: :inhale, cycle_count: 1}, Hue.status().breathing)
           end)

    assert {:ok, %{active: false}} = Hue.stop_breathing()
    assert %{active_session: nil, gain: 0} = Audio.status()

    assert eventually(fn ->
             List.last(HueDriver.commands()) ==
               {:set, "bedroom-group",
                %{
                  "color" => %{"xy" => %{"x" => 0.31, "y" => 0.33}},
                  "dimming" => %{"brightness" => 42.0},
                  "on" => %{"on" => false}
                }}
           end)
  end

  test "measures Hue latency and refreshes breathing synchronization" do
    HueDriver.set_delay(80)
    assert {:ok, _status} = Hue.pair("192.168.1.42")

    assert {:ok, %{synchronization: synchronization}} =
             Hue.start_breathing("bedroom-group", 3, 60)

    assert synchronization.hue_latency_ms in 35..60
    assert synchronization.hue_round_trip_ms in 70..120
    assert synchronization.samples == 1

    assert eventually(fn ->
             sync = Hue.status().breathing.synchronization

             sync.samples >= 2 and sync.hue_round_trip_ms in 70..140 and
               sync.hue_latency_ms in 35..70 and abs(sync.estimated_error_ms) <= 30
           end)

    assert {:ok, %{active: false}} = Hue.stop_breathing()
  end

  test "stops and restores automatically after the selected duration" do
    assert {:ok, _status} = Hue.pair("192.168.1.42")

    assert {:ok,
            %{
              active: true,
              duration_minutes: 3,
              remaining_seconds: remaining,
              ends_at: ends_at
            }} = Hue.start_breathing("bedroom-group", 3)

    assert remaining in 179..180
    assert is_binary(ends_at)
    assert {:error, :invalid_breathing_duration} = Hue.start_breathing("bedroom-group", 2)
    assert {:error, :invalid_breathing_duration} = Hue.start_breathing("bedroom-group", 4)

    %{breathing: %{token: token}} = :sys.get_state(Hue)
    send(Hue, {:breathing_complete, token})

    assert eventually(fn -> Hue.status().breathing.active == false end)
    assert %{active_session: nil, gain: 0} = Audio.status()

    assert eventually(fn ->
             List.last(HueDriver.commands()) ==
               {:set, "bedroom-group",
                %{
                  "color" => %{"xy" => %{"x" => 0.31, "y" => 0.33}},
                  "dimming" => %{"brightness" => 42.0},
                  "on" => %{"on" => false}
                }}
           end)
  end

  test "changes the meditation volume without losing the breathing envelope" do
    assert {:ok, _status} = Hue.pair("192.168.1.42")

    assert {:ok, %{audio: %{volume_percent: 60, low_gain: 60, high_gain: 60}}} =
             Hue.start_breathing("bedroom-group", 3, 60)

    assert {:ok, %{audio: %{volume_percent: 80, low_gain: 80, high_gain: 80}}} =
             Hue.set_breathing_volume(80)

    assert Audio.status().gain == 80
    assert {:error, :invalid_breathing_volume} = Hue.set_breathing_volume(101)

    assert {:ok, %{active: false}} = Hue.stop_breathing()
    assert {:error, :breathing_not_active} = Hue.set_breathing_volume(40)
  end

  test "rejects breathing while a wake-light session owns Hue" do
    assert {:ok, _status} = Hue.pair("192.168.1.42")

    Hue.start_wake("session-1", %{
      enabled: true,
      target_id: "bedroom-group",
      start_brightness: 2,
      end_brightness: 65,
      ramp_seconds: 600
    })

    assert eventually(fn -> :sys.get_state(Hue).sessions != %{} end)
    assert {:error, :wake_session_active} = Hue.start_breathing("bedroom-group")
  end

  test "a wake without Hue still stops breathing audio before alarm playback" do
    assert {:ok, _status} = Hue.pair("192.168.1.42")
    assert {:ok, %{audio: %{active: true}}} = Hue.start_breathing("bedroom-group")

    assert :ok = Hue.start_wake("session-1", %{enabled: false})
    assert %{breathing: %{active: false}} = Hue.status()
    assert %{active_session: nil} = Audio.status()
  end

  defp eventually(fun, attempts \\ 50)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(2)
      eventually(fun, attempts - 1)
    end
  end
end
