defmodule RobineWake.Firmware do
  @moduledoc "Read-only firmware identity, slot, and validation health."

  alias Nerves.Runtime

  def status do
    version = Application.spec(:robine_wake, :vsn) |> to_string()

    if Application.fetch_env!(:robine_wake, :target) == :host do
      %{
        state: :available,
        version: version,
        target: :host,
        validation: :not_applicable,
        slots: %{active: :host, next: :host}
      }
    else
      validation = safe(fn -> Runtime.firmware_validation_status() end, :unknown)
      slots = safe(fn -> Runtime.firmware_slots() end, %{active: :unknown, next: :unknown})
      uuid = safe(fn -> Runtime.KV.get_active("nerves_fw_uuid") end, nil)

      %{
        state: if(validation == :unvalidated, do: :degraded, else: :available),
        version: version,
        target: Application.fetch_env!(:robine_wake, :target),
        build_id: uuid,
        validation: validation,
        slots: slots
      }
    end
  end

  defp safe(fun, default) do
    fun.()
  rescue
    _exception -> default
  catch
    :exit, _reason -> default
  end
end
