defmodule RobineWakeDev.DemoTest do
  @moduledoc "The real domain driving the emulated hardware of demo mode."
  use RobineWake.DomainCase

  import Plug.Conn
  import Plug.Test

  alias RobineWakeDev.Clock.Scaled
  alias RobineWakeDev.{Demo, Hardware, VirtualRemote}

  setup do
    start_supervised!({Phoenix.PubSub, name: RobineWakeDev.PubSub})
    start_supervised!(Hardware)
    swap_drivers(RobineWake.Hue.Driver.Emulated, RobineWake.Audio.Driver.Emulated)

    on_exit(fn -> swap_drivers(RobineWake.Hue.Driver.Test, RobineWake.Audio.Driver.Host) end)

    :ok = Hardware.subscribe()
    :ok
  end

  # Hue and Audio pick their driver when they start.
  defp swap_drivers(hue, audio) do
    Application.put_env(:robine_wake, :hue_driver, hue)
    Application.put_env(:robine_wake, :audio_driver, audio)

    for child <- [RobineWake.Hue, RobineWake.Audio] do
      :ok = Supervisor.terminate_child(RobineWake.Supervisor, child)
      {:ok, _pid} = Supervisor.restart_child(RobineWake.Supervisor, child)
    end
  end

  defp ringing_alarm(light_profile \\ %{}) do
    {:ok, alarm} =
      Settings.create_alarm(%{
        label: "Demo test",
        local_time: "07:00:00",
        days_of_week: Enum.to_list(1..7),
        sound_id: "default",
        light_profile: light_profile
      })

    {:ok, _pid} = Scheduler.trigger_now(alarm.id)
    alarm
  end

  test "the emulated bridge exposes the bar's lights and stores what the domain sets" do
    assert {:ok, _status} = Hue.pair("emulated-bridge")
    assert Enum.map(Hue.targets(), & &1["id"]) |> Enum.sort() == ["bedroom", "halo", "lamps"]

    :ok =
      RobineWake.Hue.Driver.Emulated.set_target(%{}, "lamps", %{
        "on" => %{"on" => true},
        "dimming" => %{"brightness" => 25},
        "color_temperature" => %{"mirek" => 250},
        "dynamics" => %{"duration" => 60_000}
      })

    for id <- ["lamp_left", "lamp_right"] do
      assert_receive {:hardware,
                      %{
                        type: "light",
                        id: ^id,
                        state: %{on: true, brightness: 25.0, mirek: 250, transition_ms: 60_000}
                      }}
    end

    assert {:ok, %{"on" => %{"on" => true}, "color_temperature" => %{"mirek" => 250}}} =
             RobineWake.Hue.Driver.Emulated.get_target(%{}, "lamps")

    refute Hardware.snapshot().lights["halo"].on

    assert {:error, :hue_target_not_found} =
             RobineWake.Hue.Driver.Emulated.get_target(%{}, "kitchen")
  end

  test "a breathing session breathes on the halo and plays the meditation sound" do
    {:ok, _status} = Hue.pair("emulated-bridge")
    assert {:ok, _breathing} = Hue.start_breathing("halo", 3, 40)

    assert_receive {:hardware, %{type: "light", id: "halo", state: %{on: true}}}, 2_000

    assert_receive {:hardware,
                    %{
                      type: "audio",
                      state: %{playing: true, sound_id: "breathing_meditation_ambience", url: url}
                    }},
                   2_000

    assert url =~ "/emulator/audio/"

    refute_received {:hardware, %{type: "light", id: "lamp_left"}}
    assert {:ok, _status} = Hue.stop_breathing()
  end

  test "a wake session raises the dawn on the lamps and rings through the browser" do
    {:ok, _status} = Hue.pair("emulated-bridge")
    ringing_alarm(%{enabled: true, target_id: "lamps", target_name: "Lampes", end_brightness: 25})

    assert_receive {:hardware, %{type: "light", id: "lamp_left", state: %{on: true}}}, 2_000

    assert_receive {:hardware,
                    %{
                      type: "audio",
                      state: %{playing: true, url: "/emulator/audio/sounds/default", loop: true}
                    }},
                   2_000

    assert_receive {:hardware, %{type: "audio", state: %{gain: gain, db: db}}} when gain > 0,
                   2_000

    assert db < -6
  end

  test "the virtual remote signs dismissals like the firmware, with one counter" do
    start_supervised!(VirtualRemote)
    ringing_alarm()
    assert WakeSession.active()

    assert VirtualRemote.press() == :dismissed
    refute WakeSession.active()
    assert [%{"id" => "demo-remote", "last_counter" => 1}] = Settings.remote_buttons()

    # Same answer as the real server gives the ESP32 when nothing rings.
    assert VirtualRemote.press() == :dismissed
    assert [%{"last_counter" => 2}] = Settings.remote_buttons()
  end

  test "reset seeds the evening, and the jump lands five minutes before the dawn" do
    start_supervised!({Scaled, utc: ~U[2026-10-01 12:00:00Z]})
    Application.put_env(:robine_wake, :clock, Scaled)
    start_supervised!(VirtualRemote)
    start_supervised!({Demo, reset_hours: 0})

    :ok = Demo.reset()

    assert [%{label: "Demo · Réveil", light_profile: %{target_id: "lamps"}}] =
             Settings.list_alarms()

    assert Hue.status().configured
    assert [%{"id" => "demo-remote"}] = Settings.remote_buttons()
    assert %{hour: 22, minute: 30} = Scaled.utc_now() |> DateTime.shift_zone!("Europe/Paris")

    :ok = Demo.jump_before_alarm()
    assert %{hour: 6, minute: 35} = Scaled.utc_now() |> DateTime.shift_zone!("Europe/Paris")
  end

  describe "demo router" do
    setup do
      Application.put_env(:robine_wake, :demo_secret, "test-secret")
      Application.put_env(:robine_wake, :demo_access_code, "open-sesame")
      on_exit(fn -> Application.delete_env(:robine_wake, :demo_access_code) end)
    end

    defp call(conn), do: RobineWakeDemoWeb.Router.call(conn, RobineWakeDemoWeb.Router.init([]))

    test "keeps everything behind the access code" do
      assert call(conn(:get, "/emulator/state")).status == 401
      assert call(conn(:post, "/api/v1/command", ~s({"v":1,"op":"session.get"}))).status == 401

      page = conn(:get, "/demo") |> put_req_header("accept", "text/html") |> call()
      assert {302, "/access"} == {page.status, get_resp_header(page, "location") |> hd()}

      assert call(conn(:post, "/access", "code=wrong")).status == 401

      granted = call(conn(:post, "/access", "code=open-sesame"))
      assert granted.status == 302
      cookie = granted.resp_cookies["robine_demo_access"].value

      state =
        conn(:get, "/emulator/state") |> put_req_cookie("robine_demo_access", cookie) |> call()

      assert state.status == 200
      assert %{"lights" => %{"halo" => _}, "audio" => _} = Jason.decode!(state.resp_body)
    end

    test "serves the app, the room and the side-by-side page, and keeps MCP off" do
      Application.delete_env(:robine_wake, :demo_access_code)

      top = conn(:get, "/") |> put_req_header("sec-fetch-dest", "document") |> call()
      assert get_resp_header(top, "location") == ["/demo"]
      assert call(conn(:get, "/?app")).status == 200
      assert call(conn(:get, "/demo")).resp_body =~ "/room/index.html?live=1"
      assert call(conn(:get, "/room/live.js")).status == 200
      assert call(conn(:post, "/mcp", "{}")).status == 404

      command =
        conn(:post, "/api/v1/command", ~s({"v":1,"op":"session.get"}))
        |> put_req_header("content-type", "application/json")
        |> call()

      assert %{"status" => "ok"} = Jason.decode!(command.resp_body)
    end
  end
end
