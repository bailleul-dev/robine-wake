defmodule RobineWake.Hue.Driver.Emulated do
  @moduledoc """
  Virtual Philips Hue bridge for demo mode. Pairing always succeeds and the
  bridge exposes the lights of the sound bar (breathing halo, bedside lamps)
  as Hue targets. Commands from the real `RobineWake.Hue` service are applied
  to `RobineWakeDev.Hardware`, which the 3D room renders.
  """

  @behaviour RobineWake.Hue.Driver

  alias RobineWakeDev.Hardware

  @impl true
  def pair(_host) do
    {:ok, %{"host" => "emulated-bridge", "application_key" => "demo", "client_key" => "demo"}}
  end

  @impl true
  def targets(_config), do: {:ok, Hardware.hue_targets()}

  @impl true
  def get_target(_config, target_id), do: Hardware.hue_state(target_id)

  @impl true
  def set_target(_config, target_id, changes), do: Hardware.apply_hue(target_id, changes)
end
