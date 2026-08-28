defmodule RobineWake.AlarmPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias RobineWake.Alarm

  property "recurring occurrence generation is strictly ordered and duplicate-free" do
    check all(
            hour <- integer(0..23),
            minute <- integer(0..59),
            generated_days <- list_of(integer(1..7), min_length: 1, max_length: 14)
          ) do
      days = Enum.uniq(generated_days)
      local_time = :io_lib.format("~2..0B:~2..0B", [hour, minute]) |> IO.iodata_to_binary()
      assert {:ok, alarm} = Alarm.new(%{local_time: local_time, days_of_week: days})

      occurrences = Alarm.next_occurrences(alarm, 20, ~U[2026-01-01 00:00:00Z])

      assert length(occurrences) == 20
      assert Enum.uniq(occurrences) == occurrences

      assert Enum.chunk_every(occurrences, 2, 1, :discard)
             |> Enum.all?(fn [first, second] -> DateTime.before?(first, second) end)
    end
  end

  test "10,000 daily recalculations contain no duplicate occurrence" do
    assert {:ok, alarm} =
             Alarm.new(%{
               local_time: "07:00",
               days_of_week: [1, 2, 3, 4, 5, 6, 7],
               timezone: "Europe/Paris"
             })

    occurrences = Alarm.next_occurrences(alarm, 10_000, ~U[2026-01-01 00:00:00Z])

    assert length(occurrences) == 10_000
    assert MapSet.size(MapSet.new(occurrences)) == 10_000
  end
end
