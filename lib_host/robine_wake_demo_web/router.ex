defmodule RobineWakeDemoWeb.Router do
  @moduledoc """
  Single public entry point of the demo deployment (`ROBINE_DEMO=1`).

  - `/demo`: the product web app and the 3D room side by side;
  - `/room/*`: the WebGL room (`ROBINE_ROOM_DIR`);
  - `/emulator/*`: the emulated hardware (state stream, sounds, remote,
    clock, reset);
  - everything else goes to `RobineWakeWeb.Router`, the real product app
    and API, unchanged.

  When `ROBINE_DEMO_ACCESS_CODE` is set, every route sits behind an access
  code kept in a signed cookie.
  """

  use Plug.Router

  alias RobineWake.Audio.MeditationDSP
  alias RobineWake.SoundLibrary
  alias RobineWakeDev.{Demo, Hardware, VirtualRemote}

  @cookie "robine_demo_access"
  @product_opts RobineWakeWeb.Router.init([])
  @keepalive_ms 15_000
  @wav_block_frames 4_096
  @wav_lead_ms 1_500

  @external_resource Path.join(__DIR__, "demo.html")
  @demo_page File.read!(Path.join(__DIR__, "demo.html"))

  plug :gate

  plug Plug.Static,
    at: "/room",
    from: {__MODULE__, :room_dir, []},
    only: ~w(index.html room.js decor.js remote.js remote_sprites.js audio.js live.js assets),
    cache_control_for_etags: "public, max-age=0, must-revalidate"

  plug :match
  plug :dispatch

  @doc false
  def room_dir,
    do:
      Application.get_env(
        :robine_wake,
        :demo_room_dir,
        "hardware/robine_enclosure/soundbar/viewer"
      )

  # --- Access gate ------------------------------------------------------------

  get "/access" do
    html(conn, 200, access_page(nil))
  end

  post "/access" do
    {:ok, body, conn} = read_body(conn, length: 1_000)
    code = body |> URI.decode_query() |> Map.get("code", "")

    if valid_code?(code) do
      conn
      |> put_resp_cookie(@cookie, access_token(),
        http_only: true,
        same_site: "Lax",
        max_age: 30 * 86_400
      )
      |> redirect("/demo")
    else
      html(conn, 401, access_page("Code incorrect."))
    end
  end

  # --- Pages --------------------------------------------------------------------

  get "/demo" do
    html(conn, 200, @demo_page)
  end

  get "/room" do
    redirect(conn, "/room/index.html?live=1")
  end

  # A top-level visit to "/" lands on the side-by-side page; the app itself
  # opens in the page's iframe, or alone with "/?app".
  get "/" do
    conn = fetch_query_params(conn)

    if get_req_header(conn, "sec-fetch-dest") == ["document"] and
         not Map.has_key?(conn.query_params, "app"),
       do: redirect(conn, "/demo"),
       else: RobineWakeWeb.Router.call(conn, @product_opts)
  end

  # --- Emulated hardware -----------------------------------------------------

  get "/emulator/state" do
    json(conn, 200, Hardware.snapshot())
  end

  get "/emulator/stream" do
    :ok = Hardware.subscribe()

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache, no-transform")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    case chunk(conn, sse("snapshot", Hardware.snapshot())) do
      {:ok, conn} -> stream_hardware(conn)
      {:error, _reason} -> conn
    end
  end

  get "/emulator/audio/sounds/:id" do
    with {:ok, path} <- SoundLibrary.path(id),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type(MIME.from_path(path), nil)
      |> put_resp_header("cache-control", "public, max-age=86400")
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  # The breathing soundscape rendered live by the server's DSP, the fallback
  # of the ALSA driver when the recording is missing.
  get "/emulator/audio/breathing.wav" do
    conn =
      conn
      |> put_resp_content_type("audio/wav", nil)
      |> put_resp_header("cache-control", "no-store")
      |> send_chunked(200)

    case chunk(conn, wav_header()) do
      {:ok, conn} ->
        stream_wav(conn, MeditationDSP.initial_state(), System.monotonic_time(:millisecond), 0)

      {:error, _reason} ->
        conn
    end
  end

  post "/emulator/remote/press" do
    json(conn, 200, %{feedback: VirtualRemote.press()})
  end

  post "/emulator/clock" do
    {:ok, body, conn} = read_body(conn, length: 1_000)

    result =
      case Jason.decode(body) do
        {:ok, %{"speed" => speed}} -> Demo.set_speed(speed)
        {:ok, %{"jump" => "alarm"}} -> Demo.jump_before_alarm()
        _ -> {:error, :invalid_body}
      end

    case result do
      :ok -> json(conn, 200, Hardware.snapshot().clock)
      {:error, reason} -> json(conn, 422, %{error: reason})
    end
  end

  post "/emulator/reset" do
    :ok = Demo.reset()
    json(conn, 200, Hardware.snapshot())
  end

  # --- Product app ---------------------------------------------------------------

  # The assistant endpoint stays off a shared public instance.
  match "/mcp" do
    send_resp(conn, 404, "")
  end

  match _ do
    RobineWakeWeb.Router.call(conn, @product_opts)
  end

  # --- Gate ----------------------------------------------------------------------

  defp gate(%Plug.Conn{path_info: ["access"]} = conn, _opts), do: conn

  defp gate(conn, _opts) do
    conn = fetch_cookies(conn)

    cond do
      access_code() == nil ->
        conn

      Plug.Crypto.secure_compare(conn.cookies[@cookie] || "", access_token()) ->
        conn

      get_req_header(conn, "accept") |> Enum.any?(&String.contains?(&1, "text/html")) ->
        conn |> redirect("/access") |> halt()

      true ->
        conn |> json(401, %{error: "demo_access_required"}) |> halt()
    end
  end

  defp access_code do
    case Application.get_env(:robine_wake, :demo_access_code) do
      code when is_binary(code) and code != "" -> code
      _ -> nil
    end
  end

  defp valid_code?(code),
    do: access_code() != nil and Plug.Crypto.secure_compare(code, access_code())

  # The cookie holds an HMAC of the code: changing the code signs everyone out.
  defp access_token do
    secret = Application.fetch_env!(:robine_wake, :demo_secret)

    :crypto.mac(:hmac, :sha256, secret, "demo-access:" <> (access_code() || ""))
    |> Base.url_encode64(padding: false)
  end

  defp access_page(error) do
    message = if error, do: ~s(<p class="error">#{error}</p>), else: ""

    """
    <!doctype html>
    <html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Robine Wake Demo</title>
    <style>
      :root{color-scheme:dark;font-family:system-ui,sans-serif}
      body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0d1320;color:#e8edf6}
      form{display:grid;gap:12px;width:min(320px,calc(100vw - 32px))}
      h1{font-size:20px;margin:0 0 4px}
      input,button{font:inherit;padding:10px 12px;border-radius:8px;border:1px solid #33405a;background:#141c2c;color:inherit}
      button{background:#2f4f8f;border-color:#2f4f8f;cursor:pointer}
      .error{color:#ff9b8a;margin:0}
    </style></head>
    <body><form method="post" action="/access">
      <h1>Robine Wake · démo</h1>
      <label for="code">Code d'accès</label>
      <input id="code" name="code" type="password" autocomplete="current-password" autofocus required>
      #{message}
      <button type="submit">Entrer</button>
    </form></body></html>
    """
  end

  # --- Streams -------------------------------------------------------------------

  defp stream_hardware(conn) do
    receive do
      {:hardware, event} ->
        case chunk(conn, sse("hardware", event)) do
          {:ok, conn} -> stream_hardware(conn)
          {:error, _reason} -> conn
        end
    after
      @keepalive_ms ->
        case chunk(conn, ": keepalive\n\n") do
          {:ok, conn} -> stream_hardware(conn)
          {:error, _reason} -> conn
        end
    end
  end

  defp sse(event, data), do: ["event: ", event, "\ndata: ", Jason.encode!(data), "\n\n"]

  # Renders at real time, keeping the browser @wav_lead_ms ahead, and stops
  # when the visitor leaves or the breathing session ends.
  defp stream_wav(conn, dsp, started_ms, sent_frames) do
    rate = MeditationDSP.sample_rate()
    ahead_ms = div(sent_frames * 1_000, rate) - (System.monotonic_time(:millisecond) - started_ms)

    cond do
      Hardware.snapshot().audio.sound_id != Hardware.breathing_sound_id() ->
        conn

      ahead_ms > @wav_lead_ms ->
        Process.sleep(ahead_ms - @wav_lead_ms)
        stream_wav(conn, dsp, started_ms, sent_frames)

      true ->
        {pcm, dsp} = MeditationDSP.render(dsp, @wav_block_frames)

        case chunk(conn, pcm) do
          {:ok, conn} -> stream_wav(conn, dsp, started_ms, sent_frames + @wav_block_frames)
          {:error, _reason} -> conn
        end
    end
  end

  # 16-bit stereo PCM with an open-ended length, as streaming players expect.
  defp wav_header do
    rate = MeditationDSP.sample_rate()
    size = 0xFFFF_FFFF

    <<"RIFF", size - 8::little-32, "WAVE", "fmt ", 16::little-32, 1::little-16, 2::little-16,
      rate::little-32, rate * 4::little-32, 4::little-16, 16::little-16, "data",
      size - 44::little-32>>
  end

  # --- Helpers -------------------------------------------------------------------

  defp html(conn, status, body) do
    conn |> put_resp_content_type("text/html") |> send_resp(status, body)
  end

  defp json(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end

  defp redirect(conn, path) do
    conn |> put_resp_header("location", path) |> send_resp(302, "")
  end
end
