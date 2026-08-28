defmodule RobineWake.Camera.Driver.Host do
  @moduledoc false
  @behaviour RobineWake.Camera.Driver

  @impl true
  def capabilities,
    do: %{
      state: :available,
      kind: :simulated_ir,
      formats: [:grayscale8],
      resolution: %{width: 320, height: 240}
    }

  @impl true
  def health do
    case Application.get_env(:robine_wake, :host_camera_state, :available) do
      :available -> %{state: :available, source: :host_simulator}
      :unavailable -> %{state: :degraded, source: :host_simulator, reason: :camera_unavailable}
      other -> %{state: :degraded, source: :host_simulator, reason: other}
    end
  end

  @impl true
  def capture(_opts), do: {:error, :use_submit_frame_on_host}
end
