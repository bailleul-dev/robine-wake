defmodule RobineWake.GuideLight do
  @moduledoc """
  NeoPixel guide light wired to the ESP32, driven through its low-level
  `light.set` command.

  The Raspberry Pi owns the breathing clock because it is the master of the
  audio: it sends one command per phase, at the phase boundary, with the
  transition the ESP32 interpolates. Commands are serialized here so an
  `off` never overtakes the last fade, and never block the caller. A
  failure is logged and the breathing session continues without the light.

  This module speaks the API-002 envelope; the configured driver only moves
  bytes (UART on the GPIO header, or HTTP over Wi-Fi):

      config :robine_wake, guide_light: [driver: RobineWake.GuideLight.Driver.UART, device: "ttyS0"]
  """

  use GenServer
  require Logger

  alias RobineWake.EventLog

  @type rgb :: %{r: 0..255, g: 0..255, b: 0..255}
  @type level :: %{
          required(:brightness) => number(),
          optional(:color) => rgb(),
          optional(:transition_ms) => non_neg_integer(),
          optional(:easing) => :linear | :smoothstep
        }

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Queues a light level; returns immediately."
  @spec set(level()) :: :ok
  def set(level), do: GenServer.cast(__MODULE__, {:set, level})

  @spec off(non_neg_integer()) :: :ok
  def off(transition_ms \\ 0), do: set(%{brightness: 0, transition_ms: transition_ms})

  def status, do: GenServer.call(__MODULE__, :status)

  def configured?, do: is_list(Application.get_env(:robine_wake, :guide_light))

  @impl true
  def init(_opts), do: {:ok, %{conn: nil, sequence: 0, last_error: nil}}

  @impl true
  def handle_cast({:set, level}, state) do
    case Application.get_env(:robine_wake, :guide_light) do
      nil -> {:noreply, state}
      config -> {:noreply, send_level(state, config, level)}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status =
      cond do
        not configured?() -> :not_configured
        state.last_error -> :unavailable
        true -> :available
      end

    {:reply, %{state: status, last_error: state.last_error && inspect(state.last_error)}, state}
  end

  defp send_level(state, config, level) do
    {driver, options} = Keyword.pop!(config, :driver)
    id = "guide-light-#{state.sequence + 1}"
    state = %{state | sequence: state.sequence + 1}
    request = Jason.encode!(%{"v" => 1, "id" => id, "op" => "light.set", "body" => encode(level)})

    with {:ok, conn} <- connect(state, driver, options),
         state = %{state | conn: conn},
         {:ok, response} <- driver.request(conn, id, request),
         :ok <- check_response(response) do
      %{state | last_error: nil}
    else
      {:error, reason} -> failed(state, driver, reason)
    end
  end

  defp connect(%{conn: nil}, driver, options), do: driver.open(options)
  defp connect(%{conn: conn}, _driver, _options), do: {:ok, conn}

  defp check_response(response) do
    case Jason.decode(response) do
      {:ok, %{"status" => "ok"}} -> :ok
      {:ok, %{"error" => %{"code" => code}}} -> {:error, {:guide_light_rejected, code}}
      _ -> {:error, :invalid_guide_light_response}
    end
  end

  # The link is reopened on the next command; logged once per outage.
  defp failed(state, driver, reason) do
    if state.conn, do: driver.close(state.conn)

    if is_nil(state.last_error) do
      EventLog.emit(:guide_light_failed,
        source: :guide_light,
        severity: :warning,
        payload: %{reason: inspect(reason)}
      )
    end

    %{state | conn: nil, last_error: reason}
  end

  defp encode(level) do
    %{"brightness" => level.brightness}
    |> put("color", level[:color] && Map.take(level.color, [:r, :g, :b]))
    |> put("transition_ms", level[:transition_ms])
    |> put("easing", level[:easing] && Atom.to_string(level.easing))
  end

  defp put(map, _key, nil), do: map
  defp put(map, key, value), do: Map.put(map, key, value)
end
