defmodule RobineWake.GuideLight.Driver.Emulated do
  @moduledoc """
  LED strip of demo mode: answers the ESP32's API-002 commands and shows
  each program on the halo of the 3D room, as one colour the viewer
  interpolates (the room has no pixels). A dawn rises from a faint orange to
  daylight, a sunset fades from amber to dark, a breathing session holds a
  dim red.
  """

  @behaviour RobineWake.GuideLight.Driver

  alias RobineWakeDev.Hardware

  @output "halo"
  @orange %{x: 0.6, y: 0.38}
  @red %{x: 0.68, y: 0.31}
  # Colour temperatures, in mireds: 2200 K amber, 5500 K daylight.
  @amber 455
  @daylight 182

  @impl true
  def open(_options), do: {:ok, :emulated}

  @impl true
  def close(_conn), do: :ok

  @impl true
  def request(_conn, id, request) do
    %{"op" => operation, "body" => body} = Jason.decode!(request)

    case show(operation, body) do
      :ok -> {:ok, Jason.encode!(%{v: 1, id: id, status: "ok", body: status(operation, body)})}
      {:error, code} -> {:ok, Jason.encode!(%{v: 1, id: id, status: "error", error: %{code: code}})}
    end
  end

  defp show("light.program", %{"program" => "dawn", "duration_ms" => duration}) do
    light(%{on: true, brightness: 2.0, xy: @orange})
    light(%{on: true, brightness: 60.0, mirek: @daylight, transition_ms: duration})
  end

  defp show("light.program", %{"program" => "sunset", "duration_ms" => duration}) do
    light(%{on: true, brightness: 24.0, mirek: @amber})
    light(%{on: true, brightness: 0.0, transition_ms: duration})
  end

  defp show("light.program", %{"program" => "breathing"}),
    do: light(%{on: true, brightness: 4.0, xy: @red})

  defp show("light.program", %{"program" => "off"}), do: light(%{on: false})
  defp show("light.program", _body), do: {:error, "invalid_program"}

  defp show("light.set", %{"brightness" => brightness} = body) do
    light(%{
      on: brightness > 0,
      brightness: brightness * 1.0,
      transition_ms: Map.get(body, "transition_ms", 0)
    })
  end

  defp show(_operation, _body), do: {:error, "unsupported_operation"}

  defp light(changes), do: Hardware.apply_light(@output, changes)

  defp status("light.program", %{"program" => "off"}), do: %{name: "Emulated strip", program: nil}

  defp status("light.program", %{"program" => program}),
    do: %{name: "Emulated strip", program: program}

  defp status(_operation, _body), do: %{name: "Emulated strip", program: nil}
end
