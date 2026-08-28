defmodule RobineWake.Id do
  @moduledoc false

  def generate do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c = Bitwise.band(c, 0x0FFF) + 0x4000
    d = Bitwise.band(d, 0x3FFF) + 0x8000

    Enum.join(
      [hex(a, 8), hex(b, 4), hex(c, 4), hex(d, 4), hex(e, 12)],
      "-"
    )
  end

  defp hex(value, width),
    do: value |> Integer.to_string(16) |> String.pad_leading(width, "0")
end
