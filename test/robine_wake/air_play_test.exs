defmodule RobineWake.AirPlayTest do
  use ExUnit.Case, async: false

  alias RobineWake.AirPlay

  @airplay_child RobineWake.AirPlay

  setup do
    original = %{
      enabled: Application.fetch_env!(:robine_wake, :airplay_enabled),
      network_state: Application.get_env(:robine_wake, :host_network_state, :available),
      restart_delay: Application.fetch_env!(:robine_wake, :airplay_restart_delay_ms),
      receiver: Application.get_env(:robine_wake, :airplay_receiver, :shairport),
      robine_executable: Application.fetch_env!(:robine_wake, :airplay_robine_executable)
    }

    on_exit(fn ->
      :ok = Supervisor.terminate_child(RobineWake.Supervisor, @airplay_child)
      Application.put_env(:robine_wake, :airplay_enabled, original.enabled)
      Application.put_env(:robine_wake, :host_network_state, original.network_state)
      Application.put_env(:robine_wake, :airplay_restart_delay_ms, original.restart_delay)
      Application.put_env(:robine_wake, :airplay_receiver, original.receiver)
      Application.put_env(:robine_wake, :airplay_robine_executable, original.robine_executable)
      {:ok, _pid} = Supervisor.restart_child(RobineWake.Supervisor, @airplay_child)
    end)

    :ok = Supervisor.terminate_child(RobineWake.Supervisor, @airplay_child)
    Application.put_env(:robine_wake, :airplay_enabled, true)
    Application.put_env(:robine_wake, :host_network_state, :unavailable)
    Application.put_env(:robine_wake, :airplay_restart_delay_ms, 10)
    {:ok, _pid} = Supervisor.restart_child(RobineWake.Supervisor, @airplay_child)

    :ok
  end

  test "waits for the network before starting the receiver" do
    assert_eventually(fn ->
      match?(%{state: :starting, reason: :network_unavailable}, AirPlay.status())
    end)

    Application.put_env(:robine_wake, :host_network_state, :available)

    assert_eventually(fn ->
      match?(%{state: :starting, reason: :executable_not_found}, AirPlay.status())
    end)
  end

  describe "robine-airplayd receiver" do
    @tag :tmp_dir
    test "keeps its session on suspend and only releases ALSA", %{tmp_dir: tmp_dir} do
      start_robine(fake_receiver(tmp_dir, "echo '{\"event\":\"suspended\"}'"))

      assert_eventually(fn ->
        match?(
          %{state: :available, receiver: :robine, session: "playing", volume_db: -12.5},
          AirPlay.status()
        )
      end)

      assert :ok = AirPlay.suspend()
      assert %{state: :suspended} = AirPlay.status()
      assert File.read!(Path.join(tmp_dir, "commands")) =~ ~s({"cmd":"suspend"})

      assert :ok = AirPlay.resume()
      assert %{state: :available, session: "playing"} = AirPlay.status()

      assert_eventually(fn ->
        File.read!(Path.join(tmp_dir, "commands")) =~ ~s({"cmd":"resume"})
      end)
    end

    @tag :tmp_dir
    test "stops a receiver that does not release ALSA in time", %{tmp_dir: tmp_dir} do
      start_robine(fake_receiver(tmp_dir, ":"))
      assert_eventually(fn -> match?(%{state: :available}, AirPlay.status()) end)

      {elapsed_us, :ok} = :timer.tc(fn -> AirPlay.suspend() end)
      assert elapsed_us < 1_500_000
      assert %{state: :suspended} = AirPlay.status()

      # Resuming starts a fresh receiver.
      assert :ok = AirPlay.resume()

      assert_eventually(fn ->
        match?(%{state: :available, session: "playing"}, AirPlay.status())
      end)
    end
  end

  defp start_robine(executable) do
    :ok = Supervisor.terminate_child(RobineWake.Supervisor, @airplay_child)
    Application.put_env(:robine_wake, :airplay_receiver, :robine)
    Application.put_env(:robine_wake, :airplay_robine_executable, executable)
    Application.put_env(:robine_wake, :host_network_state, :available)
    {:ok, _pid} = Supervisor.restart_child(RobineWake.Supervisor, @airplay_child)
  end

  # Speaks the robine-airplayd line protocol; `on_suspend` is the shell
  # command run when asked to suspend.
  defp fake_receiver(dir, on_suspend) do
    path = Path.join(dir, "robine-airplayd")

    File.write!(path, """
    #!/bin/sh
    echo 'receiver ready (log line)'
    echo '{"event":"ready","name":"Robine Wake Bedroom"}'
    echo '{"event":"session","state":"playing"}'
    echo '{"event":"volume","db":-12.5}'
    while read -r line; do
      echo "$line" >> "#{dir}/commands"
      case "$line" in
        *suspend*) #{on_suspend} ;;
        *resume*) echo '{"event":"resumed"}' ;;
      esac
    done
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp assert_eventually(assertion, attempts \\ 50)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      assert true
    else
      Process.sleep(10)
      assert_eventually(assertion, attempts - 1)
    end
  end

  defp assert_eventually(_assertion, 0), do: flunk("condition was not met before timeout")
end
