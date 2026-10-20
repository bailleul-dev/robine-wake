defmodule RobineWake.GuideLightTest do
  use RobineWake.DomainCase

  alias RobineWake.{EventLog, GuideLight}
  alias RobineWake.GuideLight.Driver.Test, as: GuideLightDriver

  test "a queued program is sent in order, and nothing without a configured ESP32" do
    :ok = GuideLight.start_program(%{"program" => "dawn", "duration_ms" => 60_000})
    :ok = GuideLight.start_program(%{"program" => "off"})
    _ = GuideLight.status()

    assert [
             {"light.program", %{program: "dawn", duration_ms: 60_000}},
             {"light.program", %{program: "off"}}
           ] = GuideLightDriver.requests()

    config = Application.get_env(:robine_wake, :guide_light)
    Application.delete_env(:robine_wake, :guide_light)
    on_exit(fn -> Application.put_env(:robine_wake, :guide_light, config) end)
    :ok = GuideLightDriver.reset()

    :ok = GuideLight.start_program(%{"program" => "off"})
    assert %{state: :not_configured} = GuideLight.status()
    assert GuideLightDriver.requests() == []
  end

  test "an unreachable ESP32 is logged once per outage" do
    :ok = GuideLight.start_program(%{"program" => "off"})
    assert %{state: :available} = GuideLight.status()

    GuideLightDriver.set_result({:error, {:guide_light_unreachable, :timeout}})
    :ok = GuideLight.start_program(%{"program" => "off"})
    :ok = GuideLight.start_program(%{"program" => "off"})

    assert %{state: :unavailable} = GuideLight.status()
    assert [_] = Enum.filter(EventLog.recent(), &(&1.code == "guide_light_failed"))

    GuideLightDriver.set_result(:ok)
    :ok = GuideLight.start_program(%{"program" => "off"})
    assert %{state: :available} = GuideLight.status()
  end

  test "a restart numbers requests afresh, which the ESP32 must not take for repeats" do
    :ok = GuideLight.start_program(%{"program" => "off"})
    _ = GuideLight.status()
    # The driver's table may belong to the process restarted here.
    before = List.last(GuideLightDriver.ids())
    :ok = Supervisor.terminate_child(RobineWake.Supervisor, GuideLight)
    {:ok, _pid} = Supervisor.restart_child(RobineWake.Supervisor, GuideLight)
    :ok = GuideLight.start_program(%{"program" => "off"})
    _ = GuideLight.status()

    now = List.last(GuideLightDriver.ids())
    assert now =~ ~r/^guide-light-[0-9a-f]{8}-1$/
    refute now == before
  end

  describe "light programs for the web UI" do
    alias RobineWake.Bluetooth.Command

    defp program(body),
      do: Command.execute(%{"v" => 1, "op" => "light.program", "body" => body})

    test "are forwarded to the ESP32 and answered with its light status" do
      GuideLightDriver.set_result(
        {:response, %{v: 1, status: "ok", body: %{program: "dawn", brightness: 0}}}
      )

      assert %{"status" => "ok", "body" => %{"program" => "dawn"}} =
               program(%{"program" => "dawn", "duration_ms" => 1_800_000})

      assert [{"light.program", %{program: "dawn", duration_ms: 1_800_000}}] =
               GuideLightDriver.requests()
    end

    test "read the strip pixel by pixel" do
      GuideLightDriver.set_result(
        {:response,
         %{v: 1, status: "ok", body: %{program: "breathing", pixels: "0a0000", elapsed_ms: 4_000}}}
      )

      assert %{"status" => "ok", "body" => %{"program" => "breathing", "pixels" => "0a0000"}} =
               Command.execute(%{"v" => 1, "op" => "light.get", "body" => %{}})

      assert [{"light.get", %{}}] = GuideLightDriver.requests()
    end

    test "pass the ESP32's validation error through" do
      GuideLightDriver.set_result(
        {:response, %{v: 1, status: "error", error: %{code: "invalid_cadence"}}}
      )

      assert %{"status" => "error", "error" => %{"code" => "invalid_cadence"}} =
               program(%{"program" => "breathing", "cadence" => "4-6"})
    end

    test "report an unreachable ESP32 and close the link they opened" do
      GuideLightDriver.set_result({:error, {:guide_light_unreachable, :timeout}})

      for _attempt <- 1..3 do
        assert %{"status" => "error", "error" => %{"code" => "light_unavailable"}} =
                 program(%{"program" => "off"})
      end

      # A serial port left open would lock the next attempt out (EAGAIN).
      # The first attempt may close a link opened by an earlier test.
      %{opened: opened, closed: closed} = GuideLightDriver.link_counts()
      assert opened >= 2 and closed >= opened
    end

    test "are listed only when a guide light is configured" do
      operations = fn ->
        Command.execute(%{"v" => 1, "op" => "capabilities.get"})["body"]["operations"]
      end

      assert "light.program" in operations.()
      assert "light.get" in operations.()

      previous = Application.get_env(:robine_wake, :guide_light)
      Application.put_env(:robine_wake, :guide_light, nil)
      on_exit(fn -> Application.put_env(:robine_wake, :guide_light, previous) end)

      refute "light.program" in operations.()
      refute "light.get" in operations.()

      assert %{"error" => %{"code" => "capability_unavailable"}} =
               program(%{"program" => "off"})
    end
  end
end
