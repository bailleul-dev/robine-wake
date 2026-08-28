defmodule RobineWakeWeb.MCPRouterTest do
  use RobineWake.DomainCase

  import Plug.Conn
  import Plug.Test

  alias RobineWake.MCP.RateLimiter

  @opts RobineWakeWeb.Router.init([])

  setup do
    :ok = RateLimiter.clear()
  end

  test "serves MCP over local Streamable HTTP" do
    response =
      post_mcp(%{
        "jsonrpc" => "2.0",
        "id" => "init-1",
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-06-18",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "test", "version" => "1"}
        }
      })

    assert response.status == 200
    assert ["application/json; charset=utf-8"] = get_resp_header(response, "content-type")

    assert %{
             "id" => "init-1",
             "result" => %{"protocolVersion" => "2025-06-18"}
           } = Jason.decode!(response.resp_body)
  end

  test "requires neither authentication nor a browser CSRF token" do
    body = rpc("tools/list", %{})

    unauthenticated =
      conn(:post, "/mcp", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> RobineWakeWeb.Router.call(@opts)

    assert unauthenticated.status == 200

    assert %{"result" => %{"tools" => unauthenticated_tools}} =
             Jason.decode!(unauthenticated.resp_body)

    assert length(unauthenticated_tools) == 10

    authenticated = post_mcp(body)
    assert authenticated.status == 200
    assert %{"result" => %{"tools" => tools}} = Jason.decode!(authenticated.resp_body)
    assert length(tools) == 10
  end

  test "validates Origin to prevent DNS rebinding" do
    rejected = post_mcp(rpc("ping", %{}), origin: "https://attacker.example")
    assert rejected.status == 403
    assert Jason.decode!(rejected.resp_body)["error"]["message"] == "Origin not allowed"

    accepted = post_mcp(rpc("ping", %{}), origin: "http://www.example.com")
    assert accepted.status == 200
  end

  test "enforces Streamable HTTP accept types and rejects standalone GET streams" do
    not_acceptable =
      conn(:post, "/mcp", Jason.encode!(rpc("ping", %{})))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> auth()
      |> RobineWakeWeb.Router.call(@opts)

    assert not_acceptable.status == 406

    get_response =
      conn(:get, "/mcp")
      |> put_req_header("accept", "text/event-stream")
      |> auth()
      |> RobineWakeWeb.Router.call(@opts)

    assert get_response.status == 405
    assert get_resp_header(get_response, "allow") == ["POST"]
  end

  test "requires a JSON request content type" do
    response =
      conn(:post, "/mcp", Jason.encode!(rpc("ping", %{})))
      |> put_req_header("content-type", "text/plain")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> auth()
      |> RobineWakeWeb.Router.call(@opts)

    assert response.status == 415
  end

  test "returns 202 with an empty body for notifications" do
    response = post_mcp(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    assert response.status == 202
    assert response.resp_body == ""
  end

  test "rate limits authenticated MCP requests per peer" do
    original_limit = Application.fetch_env!(:robine_wake, :mcp_max_requests_per_minute)
    Application.put_env(:robine_wake, :mcp_max_requests_per_minute, 2)

    on_exit(fn ->
      Application.put_env(:robine_wake, :mcp_max_requests_per_minute, original_limit)
      RateLimiter.clear()
    end)

    assert post_mcp(rpc("ping", %{})).status == 200
    assert post_mcp(rpc("ping", %{})).status == 200

    limited = post_mcp(rpc("ping", %{}))
    assert limited.status == 429
    assert get_resp_header(limited, "retry-after") == ["60"]
  end

  defp rpc(method, params) do
    %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}
  end

  defp post_mcp(body, opts \\ []) do
    conn =
      conn(:post, "/mcp", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> auth()

    conn = if origin = opts[:origin], do: put_req_header(conn, "origin", origin), else: conn
    RobineWakeWeb.Router.call(conn, @opts)
  end

  defp auth(conn) do
    put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth("admin", "robine"))
  end
end
