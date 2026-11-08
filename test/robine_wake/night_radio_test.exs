defmodule RobineWake.NightRadioTest do
  use RobineWake.DomainCase

  alias RobineWake.{ClockQuality, Health, Network, NightRadio}
  alias RobineWake.NightRadio.Driver.Rfkill

  # The DomainCase manual clock reads 2026-01-15 06:00 UTC, 07:00 in Paris.
  @covering %{enabled: true, start: "06:30", end: "07:30"}

  setup do
    on_exit(fn ->
      Application.delete_env(:robine_wake, :host_night_radio_failure)
      {:ok, _settings} = Settings.set_night_radio(%{enabled: false})
      NightRadio.evaluate()
    end)

    :ok
  end

  describe "quiet window" do
    @paris %{start: "23:00", end: "07:00", timezone: "Europe/Paris"}

    test "spans midnight in local time" do
      assert NightRadio.in_window?(@paris, ~U[2026-01-15 22:30:00Z])
      assert NightRadio.in_window?(@paris, ~U[2026-01-15 05:59:59Z])
      refute NightRadio.in_window?(@paris, ~U[2026-01-15 06:00:00Z])
      refute NightRadio.in_window?(@paris, ~U[2026-01-15 21:59:59Z])
      # Summer time: 23:00 in Paris is 21:00 UTC.
      assert NightRadio.in_window?(@paris, ~U[2026-07-15 21:00:00Z])
    end

    test "supports a window within a single day" do
      nap = %{start: "13:00", end: "15:00", timezone: "Europe/Paris"}
      assert NightRadio.in_window?(nap, ~U[2026-01-15 12:00:00Z])
      refute NightRadio.in_window?(nap, ~U[2026-01-15 14:00:00Z])
    end

    test "keeps the radios on unless every condition holds" do
      config = Map.put(@paris, :enabled, true)
      night = ~U[2026-01-15 01:00:00Z]

      assert NightRadio.decide(config, night, true, false) == {true, :quiet_window}
      assert NightRadio.decide(config, night, false, false) == {false, :clock_untrusted}
      assert NightRadio.decide(config, night, true, true) == {false, :wake_session}

      assert NightRadio.decide(config, ~U[2026-01-15 12:00:00Z], true, false) ==
               {false, :outside_window}

      assert NightRadio.decide(%{config | enabled: false}, night, true, false) ==
               {false, :disabled}
    end
  end

  test "silences the radios in the window and restores them when disabled" do
    assert %{state: :radios_on, reason: :disabled} = NightRadio.evaluate()

    assert {:ok, %{enabled: true, start: "06:30"}} = Settings.set_night_radio(@covering)
    assert %{state: :silenced, reason: :quiet_window} = NightRadio.evaluate()
    assert NightRadio.silenced?()
    assert Application.get_env(:robine_wake, :host_night_radio_silenced)

    assert {:ok, %{enabled: false}} = Settings.set_night_radio(%{"enabled" => false})
    assert %{state: :radios_on, reason: :disabled} = NightRadio.evaluate()
    refute Application.get_env(:robine_wake, :host_night_radio_silenced)
  end

  test "keeps the radios on while the clock is untrusted, so NTP can synchronize" do
    {:ok, _settings} = Settings.set_night_radio(@covering)
    :ok = ClockQuality.mark_untrusted(:test)

    assert %{state: :radios_on, reason: :clock_untrusted} = NightRadio.evaluate()

    {:ok, _clock} = ClockQuality.confirm()
    assert %{state: :silenced} = NightRadio.evaluate()
  end

  test "restores the radios while a wake session runs" do
    {:ok, _settings} = Settings.set_night_radio(@covering)
    assert %{state: :silenced} = NightRadio.evaluate()

    {:ok, alarm} = Settings.create_alarm(%{local_time: "08:00", days_of_week: [1]})
    {:ok, _pid} = Scheduler.trigger_now(alarm.id)

    assert %{state: :radios_on, reason: :wake_session} = NightRadio.evaluate()

    WakeSession.dismiss(:test_cleanup)
    assert %{state: :silenced} = NightRadio.evaluate()
  end

  test "a lost link is reported as silenced and does not degrade health" do
    previous = Application.get_env(:robine_wake, :host_network_state, :available)
    Application.put_env(:robine_wake, :host_network_state, :unavailable)
    on_exit(fn -> Application.put_env(:robine_wake, :host_network_state, previous) end)

    {:ok, _settings} = Settings.set_night_radio(@covering)
    NightRadio.evaluate()

    assert %{state: :silenced, reason: :night_radio} = Network.status()
    assert %{network: %{state: :silenced}, night_radio: %{state: :silenced}} = Health.snapshot()
  end

  test "reports a driver failure and retries until it succeeds" do
    Application.put_env(:robine_wake, :host_night_radio_failure, :eperm)
    {:ok, _settings} = Settings.set_night_radio(@covering)

    assert %{state: :error, error: :eperm} = NightRadio.evaluate()
    refute NightRadio.silenced?()

    Application.delete_env(:robine_wake, :host_night_radio_failure)
    assert %{state: :silenced, error: nil} = NightRadio.evaluate()
  end

  test "validates the window before persisting it" do
    assert {:error, %{start: "must be HH:MM"}} = Settings.set_night_radio(%{start: "24:00"})
    assert {:error, %{end: "must be HH:MM"}} = Settings.set_night_radio(%{end: "7:00"})
    assert {:error, %{enabled: _}} = Settings.set_night_radio(%{enabled: "yes"})

    assert {:error, %{end: "must differ from start"}} =
             Settings.set_night_radio(%{start: "07:00", end: "07:00"})

    assert {:error, _} = Settings.set_night_radio(:on)
    assert %{enabled: false, start: "23:00", end: "07:00"} = Settings.night_radio()
  end

  describe "rfkill driver" do
    setup do
      root = Path.join(System.tmp_dir!(), "rfkill-#{System.unique_integer([:positive])}")

      for {index, type, name} <- [
            {0, "bluetooth", "hci0"},
            {1, "wlan", "phy0"},
            {2, "nfc", "nfc0"}
          ] do
        dir = Path.join(root, "rfkill#{index}")
        File.mkdir_p!(dir)
        File.write!(Path.join(dir, "type"), type <> "\n")
        File.write!(Path.join(dir, "name"), name <> "\n")
        File.write!(Path.join(dir, "soft"), "0\n")
        File.write!(Path.join(dir, "hard"), "0\n")
      end

      Application.put_env(:robine_wake, :rfkill_root, root)

      on_exit(fn ->
        Application.delete_env(:robine_wake, :rfkill_root)
        File.rm_rf!(root)
      end)

      {:ok, root: root}
    end

    test "soft-blocks only Wi-Fi and Bluetooth", %{root: root} do
      assert :ok = Rfkill.set_silenced(true)

      assert File.read!(Path.join(root, "rfkill0/soft")) == "1"
      assert File.read!(Path.join(root, "rfkill1/soft")) == "1"
      assert File.read!(Path.join(root, "rfkill2/soft")) == "0\n"

      assert %{
               radios: [
                 %{type: "bluetooth", name: "hci0", soft_blocked: true},
                 %{type: "wlan", name: "phy0", soft_blocked: true}
               ]
             } = Rfkill.status()

      assert :ok = Rfkill.set_silenced(false)
      assert %{radios: [%{soft_blocked: false}, %{soft_blocked: false}]} = Rfkill.status()
    end

    test "fails when no radio is present", %{root: root} do
      File.rm_rf!(root)
      assert {:error, :no_radio} = Rfkill.set_silenced(true)
    end
  end
end
