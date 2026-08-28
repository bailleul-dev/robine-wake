defmodule RobineWake.FirmwareTest do
  use ExUnit.Case, async: true

  test "host health exposes firmware identity without target side effects" do
    assert %{
             state: :available,
             target: :host,
             version: "0.1.0",
             validation: :not_applicable,
             slots: %{active: :host, next: :host}
           } = RobineWake.Firmware.status()
  end
end
