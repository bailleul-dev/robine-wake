defmodule RobineWakeWeb.RouterTest do
  use RobineWake.DomainCase
  import Plug.Conn
  import Plug.Test

  alias RobineWake.Bluetooth.Command, as: BluetoothCommand

  @opts RobineWakeWeb.Router.init([])

  test "health endpoint is available without authentication" do
    conn = conn(:get, "/health") |> RobineWakeWeb.Router.call(@opts)
    assert conn.status == 200

    assert %{"state" => "degraded", "camera" => %{"analysis_health" => analysis}} =
             Jason.decode!(conn.resp_body)

    assert analysis["reason"] == "calibration_required"
  end

  test "web API is directly available on the local network" do
    conn = conn(:get, "/api/state") |> RobineWakeWeb.Router.call(@opts)
    assert conn.status == 200

    assert %{"smartphone_dismiss" => %{"enabled" => true, "locked" => false}} =
             Jason.decode!(conn.resp_body)
  end

  test "smartphone dismissal setting is persistent and locked during an alarm" do
    disabled =
      conn(
        :patch,
        "/api/settings/smartphone-dismiss",
        Jason.encode!(%{enabled: false})
      )
      |> put_req_header("content-type", "application/json")
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert disabled.status == 200
    refute Settings.smartphone_dismiss_enabled()

    {:ok, alarm} =
      Settings.create_alarm(%{
        local_time: "08:00",
        days_of_week: [1],
        strong_sound_id: "wake_up_call"
      })

    assert {:ok, _pid} = WakeSession.start(alarm)

    locked =
      conn(
        :patch,
        "/api/settings/smartphone-dismiss",
        Jason.encode!(%{enabled: true})
      )
      |> put_req_header("content-type", "application/json")
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert locked.status == 409

    assert %{"error" => %{"code" => "smartphone_dismiss_setting_locked"}} =
             Jason.decode!(locked.resp_body)

    refused =
      conn(:post, "/api/session/dismiss", "{}")
      |> put_req_header("content-type", "application/json")
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert refused.status == 403
    assert WakeSession.active()
    assert {:ok, _session} = WakeSession.dismiss(:manual)
  end

  @tag remote_dismiss_enabled: false
  test "a test exposes direct dismissal through HTTP and Bluetooth" do
    {:ok, alarm} = Settings.create_alarm(%{local_time: "23:00", days_of_week: [1]})

    for path <- ["trigger", "trigger-strong"] do
      started =
        conn(:post, "/api/alarms/#{alarm.id}/#{path}", "{}")
        |> put_req_header("content-type", "application/json")
        |> csrf()
        |> RobineWakeWeb.Router.call(@opts)

      assert started.status == 202
      state = conn(:get, "/api/state") |> RobineWakeWeb.Router.call(@opts)

      assert %{"active_session" => %{"test_mode" => true, "smartphone_dismiss_allowed" => true}} =
               Jason.decode!(state.resp_body)

      assert %{"body" => %{"active_session" => %{"test_mode" => true}}} =
               BluetoothCommand.execute(%{"v" => 1, "op" => "state.get", "body" => %{}})

      stopped =
        conn(:post, "/api/session/dismiss", "{}")
        |> put_req_header("content-type", "application/json")
        |> csrf()
        |> RobineWakeWeb.Router.call(@opts)

      assert stopped.status == 200
      assert WakeSession.active() == nil
    end
  end

  @tag remote_dismiss_enabled: false
  test "button-only mode locks remote settings and rejects web and iPhone dismissal" do
    state = conn(:get, "/api/state") |> RobineWakeWeb.Router.call(@opts)

    assert %{"smartphone_dismiss" => %{"enabled" => false, "locked" => true}} =
             Jason.decode!(state.resp_body)

    assert {:error, :smartphone_dismiss_setting_locked} =
             Settings.set_smartphone_dismiss_enabled(true)

    assert %{"status" => "error"} =
             BluetoothCommand.execute(%{
               "v" => 1,
               "op" => "settings.smartphone_dismiss.set",
               "body" => %{"enabled" => true}
             })

    {:ok, alarm} = Settings.create_alarm(%{local_time: "08:00", days_of_week: [1]})
    assert {:ok, _pid} = WakeSession.start(alarm)
    assert %{smartphone_dismiss_allowed: false} = WakeSession.active()

    refused =
      conn(:post, "/api/session/dismiss", "{}")
      |> put_req_header("content-type", "application/json")
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert refused.status == 403

    assert %{"status" => "error", "error" => %{"code" => "smartphone_dismiss_disabled"}} =
             BluetoothCommand.execute(%{"v" => 1, "op" => "session.dismiss"})

    assert {:error, :smartphone_dismiss_disabled} = WakeSession.dismiss(:mcp)
    assert WakeSession.active()
    assert {:ok, %{terminal_reason: :remote_button}} = WakeSession.dismiss(:remote_button)
  end

  test "Expo web client and its versioned assets are served at the root" do
    page = conn(:get, "/") |> RobineWakeWeb.Router.call(@opts)

    assert page.status == 200
    assert get_resp_header(page, "content-type") == ["text/html; charset=utf-8"]
    assert page.resp_body =~ ~s(<div id="root"></div>)

    [_, asset_path] = Regex.run(~r{<script src="(/[^"]+\.js)"}, page.resp_body)
    asset = conn(:get, asset_path) |> RobineWakeWeb.Router.call(@opts)

    assert asset.status == 200
    assert get_resp_header(asset, "content-type") == ["text/javascript"]
    assert byte_size(asset.resp_body) > 100_000
  end

  test "Expo web routes support direct links and browser reloads" do
    for path <- ["/matin", "/soir", "/alarmes", "/reveil"] do
      page = conn(:get, path) |> RobineWakeWeb.Router.call(@opts)

      assert page.status == 200
      assert get_resp_header(page, "content-type") == ["text/html; charset=utf-8"]
      assert page.resp_body =~ ~s(<div id="root"></div>)
    end
  end

  test "old beta URL redirects to the default Expo interface" do
    response = conn(:get, "/beta") |> RobineWakeWeb.Router.call(@opts)

    assert response.status == 302
    assert get_resp_header(response, "location") == ["/"]
  end

  test "versioned command API reuses the Bluetooth contract without auth or CSRF" do
    payload = %{"v" => 1, "id" => "http", "op" => "capabilities.get", "body" => %{}}

    conn =
      conn(:post, "/api/v1/command", Jason.encode!(payload))
      |> put_req_header("content-type", "application/json")
      |> RobineWakeWeb.Router.call(@opts)

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == BluetoothCommand.execute(payload)
  end

  test "alarm editor exposes the complete two-stage wake journey" do
    conn = conn(:get, "/legacy") |> auth() |> RobineWakeWeb.Router.call(@opts)

    assert conn.status == 200
    assert conn.resp_body =~ ~s(id="alarm-dialog")
    assert conn.resp_body =~ ~s(name="sound_id")
    assert conn.resp_body =~ ~s(name="strong_sound_id")
    assert conn.resp_body =~ "Your two-stage wake-up"
    assert conn.resp_body =~ "Shape the gentle ramp"
  end

  test "health status opens an actionable in-app diagnostic" do
    conn = conn(:get, "/legacy") |> auth() |> RobineWakeWeb.Router.call(@opts)

    assert conn.status == 200
    assert conn.resp_body =~ ~s(id="health")
    assert conn.resp_body =~ ~s|onclick="showDiagnostics()"|
    assert conn.resp_body =~ ~s(id="diagnostics-panel")
    assert conn.resp_body =~ "function renderDiagnostics(data)"
  end

  test "disabled camera is absent from the product surface and alarm behavior" do
    original = Application.fetch_env!(:robine_wake, :camera_enabled)
    Application.put_env(:robine_wake, :camera_enabled, false)
    on_exit(fn -> Application.put_env(:robine_wake, :camera_enabled, original) end)

    page = conn(:get, "/legacy") |> auth() |> RobineWakeWeb.Router.call(@opts)
    refute page.resp_body =~ "camera-form"
    refute page.resp_body =~ "Détection du lit"
    refute page.resp_body =~ "Calibrer la caméra"
    refute page.resp_body =~ ~s(value="bed_exit")

    calibration =
      conn(:post, "/api/camera/calibrate", "{}")
      |> put_req_header("content-type", "application/json")
      |> auth()
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert calibration.status == 404

    capabilities =
      BluetoothCommand.execute(%{"v" => 1, "op" => "capabilities.get", "body" => %{}})

    refute "camera.calibrate" in capabilities["body"]["operations"]

    assert {:ok, alarm} = Alarm.new(%{dismiss_policy: "bed_exit"})
    assert alarm.dismiss_policy == :manual

    health = RobineWake.Health.snapshot()
    assert health.camera == %{enabled: false, state: :disabled}
  end

  test "legacy basic-auth headers do not trigger a login challenge" do
    response =
      conn(:get, "/api/state")
      |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth("admin", "wrong"))
      |> RobineWakeWeb.Router.call(@opts)

    assert response.status == 200
    assert get_resp_header(response, "www-authenticate") == []
  end

  test "creates and lists an alarm through the authenticated API" do
    payload =
      Jason.encode!(%{
        label: "API",
        local_time: "08:00",
        days_of_week: [1, 2, 3, 4, 5],
        sound_id: "jungle_sunrise",
        strong_sound_id: "wake_up_call"
      })

    created =
      conn(:post, "/api/alarms", payload)
      |> put_req_header("content-type", "application/json")
      |> auth()
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert created.status == 201

    assert %{
             "data" => %{
               "label" => "API",
               "id" => id,
               "sound_id" => "jungle_sunrise",
               "strong_sound_id" => "wake_up_call"
             }
           } = Jason.decode!(created.resp_body)

    listed = conn(:get, "/api/alarms") |> auth() |> RobineWakeWeb.Router.call(@opts)
    assert listed.status == 200
    assert %{"data" => [%{"id" => ^id}]} = Jason.decode!(listed.resp_body)
  end

  test "previews five alarm occurrences without persisting the alarm" do
    payload = Jason.encode!(%{local_time: "08:00", days_of_week: [1, 2, 3, 4, 5]})

    response =
      conn(:post, "/api/alarms/preview", payload)
      |> put_req_header("content-type", "application/json")
      |> auth()
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert response.status == 200

    assert %{
             "data" => %{
               "next_occurrences" => occurrences,
               "prewake_seconds" => 1_200
             }
           } = Jason.decode!(response.resp_body)

    assert length(occurrences) == 5
    assert Settings.list_alarms() == []
  end

  test "triggers an alarm directly in its strong phase" do
    {:ok, alarm} =
      Settings.create_alarm(%{
        local_time: "08:00",
        days_of_week: [1],
        strong_sound_id: "wake_up_call",
        volume_profile: %{start: 10, ceiling: 35, ramp_seconds: 300}
      })

    response =
      conn(:post, "/api/alarms/#{alarm.id}/trigger-strong", "{}")
      |> put_req_header("content-type", "application/json")
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert response.status == 202
    assert %{"phase" => "strong"} = Jason.decode!(response.resp_body)
    assert %{audio_phase: :strong, current_gain: 35} = WakeSession.active()
  end

  test "lists sounds and imports a digest-verified WAV through the authenticated API" do
    default_path = Application.fetch_env!(:robine_wake, :default_sound_path)
    contents = File.read!(default_path)
    digest = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
    sound_id = "api_sound_#{System.unique_integer([:positive])}"

    response =
      conn(
        :post,
        "/api/sounds",
        Jason.encode!(%{id: sound_id, sha256: digest, data_base64: Base.encode64(contents)})
      )
      |> put_req_header("content-type", "application/json")
      |> auth()
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert response.status == 201

    assert %{"data" => %{"id" => ^sound_id, "sha256" => ^digest}} =
             Jason.decode!(response.resp_body)

    listed = conn(:get, "/api/sounds") |> auth() |> RobineWakeWeb.Router.call(@opts)
    assert listed.status == 200
    sounds = Jason.decode!(listed.resp_body)["data"]
    assert Enum.any?(sounds, &(&1["id"] == sound_id))
    assert Enum.any?(sounds, &(&1["id"] == "jungle_sunrise" and &1["format"] == "mp3"))
    assert Enum.any?(sounds, &(&1["id"] == "wake_up_call" and &1["intensity"] == "strong"))
  end

  test "rejects a sound upload with an invalid digest as a validation error" do
    response =
      conn(
        :post,
        "/api/sounds",
        Jason.encode!(%{
          id: "bad_upload",
          sha256: "short",
          data_base64: Base.encode64(String.duplicate("x", 64))
        })
      )
      |> put_req_header("content-type", "application/json")
      |> auth()
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert response.status == 422
    assert %{"error" => %{"code" => "invalid_sound"}} = Jason.decode!(response.resp_body)
  end

  test "camera calibration reports an unavailable host capture capability" do
    response =
      conn(:post, "/api/camera/calibrate", "{}")
      |> put_req_header("content-type", "application/json")
      |> auth()
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert response.status == 503
    assert %{"error" => %{"code" => "capability_unavailable"}} = Jason.decode!(response.resp_body)
  end

  test "camera calibration rejects a region outside the sensor profile" do
    payload = Jason.encode!(%{roi: %{x: 300, y: 200, width: 100, height: 100}})

    response =
      conn(:post, "/api/camera/calibrate", payload)
      |> put_req_header("content-type", "application/json")
      |> auth()
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert response.status == 422
    assert %{"error" => %{"code" => "validation_failed"}} = Jason.decode!(response.resp_body)
  end

  test "mutating API routes reject missing CSRF tokens" do
    response =
      conn(:post, "/api/alarms", "{}")
      |> put_req_header("content-type", "application/json")
      |> auth()
      |> RobineWakeWeb.Router.call(@opts)

    assert response.status == 403
    assert %{"error" => %{"code" => "csrf_failed"}} = Jason.decode!(response.resp_body)
  end

  test "diagnostics have a digest manifest and exclude secrets and pixels" do
    response = conn(:get, "/api/diagnostics") |> auth() |> RobineWakeWeb.Router.call(@opts)

    assert response.status == 200
    assert ["attachment" <> _] = get_resp_header(response, "content-disposition")

    body = Jason.decode!(response.resp_body)
    assert body["format"] == "robine-wake-diagnostics"
    assert length(body["manifest"]) == 5
    refute response.resp_body =~ "admin_password"
    refute response.resp_body =~ "ROBINE_ADMIN_PASSWORD"
    refute response.resp_body =~ "pixels"
  end

  test "factory reset requires explicit confirmation and erases application credentials" do
    on_exit(fn ->
      Application.put_env(:robine_wake, :admin_password, "robine")
      :ok = Supervisor.terminate_child(RobineWake.Supervisor, RobineWake.Auth)
      {:ok, _pid} = Supervisor.restart_child(RobineWake.Supervisor, RobineWake.Auth)
    end)

    {:ok, _alarm} = Settings.create_alarm(%{local_time: "07:00", days_of_week: [1]})

    rejected =
      conn(:post, "/api/factory-reset", Jason.encode!(%{confirmation: "wrong"}))
      |> put_req_header("content-type", "application/json")
      |> auth()
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert rejected.status == 422
    assert RobineWake.Auth.provisioned?()

    accepted =
      conn(:post, "/api/factory-reset", Jason.encode!(%{confirmation: "RESET"}))
      |> put_req_header("content-type", "application/json")
      |> auth()
      |> csrf()
      |> RobineWakeWeb.Router.call(@opts)

    assert accepted.status == 200
    refute RobineWake.Auth.provisioned?()
    assert Settings.list_alarms() == []
    assert Settings.recent_sessions() == []

    setup_redirect = conn(:get, "/setup") |> RobineWakeWeb.Router.call(@opts)
    assert setup_redirect.status == 302
    assert get_resp_header(setup_redirect, "location") == ["/"]
  end

  defp auth(conn) do
    put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth("admin", "robine"))
  end

  defp csrf(conn), do: put_req_header(conn, "x-csrf-token", RobineWakeWeb.CSRF.token())
end
