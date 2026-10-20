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
    guide_light = Application.get_env(:robine_wake, :guide_light)
    Application.put_env(:robine_wake, :guide_light, driver: RobineWake.GuideLight.Driver.Emulated)
    swap_audio(RobineWake.Audio.Driver.Emulated)

    on_exit(fn ->
      Application.put_env(:robine_wake, :guide_light, guide_light)
      swap_audio(RobineWake.Audio.Driver.Host)
    end)

    :ok = Hardware.subscribe()
    :ok
  end

  # Audio picks its driver when it starts; the guide light at each request.
  defp swap_audio(audio) do
    Application.put_env(:robine_wake, :audio_driver, audio)
    :ok = Supervisor.terminate_child(RobineWake.Supervisor, RobineWake.Audio)
    {:ok, _pid} = Supervisor.restart_child(RobineWake.Supervisor, RobineWake.Audio)
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

  test "the emulated strip shows its programs on the halo" do
    assert {:ok, %{"program" => "dawn"}} =
             RobineWake.GuideLight.program(%{"program" => "dawn", "duration_ms" => 60_000})

    assert_receive {:hardware, %{type: "light", id: "halo", state: %{on: true, brightness: 2.0}}}

    assert_receive {:hardware,
                    %{
                      type: "light",
                      id: "halo",
                      state: %{brightness: 60.0, mirek: 182, transition_ms: 60_000}
                    }}

    refute Hardware.snapshot().lights["lamp_left"].on

    assert {:error, {:guide_light_rejected, "invalid_program"}} =
             RobineWake.GuideLight.program(%{"program" => "disco"})
  end

  test "a breathing session breathes on the halo and plays the meditation sound" do
    assert {:ok, _breathing} = Breathing.start("0-4-0-6", 3, 40)

    assert_receive {:hardware, %{type: "light", id: "halo", state: %{on: true}}}, 2_000

    assert_receive {:hardware,
                    %{
                      type: "audio",
                      state: %{playing: true, sound_id: "breathing_meditation_ambience", url: url}
                    }},
                   2_000

    assert url =~ "/emulator/audio/"

    refute_received {:hardware, %{type: "light", id: "lamp_left"}}
    assert {:ok, _status} = Breathing.set_volume(0)
    assert {:ok, _status} = Breathing.stop()
  end

  test "a wake session raises the dawn on the halo and rings through the browser" do
    ringing_alarm(%{enabled: true})

    assert_receive {:hardware, %{type: "light", id: "halo", state: %{on: true}}}, 2_000

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

    assert [%{label: "Demo · Réveil", light_profile: %{enabled: true}}] =
             Settings.list_alarms()

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
