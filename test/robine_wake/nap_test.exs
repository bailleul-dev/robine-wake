defmodule RobineWake.NapTest do
  use RobineWake.DomainCase

  alias RobineWake.Bluetooth.Command
  alias RobineWake.Nap

  test "schedules a one-shot alarm with a two-minute ramp" do
    assert {:ok, nap} = Nap.start(20)

    assert %{id: "nap", label: "Sieste", enabled: true, prewake_seconds: 120} = nap
    assert nap.one_shot_date == ~D[2026-01-15]
    assert nap.local_time == ~T[07:20:00]
    assert nap.volume_profile.ramp_seconds == 120
    refute nap.snooze.enabled
    assert Scheduler.status().next["nap"] == "2026-01-15T07:20:00+01:00"
  end

  test "never ramps longer than the nap itself" do
    assert {:ok, %{prewake_seconds: 60}} = Nap.start(1)
  end

  test "reuses the sounds and volume of the regular alarm" do
    {:ok, _alarm} =
      Settings.create_alarm(%{
        local_time: "07:00",
        days_of_week: [1],
        volume_profile: %{start: 10, ceiling: 60, ramp_seconds: 1_200}
      })

    assert {:ok, nap} = Nap.start(30)
    assert %{start: 10, ceiling: 60, ramp_seconds: 120} = nap.volume_profile
  end

  test "rings at the end of the nap, then a new nap replaces the spent one" do
    assert {:ok, _nap} = Nap.start(10)

    Clock.Manual.advance(4 * 60_000)
    Scheduler.tick()
    refute WakeSession.active()

    Clock.Manual.advance(60_000)
    Scheduler.tick()
    assert %{alarm_id: "nap", state: :ringing} = WakeSession.active()

    WakeSession.dismiss(:test)
    assert {:ok, %{enabled: false}} = Settings.get_alarm("nap")

    assert {:ok, %{enabled: true}} = Nap.start(15)
    assert [%{id: "nap"}] = Settings.list_alarms()
  end

  test "cancels a pending nap" do
    assert {:ok, _nap} = Nap.start(20)
    assert :ok = Nap.cancel()
    assert :ok = Nap.cancel()
    assert [] = Settings.list_alarms()
  end

  test "rejects durations outside the supported range" do
    assert {:error, %{duration_minutes: _}} = Nap.start(0)
    assert {:error, %{duration_minutes: _}} = Nap.start(181)
    assert {:error, %{duration_minutes: _}} = Nap.start("20")
  end

  test "is reachable through the versioned command boundary" do
    assert %{"status" => "ok", "body" => %{"id" => "nap", "prewake_seconds" => 120}} =
             Command.execute(%{
               "v" => 1,
               "id" => "nap-start",
               "op" => "nap.start",
               "body" => %{"duration_minutes" => 20}
             })

    assert %{"status" => "ok", "body" => %{"cancelled" => true}} =
             Command.execute(%{
               "v" => 1,
               "id" => "nap-cancel",
               "op" => "nap.cancel",
               "body" => %{}
             })

    assert [] = Settings.list_alarms()
  end
end
