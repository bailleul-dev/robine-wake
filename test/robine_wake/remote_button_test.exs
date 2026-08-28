defmodule RobineWake.RemoteButtonTest do
  use RobineWake.DomainCase

  alias RobineWake.{Clock, RemoteButton, Settings}

  test "uses the firmware-compatible canonical HMAC message" do
    secret = :binary.copy(<<0x42>>, 32)

    assert RemoteButton.mac(secret, "button-001122334455", 7) ==
             "5afbdaf88cbe8167dd711c4492008bb956932b7351f26b60db69237639d9f995"

    assert RemoteButton.signed_message("button-001122334455", 7) ==
             Enum.join(["rw-remote-v1", "button-001122334455", "7", "dismiss"], <<0>>)
  end

  test "pairs only inside a short-lived explicit window without exposing the secret in status" do
    assert {:error, :pairing_window_closed} = RemoteButton.pair("bedside", "Chevet")

    assert {:ok, %{pairing: %{active: true, expires_at: expires_at}}} =
             RemoteButton.begin_pairing(30)

    assert is_binary(expires_at)

    assert {:ok,
            %{
              button_id: "bedside",
              algorithm: "hmac-sha256",
              protocol: "rw-remote-v1",
              secret_hex: secret_hex,
              next_counter: 1
            }} = RemoteButton.pair("bedside", "Bouton chevet")

    assert byte_size(secret_hex) == 64

    assert %{
             state: :available,
             pairing: %{active: false},
             buttons: [%{"id" => "bedside", "name" => "Bouton chevet", "last_counter" => 0}]
           } = RemoteButton.status()

    refute Jason.encode!(RemoteButton.status()) =~ secret_hex
    refute Jason.encode!(Settings.export_configuration()) =~ secret_hex
  end

  test "rejects pairing after the window expires" do
    assert {:ok, _status} = RemoteButton.begin_pairing(30)
    Clock.Manual.advance(30_000)

    assert {:error, :pairing_window_closed} = RemoteButton.pair("late", "Trop tard")
  end

  test "authenticates dismissal, persists the counter, and acknowledges an identical retry" do
    {secret, alarm} = paired_button_with_alarm()
    assert {:ok, _pid} = RobineWake.Scheduler.trigger_now(alarm.id)
    assert RobineWake.WakeSession.active()

    signature = RemoteButton.mac(secret, "bedside", 1)
    command = %{"button_id" => "bedside", "counter" => 1, "mac" => signature}

    assert {:ok, %{accepted: true, duplicate: false, counter: 1}} =
             RemoteButton.dismiss(command)

    refute RobineWake.WakeSession.active()

    assert {:ok, %{accepted: true, duplicate: true, counter: 1}} =
             RemoteButton.dismiss(command)

    assert [%{"last_counter" => 1, "last_seen_at" => last_seen_at}] =
             Settings.remote_buttons()

    assert is_binary(last_seen_at)
  end

  test "rejects forged, stale, malformed, and removed button commands" do
    {secret, _alarm} = paired_button_with_alarm()

    assert {:error, :invalid_remote_button_signature} =
             RemoteButton.dismiss(%{
               "button_id" => "bedside",
               "counter" => 1,
               "mac" => String.duplicate("0", 64)
             })

    assert {:ok, %{duplicate: false}} =
             RemoteButton.dismiss(%{
               "button_id" => "bedside",
               "counter" => 2,
               "mac" => RemoteButton.mac(secret, "bedside", 2)
             })

    assert {:error, :remote_button_replay} =
             RemoteButton.dismiss(%{
               "button_id" => "bedside",
               "counter" => 1,
               "mac" => RemoteButton.mac(secret, "bedside", 1)
             })

    assert {:error, :invalid_remote_button_counter} =
             RemoteButton.dismiss(%{
               "button_id" => "bedside",
               "counter" => 0,
               "mac" => RemoteButton.mac(secret, "bedside", 0)
             })

    assert :ok = RemoteButton.remove("bedside")

    assert {:error, :remote_button_not_paired} =
             RemoteButton.dismiss(%{
               "button_id" => "bedside",
               "counter" => 3,
               "mac" => RemoteButton.mac(secret, "bedside", 3)
             })
  end

  defp paired_button_with_alarm do
    assert {:ok, _status} = RemoteButton.begin_pairing(30)
    assert {:ok, %{secret_hex: secret_hex}} = RemoteButton.pair("bedside", "Bouton chevet")
    {:ok, secret} = Base.decode16(secret_hex, case: :mixed)

    assert {:ok, alarm} =
             Settings.create_alarm(%{local_time: "07:00", days_of_week: [1]})

    {secret, alarm}
  end
end
