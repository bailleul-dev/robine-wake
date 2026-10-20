defmodule RobineWake.GuideLight do
  @moduledoc """
  LED strip wired to the ESP32: the dawn of an alarm, the evening sunset and
  the breathing session are programs the ESP32 renders on its own, and
  `light.set` is a plain transition to one colour.

  `program/1` starts a program and waits for its answer, for the web UI;
  `start_program/1` and `set/1` return at once, for the wake session that
  must not wait on the light. Commands are serialized here so an `off`
  never overtakes the program before it. A failure is logged and the caller
  carries on without the light.

  This module speaks the API-002 envelope; the configured driver only moves
  bytes (UART on the GPIO header, or HTTP over Wi-Fi):

      config :robine_wake, guide_light: [driver: RobineWake.GuideLight.Driver.UART, device: "ttyS0"]
  """

  use GenServer

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

  @doc """
  Starts a `light.program` on the ESP32: `%{"program" => "dawn" | "sunset",
  "duration_ms" => ms}`, `%{"program" => "breathing", "cadence" => "0-4-0-6",
  "duration_ms" => ms}` or `%{"program" => "off"}`. Returns the light status sent back by the ESP32.
  """
  @spec program(map()) :: {:ok, map()} | {:error, term()}
  def program(body) when is_map(body),
    do: GenServer.call(__MODULE__, {:request, "light.program", body}, 5_000)

  @doc "Queues a `light.program` like `program/1`; returns immediately."
  @spec start_program(map()) :: :ok
  def start_program(body) when is_map(body), do: GenServer.cast(__MODULE__, {:program, body})

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

  def handle_cast({:program, body}, state) do
    case Application.get_env(:robine_wake, :guide_light) do
      nil ->
        {:noreply, state}

      config ->
        {state, _result} = send_request(state, config, "light.program", body)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:request, operation, body}, _from, state) do
    case Application.get_env(:robine_wake, :guide_light) do
      nil ->
        {:reply, {:error, :capability_unavailable}, state}

      config ->
        {state, result} = send_request(state, config, operation, body)
        {:reply, result, state}
    end
  end

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
    {state, _result} = send_request(state, config, "light.set", encode(level))
    state
  end

  defp send_request(state, config, operation, body) do
    {driver, options} = Keyword.pop!(config, :driver)
    id = "guide-light-#{state.sequence + 1}"
    state = %{state | sequence: state.sequence + 1}
    request = Jason.encode!(%{"v" => 1, "id" => id, "op" => operation, "body" => body})

    case connect(state, driver, options) do
      {:ok, conn} ->
        # Kept in the state before the request, so a failure closes it.
        state = %{state | conn: conn}

        with {:ok, response} <- driver.request(conn, id, request),
             {:ok, result} <- check_response(response) do
          {%{state | last_error: nil}, {:ok, result}}
        else
          # A rejected request is the caller's mistake: the link stays up.
          {:error, {:guide_light_rejected, _code} = reason} -> {state, {:error, reason}}
          {:error, reason} -> {failed(state, driver, reason), {:error, reason}}
        end

      {:error, reason} ->
        {failed(state, driver, reason), {:error, reason}}
    end
  end

  defp connect(%{conn: nil}, driver, options), do: driver.open(options)
  defp connect(%{conn: conn}, _driver, _options), do: {:ok, conn}

  defp check_response(response) do
    case Jason.decode(response) do
      {:ok, %{"status" => "ok"} = response} -> {:ok, Map.get(response, "body", %{})}
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
