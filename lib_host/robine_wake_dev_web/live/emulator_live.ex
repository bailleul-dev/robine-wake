defmodule RobineWakeDevWeb.EmulatorLive do
  use RobineWakeDevWeb, :live_view

  alias RobineWakeDev.Emulator

  @refresh_ms 500

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()
    {:ok, socket |> assign(:message, nil) |> refresh()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_event("camera", %{"mode" => mode}, socket),
    do: action(socket, fn -> Emulator.camera(String.to_existing_atom(mode)) end)

  def handle_event("calibrate-camera", _params, socket),
    do: action(socket, &Emulator.calibrate_camera/0)

  def handle_event("network", %{"mode" => mode}, socket),
    do: action(socket, fn -> Emulator.network(String.to_existing_atom(mode)) end)

  def handle_event("audio", %{"mode" => mode}, socket),
    do: action(socket, fn -> Emulator.audio(String.to_existing_atom(mode)) end)

  def handle_event("crash-audio", _params, socket),
    do: action(socket, &Emulator.crash_active_audio/0)

  def handle_event("clock-quality", %{"mode" => mode}, socket),
    do: action(socket, fn -> Emulator.clock_quality(String.to_existing_atom(mode)) end)

  def handle_event("manual-clock", _params, socket),
    do: action(socket, &Emulator.enable_manual_clock/0)

  def handle_event("system-clock", _params, socket),
    do: action(socket, &Emulator.use_system_clock/0)

  def handle_event("advance-time", %{"minutes" => minutes}, socket) do
    action(socket, fn ->
      case Integer.parse(minutes) do
        {value, ""} -> Emulator.advance_time(value)
        _ -> {:error, :invalid_duration}
      end
    end)
  end

  def handle_event("create-demo-alarm", _params, socket),
    do: action(socket, &Emulator.create_demo_alarm/0)

  def handle_event("trigger-alarm", %{"id" => id}, socket),
    do: action(socket, fn -> Emulator.trigger_alarm(id) end)

  def handle_event("snooze", _params, socket), do: action(socket, &Emulator.snooze/0)
  def handle_event("dismiss", _params, socket), do: action(socket, &Emulator.dismiss/0)
  def handle_event("reset-hardware", _params, socket), do: action(socket, &Emulator.reset_hardware/0)

  @impl true
  def render(assigns) do
    ~H"""
    <main id="hardware-lab">
      <header>
        <div>
          <div class="eyebrow">Host-only development environment</div>
          <h1>Robine Wake Hardware Lab</h1>
          <p class="muted">Drive the real scheduler, wake-session state machine, detector, and health model without a Raspberry Pi.</p>
          <p><a href="/room">Open the demo room ↗</a></p>
        </div>
        <div class={"status #{status_class(@snapshot.health.state)}"}>
          System health<strong id="system-health">{display(@snapshot.health.state)}</strong>
        </div>
      </header>

      <p id="action-message" class="message">{@message}</p>

      <div class="grid">
        <section class="card wide">
          <h2>Infrared scene</h2>
          <div class="bed">
            <div class={"person #{scene_class(@snapshot)}"}></div>
            <span id="scene-state" class="bed-label">{scene_label(@snapshot)}</span>
          </div>
          <div class="controls" style="margin-top:.8rem">
            <button id="camera-calibrate" class="primary" phx-click="calibrate-camera">Calibrate empty bed</button>
            <button id="camera-occupied" phx-click="camera" phx-value-mode="occupied">Occupied frame</button>
            <button id="camera-vacant" phx-click="camera" phx-value-mode="vacant">Vacant frame</button>
            <button id="camera-unknown" phx-click="camera" phx-value-mode="unknown">Unusable frame</button>
            <button id="camera-saturated" phx-click="camera" phx-value-mode="saturated">IR saturation</button>
            <button id="camera-offline" class="danger" phx-click="camera" phx-value-mode="offline">Disconnect camera</button>
          </div>
        </section>

        <section class="card">
          <h2>Capabilities</h2>
          <div class="status-grid">
            <div class="status">Camera<strong id="camera-health" class={status_class(camera_state(@snapshot))}>{display(camera_state(@snapshot))}</strong></div>
            <div class="status">Audio<strong id="audio-health" class={status_class(@snapshot.health.audio.capabilities.state)}>{display(@snapshot.health.audio.capabilities.state)}</strong></div>
            <div class="status">Network<strong id="network-health" class={status_class(@snapshot.health.network.state)}>{display(@snapshot.health.network.state)}</strong></div>
            <div class="status">Clock<strong id="clock-health" class={status_class(@snapshot.health.clock.quality)}>{display(@snapshot.health.clock.quality)}</strong></div>
          </div>
          <p class="muted">Camera frames: {Map.get(@snapshot.health.camera, :frames, 0)} · dropped: {Map.get(@snapshot.health.camera, :dropped_frames, 0)}</p>
        </section>

        <section class="card">
          <h2>Audio hardware</h2>
          <div class="controls">
            <button id="audio-online" class="primary" phx-click="audio" phx-value-mode="available">Available</button>
            <button id="audio-failing" phx-click="audio" phx-value-mode="failing">Fail playback</button>
            <button id="audio-offline" class="danger" phx-click="audio" phx-value-mode="unavailable">Disconnect</button>
            <button id="audio-crash" class="danger" phx-click="crash-audio">Crash active player</button>
          </div>
          <p>Gain: <strong>{@snapshot.health.audio.gain}</strong></p>
          <p class="muted">Last error: {display(@snapshot.health.audio.last_error)}</p>
        </section>

        <section class="card">
          <h2>Network and time</h2>
          <div class="controls">
            <button id="network-online" class="primary" phx-click="network" phx-value-mode="available">Network online</button>
            <button id="network-offline" class="danger" phx-click="network" phx-value-mode="unavailable">Network offline</button>
            <button id="clock-trusted" phx-click="clock-quality" phx-value-mode="trusted">Trust clock</button>
            <button id="clock-untrusted" class="danger" phx-click="clock-quality" phx-value-mode="untrusted">Lose time trust</button>
          </div>
          <p>Clock source: <strong id="clock-mode">{display(@snapshot.hardware.clock)}</strong></p>
          <div class="controls">
            <button id="manual-clock" phx-click="manual-clock">Use manual clock</button>
            <button id="system-clock" phx-click="system-clock">Use system clock</button>
          </div>
          <form id="advance-time" class="inline" phx-submit="advance-time" style="margin-top:.7rem">
            <input name="minutes" type="number" min="1" max="1440" value="5" aria-label="Minutes to advance" />
            <button>Advance minutes</button>
          </form>
        </section>

        <section class="card full">
          <h2>Alarm and active session</h2>
          <div :if={@snapshot.session} class="status-grid" id="active-session">
            <div class="status">State<strong>{@snapshot.session.state}</strong></div>
            <div class="status">Gain<strong>{@snapshot.session.current_gain}</strong></div>
            <div class="status">Snoozes<strong>{@snapshot.session.snooze_count}</strong></div>
            <div class="status">Last observation<strong>{observation_state(@snapshot.session)}</strong></div>
          </div>
          <p :if={!@snapshot.session} id="no-session" class="muted">No wake session is active.</p>
          <div class="controls">
            <button id="session-snooze" phx-click="snooze">Snooze</button>
            <button id="session-dismiss" class="danger" phx-click="dismiss">Dismiss</button>
            <button id="create-demo-alarm" class="primary" phx-click="create-demo-alarm">Create demo alarm</button>
          </div>
          <table>
            <thead><tr><th>Alarm</th><th>Local schedule</th><th>Policy</th><th>Action</th></tr></thead>
            <tbody id="alarm-list">
              <tr :for={alarm <- @snapshot.alarms} id={"alarm-#{alarm.id}"}>
                <td><strong>{alarm.label}</strong><br/><code>{alarm.id}</code></td>
                <td>{Time.to_iso8601(alarm.local_time)} · {alarm.timezone}</td>
                <td>{alarm.dismiss_policy}</td>
                <td><button id={"trigger-#{alarm.id}"} phx-click="trigger-alarm" phx-value-id={alarm.id}>Trigger now</button></td>
              </tr>
            </tbody>
          </table>
        </section>

        <section class="card full">
          <h2>Developer controls</h2>
          <div class="controls">
            <button id="reset-hardware" phx-click="reset-hardware">Reset simulated hardware</button>
            <a href={@snapshot.product_url} style="color:#8de6cc;padding:.7rem">Open product interface ↗</a>
          </div>
          <p class="muted">This console is loopback-only and is excluded from the Raspberry Pi target compilation path.</p>
        </section>
      </div>
    </main>
    """
  end

  defp action(socket, fun) do
    message =
      case fun.() do
        :ok -> "Simulation updated."
        {:error, reason} -> "Action refused: #{inspect(reason)}"
        other -> "Simulation result: #{inspect(other)}"
      end

    {:noreply, socket |> assign(:message, message) |> refresh()}
  rescue
    error -> {:noreply, socket |> assign(:message, "Action failed: #{Exception.message(error)}") |> refresh()}
  end

  defp refresh(socket), do: assign(socket, :snapshot, Emulator.snapshot())
  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_ms)

  # A disabled camera reports only `%{state: :disabled}`.
  defp camera_state(snapshot),
    do: get_in(snapshot, [:health, :camera, :driver_health, :state]) || snapshot.health.camera.state

  defp scene_class(snapshot) do
    cond do
      snapshot.hardware.camera == :unavailable -> "offline"
      get_in(snapshot, [:health, :camera, :last_observation, :state]) == :occupied -> "occupied"
      get_in(snapshot, [:health, :camera, :last_observation, :state]) == :vacant -> "vacant"
      true -> "unknown"
    end
  end

  defp scene_label(snapshot) do
    observation = get_in(snapshot, [:health, :camera, :last_observation, :state])
    state = if snapshot.hardware.camera == :unavailable, do: :unavailable, else: observation
    "Scene: #{display(state || snapshot.hardware.camera)}"
  end

  defp observation_state(session),
    do: session |> Map.get(:last_observation) |> then(&if(&1, do: display(&1.state), else: "—"))
end
