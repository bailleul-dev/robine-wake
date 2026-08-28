defmodule RobineWake.Network.Driver.Host do
  @moduledoc false
  @behaviour RobineWake.Network.Driver

  @impl true
  def status do
    case Application.get_env(:robine_wake, :host_network_state, :available) do
      :available -> %{state: :available, source: :host_simulator}
      :unavailable -> %{state: :degraded, source: :host_simulator, reason: :network_unavailable}
      other -> %{state: :degraded, source: :host_simulator, reason: other}
    end
  end
end
