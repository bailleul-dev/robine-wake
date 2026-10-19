defmodule RobineWake.GuideLightTest do
  use RobineWake.DomainCase

  alias RobineWake.{EventLog, GuideLight}
  alias RobineWake.GuideLight.Driver.Test, as: GuideLightDriver

  @amber %{r: 255, g: 120, b: 12}
  @rose %{r: 255, g: 40, b: 70}

  defp commands do
    # A call is processed after every cast queued before it.
    _ = GuideLight.status()
    GuideLightDriver.commands()
  end

  test "the Pi drives one transition per breathing phase, eased like the audio" do
    assert {:ok, _status} = Hue.pair("192.168.1.42")

    assert {:ok, %{guide_light: %{configured: true}}} = Hue.start_breathing("bedroom-group")

    assert [
             %{color: @rose, brightness: 2, transition_ms: 0},
             %{color: @amber, brightness: 30, transition_ms: 4_000, easing: "smoothstep"}
           ] = commands()

    %{breathing: %{token: token}} = :sys.get_state(Hue)
    send(Hue, {:breathing_phase, token})
    assert eventually(fn -> Hue.status().breathing.phase == :exhale end)

    assert %{color: @rose, brightness: 2, transition_ms: 6_000, easing: "smoothstep"} =
             List.last(commands())

    send(Hue, {:breathing_phase, token})
    assert eventually(fn -> Hue.status().breathing.phase == :inhale end)
    assert %{color: @amber, transition_ms: 4_000} = List.last(commands())

    assert {:ok, %{active: false}} = Hue.stop_breathing()
    assert %{brightness: 0, transition_ms: 1_500} = List.last(commands())
  end

  test "an alarm turns the guide light off with the breathing session" do
    assert {:ok, _status} = Hue.pair("192.168.1.42")
    assert {:ok, %{active: true}} = Hue.start_breathing("bedroom-group")

    assert :ok = Hue.start_wake("wake-session", %{enabled: false})

    assert %{active: false} = Hue.status().breathing
    assert %{brightness: 0} = List.last(commands())
  end

  test "an unreachable ESP32 leaves breathing running and is logged once" do
    GuideLightDriver.set_result({:error, {:guide_light_unreachable, :timeout}})
    assert {:ok, _status} = Hue.pair("192.168.1.42")
    assert {:ok, %{active: true}} = Hue.start_breathing("bedroom-group")

    %{breathing: %{token: token}} = :sys.get_state(Hue)
    send(Hue, {:breathing_phase, token})
    assert eventually(fn -> Hue.status().breathing.phase == :exhale end)

    assert length(commands()) == 3
    assert %{state: :unavailable} = GuideLight.status()
    assert %{active: true} = Hue.status().breathing
    assert [_] = Enum.filter(EventLog.recent(), &(&1.code == "guide_light_failed"))

    GuideLightDriver.set_result(:ok)
    assert {:ok, %{active: false}} = Hue.stop_breathing()
    assert %{state: :available} = GuideLight.status()
  end

  test "sends nothing without a configured ESP32" do
    config = Application.get_env(:robine_wake, :guide_light)
    Application.delete_env(:robine_wake, :guide_light)
    on_exit(fn -> Application.put_env(:robine_wake, :guide_light, config) end)

    assert {:ok, _status} = Hue.pair("192.168.1.42")

    assert {:ok, %{active: true, guide_light: %{configured: false}}} =
             Hue.start_breathing("bedroom-group")

    assert {:ok, _} = Hue.stop_breathing()
    assert [] = commands()
    assert %{state: :not_configured} = GuideLight.status()
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
