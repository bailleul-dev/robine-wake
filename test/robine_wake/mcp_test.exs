defmodule RobineWake.MCPTest do
  use RobineWake.DomainCase

  alias RobineWake.Settings

  test "initializes with the latest supported protocol and advertises tools" do
    assert {:response, 200, response} =
             RobineWake.MCP.handle(%{
               "jsonrpc" => "2.0",
               "id" => 1,
               "method" => "initialize",
               "params" => %{
                 "protocolVersion" => "2025-06-18",
                 "capabilities" => %{},
                 "clientInfo" => %{"name" => "test", "version" => "1"}
               }
             })

    assert response["result"]["protocolVersion"] == "2025-06-18"
    assert response["result"]["capabilities"] == %{"tools" => %{"listChanged" => false}}

    assert {:response, 200, listed} = request("tools/list", %{}, "2025-06-18")

    names = Enum.map(listed["result"]["tools"], & &1["name"])
    assert "get_state" in names
    assert "create_alarm" in names
    assert "dismiss_session" in names
  end

  test "creates, updates, and deletes a revisioned alarm through tools" do
    assert {:response, 200, created} =
             request("tools/call", %{
               "name" => "create_alarm",
               "arguments" => %{
                 "label" => "MCP alarm",
                 "local_time" => "08:15",
                 "days_of_week" => [1, 2, 3, 4, 5],
                 "sound_id" => "jungle_sunrise",
                 "strong_sound_id" => "wake_up_call"
               }
             })

    alarm = created["result"]["structuredContent"]["alarm"]
    assert alarm["label"] == "MCP alarm"
    assert alarm["revision"] == 1

    assert {:response, 200, updated} =
             request("tools/call", %{
               "name" => "update_alarm",
               "arguments" => %{"id" => alarm["id"], "revision" => 1, "label" => "Updated"}
             })

    assert updated["result"]["structuredContent"]["alarm"]["revision"] == 2

    assert {:response, 200, stale} =
             request("tools/call", %{
               "name" => "delete_alarm",
               "arguments" => %{"id" => alarm["id"], "revision" => 1}
             })

    assert stale["result"]["isError"]
    assert stale["result"]["structuredContent"]["error"]["code"] == "revision_conflict"

    assert {:response, 200, deleted} =
             request("tools/call", %{
               "name" => "delete_alarm",
               "arguments" => %{"id" => alarm["id"], "revision" => 2}
             })

    assert deleted["result"]["structuredContent"]["deleted"]
    assert Settings.list_alarms() == []
  end

  test "returns protocol and tool errors in the correct JSON-RPC layer" do
    assert {:response, 400, unsupported} = request("ping", %{}, "2099-01-01")
    assert unsupported["error"]["code"] == -32_602
    assert unsupported["error"]["data"]["supported"] == ["2025-06-18", "2025-03-26"]

    assert {:response, 200, unknown} =
             request("tools/call", %{"name" => "not_a_tool", "arguments" => %{}})

    assert unknown["error"]["code"] == -32_602
    assert unknown["error"]["message"] == "Unknown tool: not_a_tool"

    assert {:response, 200, invalid} =
             request("tools/call", %{
               "name" => "create_alarm",
               "arguments" => %{"local_time" => "08:00", "unexpected" => true}
             })

    assert invalid["error"]["code"] == -32_602
    assert invalid["error"]["message"] =~ "unknown properties"
  end

  test "accepts notifications without a response body" do
    assert {:accepted, 202} =
             RobineWake.MCP.handle(%{
               "jsonrpc" => "2.0",
               "method" => "notifications/initialized"
             })
  end

  defp request(method, params, protocol \\ "2025-06-18") do
    RobineWake.MCP.handle(
      %{"jsonrpc" => "2.0", "id" => 7, "method" => method, "params" => params},
      protocol
    )
  end
end
