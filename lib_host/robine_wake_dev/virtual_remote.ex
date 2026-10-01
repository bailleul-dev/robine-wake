defmodule RobineWakeDev.VirtualRemote do
  @moduledoc """
  The bedside remote (ESP32, `hardware/remote_button/src/main.cpp`) played by
  the server in demo mode.

  It pairs like a real button (`RemoteButton.begin_pairing/1` then
  `RemoteButton.pair/2`), keeps the secret and the anti-replay counter on the
  server, and sends the same signed `remote_button.dismiss` command as the
  firmware through `RobineWake.Bluetooth.Command.execute/1`, the handler of
  `POST /api/v1/command`. The secret never reaches the browser, and every
  visitor of the shared demo presses the same remote with the same counter.

  `press/0` returns the firmware's feedback screen: `:dismissed`, `:idle`,
  `:not_paired` or `:server_error`.
  """

  use GenServer

  alias RobineWake.Bluetooth.Command
  alias RobineWake.RemoteButton

  @button_id "demo-remote"
  @button_name "Demo remote"

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def button_id, do: @button_id
  def press, do: GenServer.call(__MODULE__, :press)

  @doc "Pairs again after a factory reset, starting a new counter."
  def pair, do: GenServer.call(__MODULE__, :pair)

  @impl true
  def init(_opts), do: {:ok, %{secret: nil, counter: 1}, {:continue, :pair}}

  @impl true
  def handle_continue(:pair, state), do: {:noreply, do_pair(state)}

  @impl true
  def handle_call(:pair, _from, state) do
    state = do_pair(state)
    {:reply, if(state.secret, do: :ok, else: {:error, :pairing_failed}), state}
  end

  def handle_call(:press, _from, %{secret: nil} = state), do: {:reply, :not_paired, state}

  def handle_call(:press, _from, state) do
    request = %{
      "v" => 1,
      "id" => "demo-remote-#{System.unique_integer([:positive])}",
      "op" => "remote_button.dismiss",
      "body" => %{
        "button_id" => @button_id,
        "counter" => state.counter,
        "mac" => RemoteButton.mac(state.secret, @button_id, state.counter)
      }
    }

    {feedback, advance?} = feedback(Command.execute(request))
    state = if advance?, do: %{state | counter: state.counter + 1}, else: state
    {:reply, feedback, state}
  end

  # Same mapping as dismissAlarm() in the firmware.
  defp feedback(%{"status" => "ok"}), do: {:dismissed, true}
  defp feedback(%{"error" => %{"code" => "no_active_session"}}), do: {:idle, true}

  defp feedback(%{"error" => %{"code" => code}})
       when code in [
              "remote_button_not_paired",
              "invalid_remote_button_signature",
              "remote_button_replay"
            ],
       do: {:not_paired, false}

  defp feedback(_response), do: {:server_error, false}

  defp do_pair(state) do
    _ = RemoteButton.remove(@button_id)

    with {:ok, _status} <- RemoteButton.begin_pairing(30),
         {:ok, %{secret_hex: secret_hex, next_counter: counter}} <-
           RemoteButton.pair(@button_id, @button_name) do
      %{state | secret: Base.decode16!(secret_hex, case: :lower), counter: counter}
    else
      _error -> %{state | secret: nil}
    end
  end
end
