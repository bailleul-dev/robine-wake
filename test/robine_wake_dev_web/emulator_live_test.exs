defmodule RobineWakeDevWeb.EmulatorLiveTest do
  use RobineWake.DomainCase

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias RobineWake.Audio.Driver.Host, as: HostAudio
  alias RobineWakeDev.Emulator

  @endpoint RobineWakeDevWeb.Endpoint

  setup do
    start_supervised!({Phoenix.PubSub, name: RobineWakeDev.PubSub})
    start_supervised!(@endpoint)

    on_exit(fn ->
      Application.put_env(:robine_wake, :host_audio_state, :available)
      Application.put_env(:robine_wake, :host_camera_state, :available)
      Application.put_env(:robine_wake, :host_network_state, :available)
    end)

    :ok
  end

  test "renders the hardware lab and drives synthetic camera frames" do
    {:ok, view, html} = live(Phoenix.ConnTest.build_conn(), "/")

    assert html =~ "Robine Wake Hardware Lab"
    assert has_element?(view, "#system-health")
    assert has_element?(view, "#camera-occupied")

    view |> element("#camera-calibrate") |> render_click()
    view |> element("#camera-occupied") |> render_click()

    assert RobineWake.Camera.status().last_observation.state == :occupied
    assert render(view) =~ "Scene: occupied"

    view |> element("#camera-offline") |> render_click()
    assert RobineWake.Camera.status().driver_health.state == :degraded
    assert render(view) =~ "Scene: unavailable"
  end

  test "emulates capability failures and controls a real wake session" do
    {:ok, view, _html} = live(Phoenix.ConnTest.build_conn(), "/")

    view |> element("#network-offline") |> render_click()
    assert RobineWake.Network.status().state == :degraded
    assert has_element?(view, "#network-health", "degraded")

    view |> element("#audio-offline") |> render_click()
    assert HostAudio.status().state == :degraded
    assert has_element?(view, "#audio-health", "degraded")

    view |> element("#audio-online") |> render_click()
    view |> element("#create-demo-alarm") |> render_click()
    [alarm] = RobineWake.Settings.list_alarms()
    view |> element("#trigger-#{alarm.id}") |> render_click()

    assert RobineWake.WakeSession.active().alarm_id == alarm.id
    assert has_element?(view, "#active-session")

    view |> element("#session-snooze") |> render_click()
    assert RobineWake.WakeSession.active().state == :snoozed

    view |> element("#session-dismiss") |> render_click()
    assert RobineWake.WakeSession.active() == nil
  end

  test "advances deterministic domain time from the LiveView" do
    {:ok, view, _html} = live(Phoenix.ConnTest.build_conn(), "/")
    before = RobineWake.Clock.utc_now()

    view
    |> form("#advance-time", %{minutes: "5"})
    |> render_submit()

    assert DateTime.diff(RobineWake.Clock.utc_now(), before, :second) == 300
    assert has_element?(view, "#action-message", "Simulation updated.")
  end

  test "the emulator snapshot exposes the same aggregated health model" do
    snapshot = Emulator.snapshot()
    assert snapshot.health.target == "host"
    assert snapshot.hardware.clock == :manual
    assert is_list(snapshot.alarms)
  end

  test "renders a bounded error response for an unknown development route" do
    response = get(Phoenix.ConnTest.build_conn(), "/missing")
    assert response.status == 404
    assert response.resp_body == "Not Found"
  end
end
