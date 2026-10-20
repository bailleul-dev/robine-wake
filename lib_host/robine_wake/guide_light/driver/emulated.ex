defmodule RobineWake.GuideLight.Driver.Emulated do
  @moduledoc """
  LED strip of demo mode: answers the ESP32's API-002 commands and shows
  each program on the halo of the 3D room, as one colour the viewer
  interpolates (the room has no pixels). A dawn rises from a faint orange to
  daylight, a sunset fades from amber to dark, a breathing session holds a
  dim red, a reading light holds a warm white. `light.get` reports the program and a uniform strip of the same
  colours.
  """

  @behaviour RobineWake.GuideLight.Driver

  alias RobineWakeDev.Hardware

  @output "halo"
  @orange %{x: 0.6, y: 0.38}
  @red %{x: 0.68, y: 0.31}
  # Colour temperatures, in mireds: 2200 K amber, 5500 K daylight.
  @amber 455
  @daylight 182
  @pixels 60

  @impl true
  def open(_options), do: {:ok, :emulated}

  @impl true
  def close(_conn), do: :ok

  @impl true
  def request(_conn, id, request) do
    %{"op" => operation, "body" => body} = Jason.decode!(request)

    case show(operation, body) do
      :ok -> {:ok, Jason.encode!(%{v: 1, id: id, status: "ok", body: status()})}
      {:error, code} -> {:ok, Jason.encode!(%{v: 1, id: id, status: "error", error: %{code: code}})}
    end
  end

  defp show("light.get", _body), do: :ok

  defp show("light.program", %{"program" => "dawn", "duration_ms" => duration} = body) do
    remember(body, duration)
    light(%{on: true, brightness: 2.0, xy: @orange})
    light(%{on: true, brightness: 60.0, mirek: @daylight, transition_ms: duration})
  end

  defp show("light.program", %{"program" => "sunset", "duration_ms" => duration} = body) do
    remember(body, duration)
    light(%{on: true, brightness: 24.0, mirek: @amber})
    light(%{on: true, brightness: 0.0, transition_ms: duration})
  end

  # A reading light, then the 30-minute sunset of the ESP32.
  defp show("light.program", %{"program" => "reading", "duration_ms" => duration} = body) do
    sunset = Map.get(body, "sunset_ms", 1_800_000)
    remember(body, duration + sunset)
    light(%{on: true, brightness: 40.0, mirek: 370})
  end

  defp show("light.program", %{"program" => "breathing", "duration_ms" => duration} = body) do
    remember(body, duration)
    light(%{on: true, brightness: 4.0, xy: @red})
  end

  defp show("light.program", %{"program" => "off"}) do
    Process.delete(__MODULE__)
    light(%{on: false})
  end
  defp show("light.program", _body), do: {:error, "invalid_program"}

  defp show("light.set", %{"brightness" => brightness} = body) do
    Process.delete(__MODULE__)

    light(%{
      on: brightness > 0,
      brightness: brightness * 1.0,
      transition_ms: Map.get(body, "transition_ms", 0)
    })
  end

  defp show(_operation, _body), do: {:error, "unsupported_operation"}

  defp light(changes), do: Hardware.apply_light(@output, changes)

  # Requests all come from the GuideLight process, which keeps the program.
  defp remember(body, duration_ms),
    do: Process.put(__MODULE__, {body, System.monotonic_time(:millisecond), duration_ms})

  defp status do
    case Process.get(__MODULE__) do
      nil ->
        %{name: "Emulated strip", program: nil, pixels: pixels({0, 0, 0})}

      {%{"program" => program} = body, started_ms, duration_ms} ->
        elapsed_ms = System.monotonic_time(:millisecond) - started_ms
        progress = min(elapsed_ms / duration_ms, 1.0)

        %{
          name: "Emulated strip",
          program: program,
          cadence: body["cadence"],
          elapsed_ms: elapsed_ms,
          duration_ms: duration_ms,
          pixels: pixels(colour(program, progress))
        }
    end
  end

  defp colour("dawn", progress), do: mix({60, 12, 0}, {255, 210, 160}, progress)
  defp colour("sunset", progress), do: mix({110, 40, 4}, {0, 0, 0}, progress)
  defp colour("breathing", _progress), do: {10, 0, 0}
  defp colour("reading", _progress), do: {153, 84, 24}

  defp mix({r1, g1, b1}, {r2, g2, b2}, t),
    do: {round(r1 + (r2 - r1) * t), round(g1 + (g2 - g1) * t), round(b1 + (b2 - b1) * t)}

  defp pixels({r, g, b}) do
    hex = Base.encode16(<<r, g, b>>, case: :lower)
    String.duplicate(hex, @pixels)
  end
end
