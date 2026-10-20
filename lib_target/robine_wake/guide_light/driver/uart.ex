defmodule RobineWake.GuideLight.Driver.UART do
  @moduledoc """
  Line-delimited JSON over the UART of the GPIO header (GPIO 14 TX, 15 RX),
  wired to the ESP32's UART2.

  The kernel console also writes to this UART (`console=serial0` in the
  Nerves system cmdline), so the ESP32 ignores lines that are not JSON and
  responses are matched by request id; any other line is skipped.

  While the strip is lit, its data line puts glitches on the ESP32's RX and
  the ESP32 drops the request it was receiving. An unanswered request is
  sent again with the same id: the ESP32 runs it at most once and repeats
  its answer.
  """

  @behaviour RobineWake.GuideLight.Driver

  alias Circuits.UART

  @impl true
  def open(options) do
    device = Keyword.get(options, :device, "ttyS0")
    timeout = Keyword.get(options, :timeout_ms, 300)
    attempts = Keyword.get(options, :attempts, 4)

    with {:ok, uart} <- UART.start_link(),
         :ok <-
           UART.open(uart, device,
             speed: Keyword.get(options, :speed, 115_200),
             active: false,
             framing: {UART.Framing.Line, separator: "\n", max_length: 1_024}
           ) do
      {:ok, %{uart: uart, timeout: timeout, attempts: attempts}}
    end
  end

  @impl true
  def request(%{uart: uart, timeout: timeout, attempts: attempts}, id, request),
    do: attempt(uart, id, request, timeout, attempts)

  defp attempt(uart, id, request, timeout, attempts) do
    # Stale lines (console output, late responses) must not be taken for ours.
    _ = UART.flush(uart, :receive)

    # The line framing appends the separator.
    with :ok <- UART.write(uart, request),
         {:error, :guide_light_timeout} when attempts > 1 <-
           await(uart, id, System.monotonic_time(:millisecond) + timeout) do
      attempt(uart, id, request, timeout, attempts - 1)
    else
      {:error, reason} when is_atom(reason) and reason != :guide_light_timeout ->
        {:error, {:guide_light_uart, reason}}

      result ->
        result
    end
  end

  @impl true
  def close(%{uart: uart}) do
    _ = UART.close(uart)
    GenServer.stop(uart)
  end

  defp await(uart, id, deadline_ms) do
    remaining = deadline_ms - System.monotonic_time(:millisecond)

    with true <- remaining > 0 || {:error, :guide_light_timeout},
         {:ok, line} when is_binary(line) and line != "" <- UART.read(uart, remaining) do
      case Jason.decode(line) do
        {:ok, %{"id" => ^id}} -> {:ok, line}
        _ -> await(uart, id, deadline_ms)
      end
    else
      {:ok, _empty} -> {:error, :guide_light_timeout}
      {:error, {:partial, _}} -> await(uart, id, deadline_ms)
      {:error, reason} -> {:error, reason}
    end
  end
end
