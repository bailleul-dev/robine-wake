defmodule RobineWakeDev.Clock.ScaledTest do
  use ExUnit.Case, async: false

  alias RobineWakeDev.Clock.Scaled

  setup do
    start_supervised!({Scaled, utc: ~U[2026-10-01 21:00:00Z]})
    :ok
  end

  test "virtual time runs at the chosen speed" do
    assert Scaled.utc_now() == ~U[2026-10-01 21:00:00Z]
    :ok = Scaled.set_speed(60)
    start = Scaled.monotonic_ms()
    Process.sleep(50)
    elapsed = Scaled.monotonic_ms() - start
    assert elapsed >= 50 * 60
    assert elapsed < 50 * 60 * 4
    assert Scaled.snapshot().speed == 60
  end

  test "rejects unsupported speeds" do
    assert {:error, :unsupported_speed} = Scaled.set_speed(7)
  end

  test "a speed change re-arms pending timers on their virtual deadline" do
    Scaled.send_after(self(), :due, 6_000)
    refute_receive :due, 50
    :ok = Scaled.set_speed(60)
    # 6 virtual seconds at ×60 take about 100 ms.
    assert_receive :due, 500
  end

  test "advance fires the due timers in deadline order and keeps the others" do
    Scaled.send_after(self(), :second, 2_000)
    Scaled.send_after(self(), :first, 1_000)
    Scaled.send_after(self(), :later, 3_600_000)
    :ok = Scaled.advance(5_000)
    assert_received :first
    assert_received :second
    refute_received :later
    assert DateTime.diff(Scaled.utc_now(), ~U[2026-10-01 21:00:05Z]) in 0..1
  end

  test "cancel_timer returns the remaining virtual time" do
    reference = Scaled.send_after(self(), :never, 10_000)
    remaining = Scaled.cancel_timer(reference)
    assert remaining in 9_000..10_000
    assert Scaled.cancel_timer(reference) == false
    :ok = Scaled.advance(20_000)
    refute_received :never
  end

  test "set_utc moves the wall clock but never the monotonic time backwards" do
    before = Scaled.monotonic_ms()
    :ok = Scaled.set_utc(~U[2026-10-01 06:00:00Z])
    assert DateTime.diff(Scaled.utc_now(), ~U[2026-10-01 06:00:00Z]) in 0..1
    assert Scaled.monotonic_ms() >= before
  end
end
