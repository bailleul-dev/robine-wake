defmodule RobineWake.LoRaTest do
  use RobineWake.DomainCase

  alias RobineWake.{LoRa.Protocol, LoRa.Server, RemoteButton, Settings}

  test "pairs over LoRa and returns a compact secret response" do
    assert {:ok, _status} = RemoteButton.begin_pairing(30)

    request =
      Jason.encode!(%{
        v: 1,
        id: "pair-1",
        op: "pair",
        body: %{button_id: "bedside", name: "Bouton chevet"}
      })

    assert {:ok, response} = Protocol.handle(request)
    assert byte_size(response) <= 255

    assert %{
             "v" => 1,
             "id" => "pair-1",
             "status" => "ok",
             "body" => %{"secret_hex" => secret, "next_counter" => 1}
           } = Jason.decode!(response)

    assert byte_size(secret) == 64
    assert [%{"id" => "bedside", "last_counter" => 0}] = Settings.remote_buttons()
  end

  test "authenticates a LoRa dismissal with the existing anti-replay counter" do
    assert {:ok, _status} = RemoteButton.begin_pairing(30)
    assert {:ok, %{secret_hex: secret_hex}} = RemoteButton.pair("bedside", "Bouton chevet")
    {:ok, secret} = Base.decode16(secret_hex, case: :mixed)

    assert {:ok, alarm} =
             Settings.create_alarm(%{local_time: "07:00", days_of_week: [1]})

    assert {:ok, _pid} = RobineWake.Scheduler.trigger_now(alarm.id)

    request =
      Jason.encode!(%{
        v: 1,
        id: "dismiss-1",
        op: "dismiss",
        body: %{
          button_id: "bedside",
          counter: 1,
          mac: RemoteButton.mac(secret, "bedside", 1)
        }
      })

    assert {:ok, response} = Protocol.handle(request)
    assert get_in(Jason.decode!(response), ["body", "accepted"])
    refute RobineWake.WakeSession.active()
  end

  test "retransmits the exact cached pairing acknowledgement" do
    assert {:ok, _status} = RemoteButton.begin_pairing(30)

    request =
      Jason.encode!(%{
        v: 1,
        id: "pair-retry",
        op: "pair",
        body: %{button_id: "bedside", name: "Bouton chevet"}
      })

    pid =
      start_supervised!(
        {Server,
         driver: RobineWake.LoRa.TestDriver,
         driver_options: [owner: self(), packets: [request, request]],
         name: nil}
      )

    assert_receive {:lora_transmit, first_response}, 1_000
    assert_receive {:lora_transmit, second_response}, 1_000
    assert first_response == second_response
    assert %{state: :listening, packets_received: 2} = Server.status(pid)
    assert [%{"id" => "bedside"}] = Settings.remote_buttons()
  end
end
