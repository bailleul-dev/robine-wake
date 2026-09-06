# 50-002 — HTTP Model Context Protocol

## Purpose

Allow an AI client on the configured trusted local network to
inspect and control Robine Wake through the Model Context Protocol (MCP), while
preserving the alarm domain's validation, safety ceilings, privacy rules, and
optimistic concurrency.

## Protocol profile

- Endpoint: `POST /mcp` on the existing Robine Wake HTTP listener.
- Transport: MCP Streamable HTTP with one JSON-RPC 2.0 message per request.
- Protocol versions: `2025-06-18` and compatibility version `2025-03-26`.
- Responses: synchronous `application/json`; server-sent events are not used.
- Sessions: stateless. The server does not issue `Mcp-Session-Id`.
- `GET /mcp`: `405 Method Not Allowed`, because unsolicited server messages and
  resumable streams are not supported.
- Notifications: accepted with `202 Accepted` and an empty body.
- Capabilities: tools only, with a stable list (`listChanged: false`).

Clients send `Content-Type: application/json` and
`Accept: application/json, text/event-stream`. After initialization they send
the negotiated version in `MCP-Protocol-Version`. If that header is absent, the
compatibility behavior of MCP `2025-03-26` is assumed. Unsupported header values
produce HTTP 400 and JSON-RPC `-32602` with the supported versions.

## Security boundary

The endpoint is passwordless like the local interface and remains rate-limited
per source address. MCP requests are exempt from browser CSRF tokens because
non-browser MCP clients do
not participate in the UI token flow; instead, every supplied `Origin` must
match the request origin or a value explicitly configured in
`mcp_allowed_origins`. Missing `Origin` is accepted for native MCP clients.
Requests are limited per source address; the default is 120 per
minute and can be changed with `mcp_max_requests_per_minute`.

The listener remains bound only to `web_ip`. TLS is outside the device-local
MVP, so MCP access must not be routed over an untrusted network. No tool returns
credentials, tokens, camera pixels, or raw diagnostic files.

## Tools

| Tool | Effect |
|---|---|
| `get_state` | Read health, alarms, recent sessions, and active session. |
| `list_alarms` | Read alarms with their next five occurrences. |
| `list_sounds` | Read validated on-device sounds. |
| `preview_alarm` | Validate and preview without persistence. |
| `create_alarm` | Validate and persist an alarm. |
| `update_alarm` | Update using the current resource revision. |
| `delete_alarm` | Delete using the current resource revision. |
| `trigger_alarm` | Start an existing alarm immediately. |
| `snooze_session` | Snooze the active wake session. |
| `dismiss_session` | Dismiss the active wake session with reason `mcp` when smartphone dismissal is enabled. |

Tool definitions include JSON Schema inputs and MCP safety annotations. Domain
validation failures are successful JSON-RPC responses whose tool result has
`isError: true`; malformed JSON-RPC, invalid arguments, and unknown tools use
JSON-RPC errors.
Every successful tool response includes both human-readable text content and
`structuredContent`.

## Camera-free state and tactile configuration

`get_state` must omit presence/confidence and camera/detector capabilities.
Alarm schemas accept the vibration profile defined in `20-001`, disabled when
omitted by old clients. Retired presence policies are rejected on new writes;
no MCP command may activate capture or infer dismissal from presence. Tactile
hardware access remains inside the domain service and its calibration limits.

## Requirements

- `MCP-001` — The server shall negotiate a supported MCP version and advertise
  only capabilities it implements.
- `MCP-002` — MCP traffic shall require provisioned administrator credentials.
- `MCP-003` — A supplied cross-origin `Origin` shall be rejected before tool
  dispatch.
- `MCP-004` — Alarm mutation tools shall call domain services and preserve
  revision-conflict behavior.
- `MCP-005` — Tool output shall exclude secrets and camera pixels.
- `MCP-006` — A domain execution failure shall be returned as `isError: true`
  without converting a valid tool call into a JSON-RPC transport failure.
- `MCP-007` — The implementation shall run on both `host` and the Nerves target
  without a target-specific MCP dependency.
- `MCP-008` — MCP requests shall be rate-limited per source
  address.

## Acceptance criteria

Automated tests cover initialization, discovery, notifications, passwordless
access, Origin rejection, content negotiation, rate limiting, unsupported protocol
versions, tool errors, revision conflicts, and create/update/delete behavior.
The normal host verification gate compiles the implementation with warnings as
errors.
