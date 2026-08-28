defmodule RobineWake.Audio.Driver.Host do
  @moduledoc false
  @behaviour RobineWake.Audio.Driver

  @impl true
  def capabilities do
    case state() do
      :unavailable ->
        %{state: :degraded, device: "host-simulator", gain: true, reason: :audio_unavailable}

      _ ->
        %{state: :available, device: "host-simulator", gain: true}
    end
  end

  @impl true
  def prepare(_sound_id) do
    case state() do
      :unavailable -> {:error, :audio_unavailable}
      :failing -> {:error, :injected_audio_failure}
      _ -> :ok
    end
  end

  @impl true
  def play(session_id, sound_id) do
    case state() do
      :unavailable -> {:error, :audio_unavailable}
      :failing -> {:error, :injected_audio_failure}
      _ -> {:ok, {:simulated, session_id, sound_id}}
    end
  end

  @impl true
  def set_gain(gain) when gain in 0..100 do
    if state() in [:unavailable, :failing], do: {:error, :audio_unavailable}, else: :ok
  end

  @impl true
  def stop(_handle), do: :ok

  @impl true
  def status, do: capabilities()

  defp state, do: Application.get_env(:robine_wake, :host_audio_state, :available)
end
