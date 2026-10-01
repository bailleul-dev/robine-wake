defmodule RobineWakeDevWeb.RoomRedirect do
  @moduledoc "Sends `/room` to the static WebGL demo room."
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string

    conn
    |> put_resp_header("location", "/room/index.html" <> query)
    |> send_resp(302, "")
    |> halt()
  end
end
