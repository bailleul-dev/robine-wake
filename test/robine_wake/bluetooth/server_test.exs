defmodule RobineWake.Bluetooth.ServerTest do
  use RobineWake.DomainCase

  alias RobineWake.{Bluetooth.Server, Settings}

  test "accepts a fragmented v1 command and returns the application state" do
    :ok = Server.receive_chunk(~s({"v":1,"id":"one","op":"state.))
    :ok = Server.receive_chunk(~s(get","body":{}}\n))

    assert %{
             "v" => 1,
             "id" => "one",
             "status" => "ok",
             "body" => %{
               "alarms" => [],
               "sounds" => sounds,
               "device" => %{"clock_trusted" => clock_trusted},
               "smartphone_dismiss" => %{"enabled" => true, "locked" => false}
             }
           } = response()

    assert is_boolean(clock_trusted)
    assert sounds != []
  end

  test "creates, updates, and deletes an alarm with optimistic revisions" do
    create =
      request("create", "alarm.create", %{
        label: "Bluetooth",
        local_time: "07:15",
        days_of_week: [1, 2, 3, 4, 5]
      })

    send_request(create)

    assert %{"status" => "ok", "body" => %{"id" => id, "revision" => 1}} = response()

    update =
      request("update", "alarm.update", %{
        alarm_id: id,
        alarm: %{label: "BLE updated", revision: 1}
      })

    send_request(update)

    assert %{
             "status" => "ok",
             "body" => %{"label" => "BLE updated", "revision" => 2}
           } = response()

    send_request(request("delete", "alarm.delete", %{alarm_id: id, revision: 2}))
    assert %{"status" => "ok", "body" => %{"deleted" => ^id}} = response()
    assert Settings.list_alarms() == []
  end

  test "triggers the strong alarm phase directly" do
    {:ok, alarm} =
      Settings.create_alarm(%{
        local_time: "07:30",
        days_of_week: [1],
        strong_sound_id: "wake_up_call",
        volume_profile: %{start: 10, ceiling: 30, ramp_seconds: 300}
      })

    send_request(request("strong", "alarm.trigger_strong", %{alarm_id: alarm.id}))

    assert %{
             "status" => "ok",
             "body" => %{"state" => "starting", "phase" => "strong"}
           } = response()

    assert %{audio_phase: :strong, current_gain: 30} = RobineWake.WakeSession.active()
  end

  test "deduplicates a mutation retried with the same request id" do
    create =
      request("retry-on-fallback", "alarm.create", %{
        label: "One command",
        local_time: "07:30",
        days_of_week: [1]
      })

    send_request(create)
    first = response()
    send_request(create)
    second = response()

    assert first == second
    assert length(Settings.list_alarms()) == 1

    changed = put_in(create, ["body", :label], "Different command")
    send_request(changed)

    assert %{
             "status" => "error",
             "error" => %{"code" => "request_id_reused"}
           } = response()
  end

  test "reports malformed envelopes and unsupported operations with stable error codes" do
    :ok = Server.receive_chunk("not json\n")
    assert %{"status" => "error", "error" => %{"code" => "invalid_json"}} = response()

    send_request(request("bad", "device.explode", %{}))

    assert %{
             "id" => "bad",
             "status" => "error",
             "error" => %{"code" => "unsupported_operation"}
           } = response()
  end

  test "pages large responses with ordered metadata and a verifiable CRC32" do
    send_request(request("pages", "state.get", %{}))

    pages = read_pages([])
    [{sequence, 0, page_count, total_bytes, crc32, _payload} | _] = pages

    assert length(pages) == page_count
    assert Enum.map(pages, &elem(&1, 1)) == Enum.to_list(0..(page_count - 1))
    assert Enum.all?(pages, fn page -> byte_size(elem(page, 5)) <= 460 end)
    assert Enum.all?(pages, fn page -> elem(page, 0) == sequence end)

    assembled = pages |> Enum.map(&elem(&1, 5)) |> IO.iodata_to_binary()
    assert byte_size(assembled) == total_bytes
    assert :erlang.crc32(assembled) == crc32
    assert assembled == Server.response() |> String.trim_trailing()
  end

  test "advertises the contract capabilities" do
    send_request(request("caps", "capabilities.get", %{}))

    assert %{
             "status" => "ok",
             "body" => %{
               "contract_version" => 1,
               "response_transport" => "paged-read-v1",
               "security" => "remote-button-hmac-sha256-counter",
               "operations" => operations
             }
           } = response()

    assert "state.get" in operations
    assert "alarm.update" in operations
    assert "session.get" in operations
    assert "settings.smartphone_dismiss.set" in operations
    refute "hue.pair" in operations
    assert "breathing.start" in operations
    assert "breathing.volume" in operations
    assert "breathing.stop" in operations
    assert "remote_button.pairing.begin" in operations
    assert "remote_button.dismiss" in operations
  end

  test "updates the smartphone dismissal preference" do
    send_request(request("dismiss-setting", "settings.smartphone_dismiss.set", %{enabled: false}))

    assert %{
             "status" => "ok",
             "body" => %{"enabled" => false, "locked" => false}
           } = response()

    refute Settings.smartphone_dismiss_enabled()
  end

  test "returns the active wake session through the lightweight session endpoint" do
    send_request(request("session", "session.get", %{}))

    assert %{
             "id" => "session",
             "status" => "ok",
             "body" => %{"active_session" => nil}
           } = response()
  end

  defp request(id, operation, body),
    do: %{"v" => 1, "id" => id, "op" => operation, "body" => body}

  defp send_request(request), do: Server.receive_chunk(Jason.encode!(request) <> "\n")

  defp read_pages(acc) do
    <<"RW", 1, flags, sequence::unsigned-big-32, index::unsigned-big-16, count::unsigned-big-16,
      total::unsigned-big-32, crc32::unsigned-big-32, payload::binary>> =
      Server.next_response_chunk()

    page = {sequence, index, count, total, crc32, payload}

    if Bitwise.band(flags, 0x01) == 0,
      do: read_pages([page | acc]),
      else: Enum.reverse([page | acc])
  end

  defp response, do: Server.response() |> Jason.decode!()
end
