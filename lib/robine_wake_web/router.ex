defmodule RobineWakeWeb.Router do
  use Plug.Router

  alias RobineWake.{
    Alarm,
    Auth,
    Camera,
    ClockQuality,
    Diagnostics,
    EventLog,
    EventStream,
    Health,
    Hue,
    RemoteButton,
    Scheduler,
    Settings,
    SoundLibrary,
    WakeSession
  }

  alias RobineWake.Bluetooth.Command, as: BluetoothCommand
  alias RobineWake.LoRa.Server, as: LoRaServer
  alias RobineWake.MCP.RateLimiter

  plug Plug.Logger

  plug Plug.Static,
    at: "/",
    from: {:robine_wake, "priv/web"},
    cache_control_for_etags: "public, max-age=0, must-revalidate"

  plug Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason
  plug :match
  plug :validate_mcp_origin
  plug :rate_limit_mcp
  plug :protect_csrf
  plug :dispatch

  get "/health" do
    json(conn, 200, Health.snapshot())
  end

  post "/api/v1/command" do
    json(conn, 200, BluetoothCommand.execute(conn.body_params))
  end

  get "/api/v1/events" do
    last_event_id = conn |> get_req_header("last-event-id") |> List.first()
    {:ok, sequence, replay} = EventStream.subscribe(last_event_id)

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache, no-transform")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)

    try do
      with {:ok, conn} <- chunk(conn, sse_event(%{id: sequence, event: "ready", at: nil})),
           {:ok, conn} <- chunk_replay(conn, replay) do
        stream_events(conn)
      else
        {:error, _reason} -> conn
      end
    after
      EventStream.unsubscribe()
    end
  end

  get "/mcp" do
    conn
    |> put_resp_header("allow", "POST")
    |> send_resp(405, "")
  end

  post "/mcp" do
    cond do
      not mcp_json_request?(conn) ->
        send_resp(conn, 415, "MCP requests must use application/json")

      not mcp_accepts_json_and_sse?(conn) ->
        conn
        |> put_resp_header("accept", "application/json, text/event-stream")
        |> send_resp(406, "MCP clients must accept application/json and text/event-stream")

      true ->
        protocol_version = conn |> get_req_header("mcp-protocol-version") |> List.first()

        case RobineWake.MCP.handle(conn.body_params, protocol_version) do
          {:accepted, status} -> send_resp(conn, status, "")
          {:response, status, payload} -> json(conn, status, payload)
        end
    end
  end

  get "/setup" do
    redirect(conn, to: "/")
  end

  post "/api/setup" do
    json(conn, 410, %{state: "local_access", next: "/"})
  end

  get "/" do
    web_index(conn)
  end

  get "/matin" do
    web_index(conn)
  end

  get "/soir" do
    web_index(conn)
  end

  get "/alarmes" do
    web_index(conn)
  end

  get "/reveil" do
    web_index(conn)
  end

  get "/legacy" do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, page())
  end

  get "/beta" do
    redirect(conn, to: "/")
  end

  get "/api/state" do
    json(conn, 200, %{
      health: Health.snapshot(),
      alarms: Enum.map(Settings.list_alarms(), &alarm_json/1),
      sessions: Settings.recent_sessions(),
      active_session: WakeSession.active(),
      hue: Hue.status(),
      hue_targets: Hue.targets(),
      remote_button: RemoteButton.status(),
      lora: LoRaServer.safe_status()
    })
  end

  post "/api/breathing/start" do
    with target_id when is_binary(target_id) <- conn.body_params["target_id"],
         duration when is_integer(duration) <- conn.body_params["duration_minutes"],
         volume when is_integer(volume) <- conn.body_params["volume_percent"],
         {:ok, status} <- Hue.start_breathing(target_id, duration, volume) do
      json(conn, 200, %{data: status})
    else
      nil -> api_error(conn, :invalid_body)
      {:error, reason} -> api_error(conn, reason)
      _ -> api_error(conn, :invalid_body)
    end
  end

  post "/api/breathing/volume" do
    case Hue.set_breathing_volume(conn.body_params["volume_percent"]) do
      {:ok, status} -> json(conn, 200, %{data: status})
      {:error, reason} -> api_error(conn, reason)
    end
  end

  post "/api/breathing/stop" do
    case Hue.stop_breathing() do
      {:ok, status} -> json(conn, 200, %{data: status})
      {:error, reason} -> api_error(conn, reason)
    end
  end

  get "/api/alarms" do
    json(conn, 200, %{data: Enum.map(Settings.list_alarms(), &alarm_json/1)})
  end

  get "/api/sounds" do
    json(conn, 200, %{data: SoundLibrary.list()})
  end

  post "/api/sounds" do
    with {:ok, contents} <- Base.decode64(conn.body_params["data_base64"] || ""),
         {:ok, metadata} <-
           SoundLibrary.import(
             conn.body_params["id"],
             contents,
             conn.body_params["sha256"] || ""
           ) do
      json(conn, 201, %{data: metadata})
    else
      :error -> api_error(conn, :invalid_sound)
      {:error, reason} -> api_error(conn, reason)
    end
  end

  get "/api/export" do
    download_json(conn, "robine-wake-configuration.json", Settings.export_configuration())
  end

  get "/api/diagnostics" do
    download_json(conn, "robine-wake-diagnostics.json", Diagnostics.build())
  end

  post "/api/alarms/preview" do
    case Alarm.new(conn.body_params) do
      {:ok, alarm} -> json(conn, 200, %{data: alarm_json(alarm)})
      {:error, reason} -> api_error(conn, reason)
    end
  end

  post "/api/alarms" do
    case Settings.create_alarm(conn.body_params) do
      {:ok, alarm} -> json(conn, 201, %{data: alarm_json(alarm)})
      {:error, reason} -> api_error(conn, reason)
    end
  end

  patch "/api/alarms/:id" do
    case Settings.update_alarm(id, conn.body_params) do
      {:ok, alarm} -> json(conn, 200, %{data: alarm_json(alarm)})
      {:error, reason} -> api_error(conn, reason)
    end
  end

  delete "/api/alarms/:id" do
    case Settings.delete_alarm(id, conn.body_params["revision"]) do
      :ok -> send_resp(conn, 204, "")
      {:error, reason} -> api_error(conn, reason)
    end
  end

  post "/api/alarms/:id/trigger" do
    case Scheduler.trigger_now(id) do
      {:ok, _pid} -> json(conn, 202, %{state: "starting"})
      {:error, reason} -> api_error(conn, reason)
    end
  end

  post "/api/alarms/:id/trigger-strong" do
    case Scheduler.trigger_strong_test(id) do
      {:ok, _pid} -> json(conn, 202, %{state: "starting", phase: "strong"})
      {:error, reason} -> api_error(conn, reason)
    end
  end

  post "/api/session/snooze" do
    case WakeSession.snooze() do
      {:ok, session} -> json(conn, 200, %{data: session})
      {:error, reason} -> api_error(conn, reason)
    end
  end

  post "/api/session/dismiss" do
    case WakeSession.dismiss(:manual) do
      {:ok, session} -> json(conn, 200, %{data: session})
      {:error, reason} -> api_error(conn, reason)
    end
  end

  post "/api/simulation/observation" do
    if Mix.target() == :host and camera_enabled?() do
      state = parse_state(conn.body_params["state"])
      confidence = number(conn.body_params["confidence"], 0.9)
      Camera.observe(state, confidence)
      json(conn, 202, %{accepted: true})
    else
      api_error(conn, :not_found)
    end
  end

  post "/api/camera/calibrate" do
    if camera_enabled?() do
      case Camera.calibrate(conn.body_params) do
        {:ok, result} -> json(conn, 200, %{data: result})
        {:error, reason} -> api_error(conn, reason)
      end
    else
      api_error(conn, :not_found)
    end
  end

  post "/api/time/confirm" do
    case ClockQuality.confirm() do
      {:ok, clock} -> json(conn, 200, %{data: clock})
    end
  end

  post "/api/remote-button/pairing" do
    case RemoteButton.begin_pairing(conn.body_params["duration_seconds"] || 120) do
      {:ok, status} -> json(conn, 200, %{data: status})
      {:error, reason} -> api_error(conn, reason)
    end
  end

  delete "/api/remote-button/:id" do
    case RemoteButton.remove(id) do
      :ok -> send_resp(conn, 204, "")
      {:error, reason} -> api_error(conn, reason)
    end
  end

  delete "/api/history" do
    case Settings.erase_history() do
      :ok -> send_resp(conn, 204, "")
      {:error, reason} -> api_error(conn, reason)
    end
  end

  post "/api/factory-reset" do
    if conn.body_params["confirmation"] == "RESET" do
      with :ok <- Settings.reset(),
           :ok <- RemoteButton.reset(),
           :ok <- maybe_reset_camera(),
           :ok <- EventLog.clear(),
           :ok <- Auth.factory_reset() do
        json(conn, 200, %{state: "factory_reset", next: "/"})
      else
        {:error, reason} -> api_error(conn, reason)
      end
    else
      json(conn, 422, %{error: %{code: "confirmation_required"}})
    end
  end

  match _ do
    api_error(conn, :not_found)
  end

  defp validate_mcp_origin(%Plug.Conn{request_path: "/mcp"} = conn, _opts) do
    case get_req_header(conn, "origin") do
      [] ->
        conn

      [origin] ->
        if same_origin?(conn, origin) or origin in mcp_allowed_origins() do
          conn
        else
          conn
          |> json(403, %{
            jsonrpc: "2.0",
            id: nil,
            error: %{code: -32_000, message: "Origin not allowed"}
          })
          |> halt()
        end

      _ ->
        conn |> send_resp(400, "Invalid Origin header") |> halt()
    end
  end

  defp validate_mcp_origin(conn, _opts), do: conn

  defp rate_limit_mcp(%Plug.Conn{request_path: "/mcp", method: "POST"} = conn, _opts) do
    if RateLimiter.allow?(conn.remote_ip) do
      conn
    else
      id = if is_map(conn.body_params), do: Map.get(conn.body_params, "id"), else: nil

      conn
      |> put_resp_header("retry-after", "60")
      |> json(429, %{
        jsonrpc: "2.0",
        id: id,
        error: %{code: -32_000, message: "MCP request rate limit exceeded"}
      })
      |> halt()
    end
  end

  defp rate_limit_mcp(conn, _opts), do: conn

  defp same_origin?(conn, origin) do
    case URI.parse(origin) do
      %URI{scheme: scheme, host: host, port: port, path: path, query: nil, fragment: nil}
      when scheme in ["http", "https"] and is_binary(host) and path in [nil, ""] ->
        scheme == Atom.to_string(conn.scheme) and
          String.downcase(host) == String.downcase(conn.host) and
          port == conn.port

      _ ->
        false
    end
  end

  defp mcp_allowed_origins,
    do: Application.get_env(:robine_wake, :mcp_allowed_origins, [])

  defp mcp_accepts_json_and_sse?(conn) do
    accepted =
      conn
      |> get_req_header("accept")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(fn value -> value |> String.split(";", parts: 2) |> hd() |> String.trim() end)

    "application/json" in accepted and "text/event-stream" in accepted
  end

  defp stream_events(conn) do
    receive do
      {:robine_event, event} ->
        case chunk(conn, sse_event(event)) do
          {:ok, conn} -> stream_events(conn)
          {:error, _reason} -> conn
        end
    after
      15_000 ->
        case chunk(conn, ": keep-alive\n\n") do
          {:ok, conn} -> stream_events(conn)
          {:error, _reason} -> conn
        end
    end
  end

  defp chunk_replay(conn, events) do
    Enum.reduce_while(events, {:ok, conn}, fn event, {:ok, conn} ->
      case chunk(conn, sse_event(event)) do
        {:ok, conn} -> {:cont, {:ok, conn}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp sse_event(event) do
    data =
      Jason.encode!(%{v: 1, id: event.id, event: event.event, at: event.at, data: event[:data]})

    "id: #{event.id}\nevent: #{event.event}\ndata: #{data}\n\n"
  end

  defp mcp_json_request?(conn) do
    case get_req_header(conn, "content-type") do
      [content_type] ->
        content_type |> String.split(";", parts: 2) |> hd() |> String.trim() ==
          "application/json"

      _ ->
        false
    end
  end

  defp protect_csrf(%Plug.Conn{method: method} = conn, _opts)
       when method in ["GET", "HEAD", "OPTIONS"],
       do: conn

  defp protect_csrf(%Plug.Conn{request_path: "/mcp"} = conn, _opts), do: conn
  defp protect_csrf(%Plug.Conn{request_path: "/api/v1/command"} = conn, _opts), do: conn

  defp protect_csrf(conn, _opts) do
    with [candidate] <- get_req_header(conn, "x-csrf-token"),
         true <- RobineWakeWeb.CSRF.valid?(candidate) do
      conn
    else
      _ -> conn |> json(403, %{error: %{code: "csrf_failed"}}) |> halt()
    end
  end

  defp alarm_json(%Alarm{} = alarm) do
    occurrences =
      if alarm.enabled,
        do: Enum.map(Alarm.next_occurrences(alarm, 5), &DateTime.to_iso8601/1),
        else: []

    Map.put(Alarm.to_map(alarm), "next_occurrences", occurrences)
  end

  defp json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, payload |> json_safe() |> Jason.encode!())
  end

  defp web_index(conn) do
    index_path = Application.app_dir(:robine_wake, "priv/web/index.html")

    if File.regular?(index_path) do
      conn
      |> put_resp_content_type("text/html")
      |> put_resp_header("cache-control", "no-cache")
      |> send_file(200, index_path)
    else
      send_resp(conn, 503, "Expo web bundle is not available")
    end
  end

  defp download_json(conn, filename, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, Jason.encode!(json_safe(payload), pretty: true) <> "\n")
  end

  defp json_safe(%_{} = struct), do: struct

  defp json_safe(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, json_safe(value)} end)

  defp json_safe(list) when is_list(list), do: Enum.map(list, &json_safe/1)

  defp json_safe(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&json_safe/1)

  defp json_safe(value), do: value

  defp redirect(conn, to: path) do
    conn
    |> put_resp_header("location", path)
    |> send_resp(302, "")
  end

  defp api_error(conn, reason) do
    {status, code} = error_response(reason)

    json(conn, status, %{error: %{code: code, details: normalize_reason(reason)}})
  end

  defp error_response(:not_found), do: {404, "not_found"}

  defp error_response(reason)
       when reason in [
              :revision_conflict,
              :active_session,
              :no_active_session,
              :snooze_limit,
              :snooze_disabled
            ],
       do: {409, Atom.to_string(reason)}

  defp error_response(:rate_limited), do: {429, "rate_limited"}

  defp error_response(reason)
       when reason in [:remote_button_not_paired, :pairing_window_closed],
       do: {404, Atom.to_string(reason)}

  defp error_response(reason)
       when reason in [
              :invalid_pairing_duration,
              :invalid_button_id,
              :invalid_button_name,
              :invalid_remote_button_counter,
              :invalid_remote_button_signature,
              :invalid_remote_button_command
            ],
       do: {422, Atom.to_string(reason)}

  defp error_response(reason)
       when reason in [:camera_not_detected, :rpicam_still_not_found, :use_submit_frame_on_host],
       do: {503, "capability_unavailable"}

  defp error_response(reason)
       when reason in [
              :invalid_sound,
              :invalid_sound_id,
              :invalid_size_or_digest,
              :invalid_wave,
              :not_pcm,
              :unsupported_channels,
              :unsupported_sample_rate,
              :unsupported_bit_depth,
              :invalid_format_sizes,
              :invalid_file_sizes
            ],
       do: {422, "invalid_sound"}

  defp error_response(reason) when is_map(reason), do: {422, "validation_failed"}
  defp error_response(_reason), do: {500, "internal_error"}

  defp normalize_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_reason(reason), do: reason
  defp parse_state("occupied"), do: :occupied
  defp parse_state("vacant"), do: :vacant
  defp parse_state(_), do: :unknown
  defp number(value, _default) when is_number(value), do: value / 1

  defp number(value, default) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> default
    end
  end

  defp number(_, default), do: default

  defp camera_enabled?, do: Application.get_env(:robine_wake, :camera_enabled, true)

  defp maybe_reset_camera do
    if camera_enabled?(), do: Camera.reset(), else: :ok
  end

  defp page do
    """
    <!doctype html>
    <html lang="fr">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta name="csrf-token" content="#{RobineWakeWeb.CSRF.token()}">
      <title>Robine Wake</title>
      <style>#{RobineWakeWeb.Design.product_css()}</style>
    </head>
    <body>
      <main class="shell">
        <nav class="topbar" aria-label="État du réveil">
          <div class="brand"><span class="brand-mark" aria-hidden="true"></span><div><strong>ROBINE WAKE</strong><small>Un réveil qui commence doucement</small></div></div>
          <button id="health" class="status-pill" type="button" onclick="showDiagnostics()" aria-label="Ouvrir le diagnostic">Connexion…</button>
        </nav>

        <nav class="app-tabs" aria-label="Navigation principale">
          <button class="app-tab active" data-screen="morning" onclick="showScreen('morning')"><span>☀︎</span>Matin</button>
          <button class="app-tab" data-screen="evening" onclick="showScreen('evening')"><span>☾</span>Soir</button>
          <button class="app-tab" data-screen="alarms" onclick="showScreen('alarms')"><span>◷</span>Alarmes</button>
          <button class="app-tab" data-screen="system" onclick="showScreen('system')"><span>✦</span>Réveil</button>
        </nav>

        <section id="screen-morning" class="app-screen active">
          <header class="hero">
            <div class="hero-copy"><p class="eyebrow">Votre matin</p><h1 id="hero-time" class="hero-time">--:--</h1><p id="hero-date" class="hero-date">Synchronisation du réveil</p></div>
            <div class="next-wake"><span>Prochain réveil</span><strong id="next-alarm-time">—</strong><p id="next-alarm-label">Aucune alarme programmée.</p></div>
          </header>
          <p id="clock-warning" class="clock-warning" role="alert" hidden>L’heure doit être confirmée avant d’activer les alarmes. <button class="ghost" onclick="confirmTime()">Confirmer l’heure</button></p>
          <div class="dashboard">
            <section id="session" class="session-banner" hidden><div><span class="panel-kicker">Réveil en cours</span><h2>Bonjour</h2><p id="session-state"></p></div><div class="actions"><button class="secondary" onclick="sessionAction('snooze')">Répéter</button><button class="danger" onclick="sessionAction('dismiss')">Je suis levé</button></div></section>
            <section class="panel full"><div class="panel-head"><div><span class="panel-kicker">Prochain réveil</span><h2>Vos matinées</h2></div><button class="primary" type="button" onclick="openAlarmEditor()">＋ Ajouter</button></div><div id="morning-alarms" class="alarm-list compact-alarm-list"><div class="empty-state">Chargement…</div></div></section>
            <section class="panel full"><div class="panel-head"><div><span class="panel-kicker">Historique</span><h2>Réveils récents</h2></div></div><div id="sessions" class="timeline"><div class="empty-state">Aucune séance enregistrée.</div></div></section>
          </div>
        </section>

        <section id="screen-evening" class="app-screen">
          <header class="evening-hero"><div class="breathing-orb" aria-hidden="true"><span></span></div><p class="eyebrow">Rituel du soir</p><h1>Ralentir avant la nuit</h1><p>Une respiration guidée uniquement par la lumière, sur un orage naturel et continu.</p></header>
          <div class="dashboard">
            <section class="panel full breathing-panel">
              <div class="panel-head"><div><span class="panel-kicker rose">Respiration 4 / 6</span><h2 id="breathing-title">Préparer la séance</h2></div><strong id="breathing-badge" class="breathing-badge">Prêt</strong></div>
              <div id="breathing-active" class="breathing-active" hidden><div class="phase-visual"><div id="phase-orb" class="phase-orb"></div><div><span id="breathing-phase" class="panel-kicker">Inspiration</span><strong id="breathing-remaining">—</strong><small id="breathing-target-name">Lumière Hue</small></div></div></div>
              <p class="panel-copy">La couleur bascule rapidement à chaque phase ; seule la luminosité varie lentement. L’orage reste constant même si cet écran se ferme.</p>
              <div class="phase-legends"><div><i class="inhale-dot"></i><span><strong>Inspiration</strong><small>4 s · bleu · 1 → 30 %</small></span></div><div><i class="exhale-dot"></i><span><strong>Expiration</strong><small>6 s · ambre · 30 → 1 %</small></span></div></div>
              <div class="evening-controls">
                <label class="field">Pièce ou zone<select id="breathing-target"></select></label>
                <label class="field">Durée<select id="breathing-duration"><option value="3">3 minutes</option><option value="5">5 minutes</option><option value="10" selected>10 minutes</option><option value="15">15 minutes</option><option value="20">20 minutes</option><option value="30">30 minutes</option></select></label>
                <label class="field range-field volume-control">Volume <output id="breathing-volume-output">60 %</output><input id="breathing-volume" type="range" min="0" max="100" step="5" value="60" oninput="syncBreathingVolume()" onchange="commitBreathingVolume()"></label>
              </div>
              <div class="actions breathing-actions"><button id="breathing-start" class="primary" onclick="startBreathing()">▶ Commencer la séance</button><button id="breathing-stop" class="danger" onclick="stopBreathing()" hidden>■ Terminer et restaurer la lumière</button></div>
              <p id="breathing-message" class="panel-copy" role="status"></p>
            </section>
          </div>
        </section>

        <section id="screen-alarms" class="app-screen">
          <div class="screen-heading"><p class="eyebrow">Vos habitudes</p><h1>Alarmes</h1><p>Préparez chaque réveil, de la montée douce au son de renfort.</p></div>
          <div class="dashboard">
            <section class="panel full"><div class="panel-head"><div><span class="panel-kicker">Planning</span><h2>Vos alarmes</h2></div><button class="primary" type="button" onclick="openAlarmEditor()">＋ Nouvelle alarme</button></div><div id="alarms" class="alarm-list"><div class="empty-state">Chargement…</div></div></section>
            <section class="panel full"><div class="panel-head"><div><span class="panel-kicker">Paysages sonores</span><h2>Bibliothèque</h2></div><small>Sur le réveil</small></div><div id="sounds" class="sound-library-grid"><div class="empty-state">Chargement…</div></div><details class="settings"><summary>Importer un son personnalisé</summary><p class="panel-copy">WAV PCM, mono ou stéréo, 44,1/48 kHz, 16 bits et 5 Mo maximum.</p><form id="sound-form" class="form-grid"><label class="field">Identifiant<input name="id" pattern="[A-Za-z0-9_-]{1,64}" required></label><label class="field wide">SHA-256<input name="sha256" minlength="64" maxlength="64" required></label><label class="field">Fichier WAV<input name="file" type="file" accept="audio/wav,.wav" required></label><div class="actions form-actions" style="grid-column:1/-1"><button type="submit" class="secondary">Valider et importer</button></div></form></details></section>
          </div>
        </section>

        <section id="screen-system" class="app-screen">
          <div class="screen-heading"><p class="eyebrow">État du réveil</p><h1>Robine Wake</h1><p>Connexions, matériel, confidentialité et maintenance locale.</p></div>
          <div class="dashboard">
            <section id="diagnostics-panel" class="panel full" tabindex="-1"><div class="panel-head"><div><span class="panel-kicker">Diagnostic</span><h2 id="diagnostics-title">État technique</h2></div><strong id="diagnostics-summary">Chargement…</strong></div><p class="panel-copy">Les éléments qui demandent une intervention apparaissent en premier.</p><div id="diagnostics-list" class="diagnostic-list"><div class="empty-state">Chargement…</div></div></section>
            <section id="remote-button-panel" class="panel full"><div class="panel-head"><div><span class="panel-kicker">Bouton déporté</span><h2>Arrêt sécurisé en LoRa</h2></div><strong id="remote-button-state">Chargement…</strong></div><p class="panel-copy">Le Raspberry écoute directement le bouton en 868 MHz. Chaque appui utilise un secret propre, un compteur anti-rejeu et un accusé de réception, sans Internet ni routeur.</p><div id="remote-button-list" class="timeline"><div class="empty-state">Aucun bouton associé.</div></div><p id="remote-button-message" class="panel-copy" aria-live="polite"></p><div class="actions"><button id="remote-button-pair" class="primary" onclick="beginRemoteButtonPairing()">Associer un bouton</button></div></section>
            <section class="panel"><div class="panel-head"><div><span class="panel-kicker">Système</span><h2>Prêt pour la nuit</h2></div></div><div class="system-row"><span>Firmware</span><strong id="update-state">Chargement…</strong></div><p class="panel-copy">Les mises à jour signées attendent toujours une fenêtre sûre.</p></section>
            <section class="panel"><div class="panel-head"><div><span class="panel-kicker">Vos données</span><h2>Confidentialité</h2></div></div><div class="privacy-note">Les exports contiennent uniquement les réglages et l’état technique.</div><div class="actions"><button class="ghost" onclick="location.href='/api/export'">Exporter</button><button class="ghost" onclick="location.href='/api/diagnostics'">Diagnostics</button><button class="danger" onclick="eraseHistory()">Effacer l’historique</button><button class="danger" onclick="factoryReset()">Réinitialiser</button></div></section>
          </div>
        </section>

        <footer class="footer">Robine Wake · Privé par conception · Pour des matins plus doux</footer>
      </main>
      <dialog id="alarm-dialog" aria-labelledby="alarm-dialog-title">
        <div class="alarm-editor">
          <header class="editor-head">
            <div><span id="alarm-dialog-kicker" class="panel-kicker">New wake ritual</span><h2 id="alarm-dialog-title">Create an alarm</h2></div>
            <button class="ghost icon-button" type="button" aria-label="Close alarm editor" onclick="closeAlarmEditor()">×</button>
          </header>
          <form id="alarm-form" class="editor-form">
            <section class="editor-section">
              <div class="section-title"><div><h3>When should your morning begin?</h3><p>Set the moment and give this alarm a name.</p></div></div>
              <div class="editor-basics">
                <label class="field time-field">Wake time<input name="local_time" type="time" value="07:00" required></label>
                <label class="field">Alarm name<input name="label" value="Morning alarm" maxlength="80" placeholder="Morning alarm"></label>
                <label class="field">Time zone<input name="timezone" value="Europe/Paris" required></label>
              </div>
              <div class="schedule-row">
                <fieldset class="field"><legend>Repeat every</legend><div class="days"><label class="day"><input name="days_of_week" type="checkbox" value="1" checked><span>M</span></label><label class="day"><input name="days_of_week" type="checkbox" value="2" checked><span>T</span></label><label class="day"><input name="days_of_week" type="checkbox" value="3" checked><span>W</span></label><label class="day"><input name="days_of_week" type="checkbox" value="4" checked><span>T</span></label><label class="day"><input name="days_of_week" type="checkbox" value="5" checked><span>F</span></label><label class="day"><input name="days_of_week" type="checkbox" value="6" checked><span>S</span></label><label class="day"><input name="days_of_week" type="checkbox" value="7" checked><span>S</span></label></div></fieldset>
                <label class="field">Or choose one date <small>Leave empty for a repeating alarm</small><input name="one_shot_date" type="date"></label>
              </div>
            </section>

            <section class="editor-section">
              <div class="section-title"><div><h3>Your two-stage wake-up</h3><p>Start calmly. Escalate only if you are still in bed when the gentle ramp ends.</p></div><small>Alarm always overrides AirPlay</small></div>
              <div class="sound-journey">
                <label class="sound-phase field"><span class="phase-label"><span class="phase-number">1</span><span><strong>Gentle wake</strong><small>Fades in gradually</small></span></span><select name="sound_id" id="gentle-sound-select" required><option value="default">Default tone</option></select></label>
                <span class="journey-arrow" aria-hidden="true">→</span>
                <label class="sound-phase strong field"><span class="phase-label"><span class="phase-number">2</span><span><strong>Strong wake</strong><small>Plays after the ramp if needed</small></span></span><select name="strong_sound_id" id="strong-sound-select" required><option value="default">Default tone</option></select></label>
              </div>
            </section>

            <section class="editor-section">
              <div class="section-title"><div><h3>Shape the gentle ramp</h3><p>The ramp reaches its maximum at the configured wake time, stays there for 5 minutes, then the strong sound takes over.</p></div></div>
              <div class="control-grid">
                <label class="field range-field">Start volume <output id="volume-start-output">15%</output><input name="volume_start" type="range" min="0" max="#{Application.fetch_env!(:robine_wake, :audio_safety_ceiling)}" value="15" oninput="syncAlarmOutputs()"></label>
                <label class="field range-field">Maximum volume <output id="volume-ceiling-output">85%</output><input name="volume_ceiling" type="range" min="0" max="#{Application.fetch_env!(:robine_wake, :audio_safety_ceiling)}" value="85" oninput="syncAlarmOutputs()"></label>
                <label class="field range-field">Start before wake time <output id="prewake-output">20 min</output><input name="prewake_minutes" type="range" min="1" max="60" value="20" oninput="syncAlarmOutputs()"></label>
              </div>
            </section>

            <section class="editor-section">
              <div class="section-title"><div><h3>Getting out of bed</h3><p>Choose how Robine Wake knows that your morning has started.</p></div></div>
              <div class="behavior-grid">
                <label class="field">Arrêter le réveil<select name="dismiss_policy"><option value="manual">Depuis l’application ou le réveil</option></select></label>
                <label class="field">Snooze duration <small>Minutes</small><input name="snooze_minutes" type="number" min="1" max="30" value="8"></label>
                <label class="field">Maximum snoozes<input name="snooze_maximum" type="number" min="0" max="10" value="3"></label>
              </div>
              <label class="switch" style="margin-top:.9rem"><input name="snooze_enabled" type="checkbox" checked> Allow snoozing for this alarm</label>
            </section>

            <p id="alarm-preview" class="panel-copy" aria-live="polite"></p><p id="form-error" role="alert"></p>
            <footer class="editor-actions"><button type="button" class="ghost" onclick="previewAlarm()">Preview next mornings</button><div><button type="button" class="ghost" onclick="closeAlarmEditor()">Cancel</button><button id="alarm-submit" type="submit" class="primary">Create alarm</button></div></footer>
          </form>
        </div>
      </dialog>
      <script>
        let stateCache={alarms:[],sounds:[]}; const csrfToken=document.querySelector('meta[name="csrf-token"]').content; const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
        const alarmDialog=document.querySelector('#alarm-dialog'); const alarmForm=document.querySelector('#alarm-form');
        const soundName=id=>stateCache.sounds.find(sound=>sound.id===id)?.title||id||'Son par défaut';
        const durationLabel=milliseconds=>milliseconds>=60000?`${Math.round(milliseconds/60000)} min`:`${Math.round(milliseconds/1000)} sec`;
        const repeatLabel=alarm=>alarm.one_shot_date?new Date(`${alarm.one_shot_date}T12:00:00`).toLocaleDateString('fr-FR',{weekday:'short',day:'numeric',month:'short'}):alarm.days_of_week.length===7?'Tous les jours':alarm.days_of_week.length===5&&alarm.days_of_week.every(day=>day<=5)?'En semaine':alarm.days_of_week.map(day=>['','Lun','Mar','Mer','Jeu','Ven','Sam','Dim'][day]).join(' · ');
        async function request(path, options={}) { const method=options.method||'GET'; const headers={'content-type':'application/json',...(options.headers||{})}; if(!['GET','HEAD','OPTIONS'].includes(method.toUpperCase()))headers['x-csrf-token']=csrfToken; const url=new URL(path,location.origin); const response=await fetch(url,{...options,headers}); if(!response.ok){throw await response.json()} return response.status===204?null:response.json(); }
        function showScreen(name){for(const screen of document.querySelectorAll('.app-screen'))screen.classList.toggle('active',screen.id===`screen-${name}`);for(const tab of document.querySelectorAll('.app-tab'))tab.classList.toggle('active',tab.dataset.screen===name);window.scrollTo({top:0,behavior:'smooth'})}
        function showDiagnostics(){showScreen('system');history.replaceState(null,'','#diagnostics');requestAnimationFrame(()=>{const panel=document.querySelector('#diagnostics-panel');panel.scrollIntoView({behavior:'smooth',block:'start'});panel.focus({preventScroll:true})})}
        const reasonLabel=reason=>({confirmation_required:"Confirmation de l’heure nécessaire",clock_untrusted:'Horloge non synchronisée',hue_not_configured:'Pont Hue non configuré'}[reason]||reason||'Aucun problème détecté');
        function renderDiagnostics(data){const h=data.health;const items=[
          {name:'Horloge',state:h.clock.state,detail:h.clock.trusted?`Synchronisée automatiquement · ${h.clock.source}`:reasonLabel(h.clock.reason)},
          {name:'Alarmes',state:h.scheduler.state,detail:h.scheduler.armed?'Planificateur armé':`Planificateur désarmé · ${reasonLabel(h.clock.reason)}`},
          {name:'Audio',state:h.audio.driver_status.state,detail:h.audio.last_error?String(h.audio.last_error):h.audio.driver_status.device},
          {name:'Réseau',state:h.network.state,detail:(h.network.ipv4_addresses||[]).join(' · ')||'Aucune adresse réseau'},
          {name:'Lumières Hue',state:data.hue.state,detail:data.hue.last_error||`${data.hue.target_count||0} pièce(s) disponible(s)`},
          {name:'Récepteur LoRa',state:data.lora?.state||'unavailable',detail:data.lora?.last_error||`${((data.lora?.frequency_hz||0)/1000000).toFixed(1)} MHz · ${data.lora?.packets_received||0} paquet(s) reçu(s)`},
          {name:'Stockage',state:h.storage.state,detail:'Configuration locale'},
          {name:'Firmware',state:h.firmware.state,detail:`${h.firmware.validation} · ${h.firmware.build_id}`},
          {name:'AirPlay',state:h.airplay.state,detail:h.airplay.reason||h.airplay.name}
        ];const rank={unhealthy:0,unavailable:0,degraded:1,unknown:1,healthy:2,available:2,trusted:2};items.sort((a,b)=>(rank[a.state]??1)-(rank[b.state]??1));document.querySelector('#diagnostics-summary').textContent=h.state==='healthy'?'Tout est opérationnel':'Intervention recommandée';document.querySelector('#diagnostics-summary').className=h.state;document.querySelector('#diagnostics-list').innerHTML=items.map(item=>`<div class="diagnostic-item"><span>${esc(item.name)}</span><strong class="${esc(item.state)}">${esc(item.state==='healthy'||item.state==='available'||item.state==='trusted'?'OK':item.state==='degraded'?'À vérifier':'Indisponible')}</strong><small>${esc(item.detail)}</small></div>`).join('')}
        function alarmMarkup(a){const prewake=(a.prewake_seconds??a.volume_profile.ramp_seconds)/60;return `<article class="alarm ${a.enabled?'':'disabled'}"><div class="alarm-time">${esc(a.local_time.slice(0,5))}</div><div><strong>${esc(a.label)}</strong><div class="alarm-meta"><span>${esc(a.enabled?repeatLabel(a):'En pause')}</span><span>·</span><span>début ${esc(prewake)} min avant</span></div><div class="sound-route"><span>${esc(soundName(a.sound_id))}</span><i>→</i><span>${esc(soundName(a.strong_sound_id))}</span></div></div><div class="actions"><button class="ghost" onclick="triggerAlarm('${a.id}')">Tester doux</button><button class="danger" onclick="triggerStrongAlarm('${a.id}')">Tester fort</button><button class="ghost" onclick="openAlarmEditor('${a.id}')">Modifier</button><button class="secondary" onclick="toggleAlarm('${a.id}')">${a.enabled?'Pause':'Activer'}</button><button class="danger" onclick="deleteAlarm('${a.id}')">Supprimer</button></div></article>`}
        function renderBreathing(data){const breathing=data.hue?.breathing;const active=breathing?.active===true;const targetSelect=document.querySelector('#breathing-target');const selected=active?breathing.target_id:targetSelect.value;targetSelect.innerHTML=(data.hue_targets||[]).map(target=>`<option value="${esc(target.id)}">${esc(target.name)}</option>`).join('');if([...targetSelect.options].some(option=>option.value===selected))targetSelect.value=selected;document.querySelector('#breathing-active').hidden=!active;document.querySelector('#breathing-start').hidden=active;document.querySelector('#breathing-stop').hidden=!active;document.querySelector('#breathing-title').textContent=active?'La séance est en cours':'Préparer la séance';document.querySelector('#breathing-badge').textContent=active?'En cours':data.hue?.state==='available'?'Prêt':'Hue indisponible';document.querySelector('#breathing-badge').className=`breathing-badge ${active?'active':''}`;if(active){const inhale=breathing.phase==='inhale';document.querySelector('#breathing-phase').textContent=inhale?'Inspiration':'Expiration';document.querySelector('#phase-orb').className=`phase-orb ${inhale?'inhale':'exhale'}`;document.querySelector('#breathing-remaining').textContent=`${Math.ceil((breathing.remaining_seconds||0)/60)} min restantes`;document.querySelector('#breathing-target-name').textContent=breathing.target_name||'Lumière Hue';const volume=breathing.audio?.volume_percent??60;document.querySelector('#breathing-volume').value=volume;document.querySelector('#breathing-volume-output').textContent=`${volume} %`}}
        function renderRemoteButton(data){const remote=data.remote_button||{};const radio=data.lora||{};const listening=radio.state==='listening';const pairing=remote.pairing?.active===true;const buttons=remote.buttons||[];document.querySelector('#remote-button-state').textContent=!listening?'Récepteur indisponible':pairing?'Association en cours':buttons.length?`${buttons.length} bouton(s) prêt(s)`:'Prêt à associer';document.querySelector('#remote-button-list').innerHTML=buttons.length?buttons.map(button=>`<div class="timeline-item"><div><strong>${esc(button.name)}</strong><br><small>${button.last_seen_at?`Dernier appui · ${esc(new Date(button.last_seen_at).toLocaleString('fr-FR'))}`:'Jamais utilisé'}</small></div><button class="danger" onclick="removeRemoteButton('${esc(button.id)}')">Oublier</button></div>`).join(''):'<div class="empty-state">Aucun bouton associé.</div>';document.querySelector('#remote-button-pair').disabled=pairing||!listening;document.querySelector('#remote-button-message').textContent=!listening?`Le module LoRa n’est pas prêt${radio.last_error?` : ${radio.last_error}`:'.'}`:pairing?'Fenêtre ouverte pendant 2 minutes : maintenez maintenant le bouton physique enfoncé.':`Récepteur à ${((radio.frequency_hz||0)/1000000).toFixed(1)} MHz.`}
        async function refresh(){
          const data=await request('/api/state'); stateCache={...data,sounds:stateCache.sounds}; const h=data.health; const now=new Date(h.now); const health=document.querySelector('#health');
          health.textContent=h.state==='healthy'?'Tout est prêt':h.state==='degraded'?'Attention requise':'Système indisponible'; health.className=`status-pill ${h.state}`;
          document.querySelector('#hero-time').textContent=now.toLocaleTimeString('fr-FR',{hour:'2-digit',minute:'2-digit'});
          document.querySelector('#hero-date').textContent=now.toLocaleDateString('fr-FR',{weekday:'long',month:'long',day:'numeric'});
          document.querySelector('#clock-warning').hidden=h.clock.trusted;
          const scheduled=data.alarms.filter(a=>a.enabled&&a.next_occurrences[0]).sort((a,b)=>new Date(a.next_occurrences[0])-new Date(b.next_occurrences[0])); const next=scheduled[0];
          document.querySelector('#next-alarm-time').textContent=next?new Date(next.next_occurrences[0]).toLocaleTimeString('fr-FR',{hour:'2-digit',minute:'2-digit'}):'—';
          document.querySelector('#next-alarm-label').textContent=next?`${next.label} · ${new Date(next.next_occurrences[0]).toLocaleDateString('fr-FR',{weekday:'long'})}`:'Aucune alarme programmée.';
          const alarmsHtml=data.alarms.map(alarmMarkup).join('')||'<div class="empty-state">Aucune alarme.<br><button class="primary" type="button" onclick="openAlarmEditor()">Créer une alarme</button></div>';document.querySelector('#alarms').innerHTML=alarmsHtml;document.querySelector('#morning-alarms').innerHTML=data.alarms.slice(0,2).map(alarmMarkup).join('')||alarmsHtml;
          const active=data.active_session; const session=document.querySelector('#session'); session.hidden=!active; if(active)document.querySelector('#session-state').textContent=`${active.audio_phase==='strong'?'Son de renfort':'Réveil progressif'} · volume ${active.current_gain} · ${active.snooze_count} répétitions`;
          document.querySelector('#sessions').innerHTML=data.sessions.slice(0,8).map(s=>`<div class="timeline-item"><div><strong>${esc(s.terminal_reason||s.state)}</strong><br><small>${esc(new Date(s.created_at).toLocaleString('fr-FR'))}</small></div></div>`).join('')||'<div class="empty-state">Votre historique apparaîtra ici.</div>';
          const updates=h.updates; document.querySelector('#update-state').textContent=`${h.firmware.version} · ${h.firmware.validation} · ${updates.state}${updates.reason?' · '+updates.reason:''}`;
          renderDiagnostics(data);
          renderBreathing(data);
          renderRemoteButton(data);
        }
        async function refreshSounds(){const sounds=await request('/api/sounds');stateCache.sounds=sounds.data;document.querySelector('#sounds').innerHTML=sounds.data.map(sound=>`<div class="sound-chip"><strong>${esc(sound.title||sound.id)}</strong><small>${esc(sound.artist||'Custom sound')} · ${esc(durationLabel(sound.duration_ms))}</small><em>${esc(sound.intensity||sound.format)}</em></div>`).join('');for(const select of [document.querySelector('#gentle-sound-select'),document.querySelector('#strong-sound-select')]){const selected=select.value;select.innerHTML=sounds.data.map(sound=>`<option value="${esc(sound.id)}">${esc(sound.title||sound.id)} · ${esc(sound.artist||'Custom')}</option>`).join('');if([...select.options].some(option=>option.value===selected))select.value=selected}}
        function alarmPayload(formElement){const form=new FormData(formElement);const payload=Object.fromEntries(form);const prewakeSeconds=Number(payload.prewake_minutes)*60;payload.days_of_week=payload.one_shot_date?[]:form.getAll('days_of_week').map(Number);payload.prewake_seconds=prewakeSeconds;payload.volume_profile={start:Number(payload.volume_start),ceiling:Number(payload.volume_ceiling),ramp_seconds:prewakeSeconds};payload.snooze={enabled:formElement.elements.snooze_enabled.checked,duration_seconds:Number(payload.snooze_minutes)*60,maximum:Number(payload.snooze_maximum)};['volume_start','volume_ceiling','prewake_minutes','snooze_enabled','snooze_minutes','snooze_maximum'].forEach(key=>delete payload[key]);if(formElement.dataset.id)payload.revision=Number(formElement.dataset.revision);return payload}
        function syncAlarmOutputs(){const fields=alarmForm.elements;document.querySelector('#volume-start-output').textContent=`${fields.volume_start.value}%`;document.querySelector('#volume-ceiling-output').textContent=`${fields.volume_ceiling.value}%`;document.querySelector('#prewake-output').textContent=`${fields.prewake_minutes.value} min`}
        function setSelectValue(select,value,fallback){select.value=[...select.options].some(option=>option.value===value)?value:fallback}
        function openAlarmEditor(id=null){alarmForm.reset();alarmForm.dataset.id='';alarmForm.dataset.revision='';document.querySelector('#form-error').textContent='';document.querySelector('#alarm-preview').textContent='';document.querySelector('#alarm-dialog-kicker').textContent=id?'Wake ritual':'New wake ritual';document.querySelector('#alarm-dialog-title').textContent=id?'Edit alarm':'Create an alarm';document.querySelector('#alarm-submit').textContent=id?'Save changes':'Create alarm';const fields=alarmForm.elements;if(id){const alarm=stateCache.alarms.find(item=>item.id===id);if(!alarm)return;alarmForm.dataset.id=id;alarmForm.dataset.revision=alarm.revision;fields.label.value=alarm.label;fields.local_time.value=alarm.local_time.slice(0,5);fields.timezone.value=alarm.timezone;fields.one_shot_date.value=alarm.one_shot_date||'';fields.dismiss_policy.value=alarm.dismiss_policy;fields.volume_start.value=alarm.volume_profile.start;fields.volume_ceiling.value=alarm.volume_profile.ceiling;fields.prewake_minutes.value=Math.max(1,Math.round((alarm.prewake_seconds??alarm.volume_profile.ramp_seconds)/60));fields.snooze_enabled.checked=alarm.snooze.enabled;fields.snooze_minutes.value=alarm.snooze.duration_seconds/60;fields.snooze_maximum.value=alarm.snooze.maximum;for(const checkbox of alarmForm.querySelectorAll('[name="days_of_week"]'))checkbox.checked=alarm.days_of_week.includes(Number(checkbox.value));setSelectValue(fields.sound_id,alarm.sound_id,'default');setSelectValue(fields.strong_sound_id,alarm.strong_sound_id||'default','default')}else{setSelectValue(fields.sound_id,'jungle_sunrise','default');setSelectValue(fields.strong_sound_id,'wake_up_call','default')}syncAlarmOutputs();alarmDialog.showModal()}
        function closeAlarmEditor(){alarmDialog.close()}
        alarmDialog.addEventListener('click',event=>{if(event.target===alarmDialog)closeAlarmEditor()});
        alarmForm.addEventListener('submit',async event=>{event.preventDefault();const id=alarmForm.dataset.id;try{await request(id?`/api/alarms/${id}`:'/api/alarms',{method:id?'PATCH':'POST',body:JSON.stringify(alarmPayload(alarmForm))});closeAlarmEditor();await refresh()}catch(error){document.querySelector('#form-error').textContent=error.error?.details?Object.values(error.error.details).join(' · '):'Unable to save this alarm.'}});
        async function previewAlarm(){try{const data=await request('/api/alarms/preview',{method:'POST',body:JSON.stringify(alarmPayload(alarmForm))});document.querySelector('#alarm-preview').textContent='Next mornings · '+data.data.next_occurrences.slice(0,3).map(value=>new Date(value).toLocaleString('en-GB',{weekday:'short',day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})).join('  ·  ');document.querySelector('#form-error').textContent=''}catch(error){document.querySelector('#form-error').textContent='Complete the schedule to preview it.'}}
        async function triggerAlarm(id){await request(`/api/alarms/${id}/trigger`,{method:'POST',body:'{}'}); await refresh()}
        async function triggerStrongAlarm(id){if(confirm('Tester directement le son de renfort au volume maximal configuré ?')){await request(`/api/alarms/${id}/trigger-strong`,{method:'POST',body:'{}'});await refresh()}}
        async function deleteAlarm(id){if(confirm('Delete this alarm?')){const a=stateCache.alarms.find(item=>item.id===id);await request(`/api/alarms/${id}`,{method:'DELETE',body:JSON.stringify({revision:a.revision})});await refresh()}}
        async function toggleAlarm(id){const a=stateCache.alarms.find(item=>item.id===id);await request(`/api/alarms/${id}`,{method:'PATCH',body:JSON.stringify({enabled:!a.enabled,revision:a.revision})});await refresh()}
        async function sessionAction(action){await request(`/api/session/${action}`,{method:'POST',body:'{}'});await refresh()}
        async function observe(state){await request('/api/simulation/observation',{method:'POST',body:JSON.stringify({state,confidence:.95})});await refresh()}
        function syncBreathingVolume(){document.querySelector('#breathing-volume-output').textContent=`${document.querySelector('#breathing-volume').value} %`}
        async function commitBreathingVolume(){if(stateCache.hue?.breathing?.active!==true)return;const message=document.querySelector('#breathing-message');try{await request('/api/breathing/volume',{method:'POST',body:JSON.stringify({volume_percent:Number(document.querySelector('#breathing-volume').value)})});message.textContent='Volume mis à jour.'}catch(error){message.textContent=error.error?.message||'Impossible de modifier le volume.'}}
        async function startBreathing(){const message=document.querySelector('#breathing-message');const target=document.querySelector('#breathing-target').value;if(!target){message.textContent='Aucune pièce Hue disponible.';return}message.textContent='Démarrage de la séance…';try{await request('/api/breathing/start',{method:'POST',body:JSON.stringify({target_id:target,duration_minutes:Number(document.querySelector('#breathing-duration').value),volume_percent:Number(document.querySelector('#breathing-volume').value)})});message.textContent='La lumière et le paysage sonore démarrent.';await refresh()}catch(error){message.textContent=error.error?.message||'Impossible de démarrer la séance.'}}
        async function stopBreathing(){const message=document.querySelector('#breathing-message');message.textContent='Fin de la séance…';try{await request('/api/breathing/stop',{method:'POST',body:'{}'});message.textContent='Séance terminée, lumière restaurée.';await refresh()}catch(error){message.textContent=error.error?.message||'Impossible de terminer la séance.'}}
        async function confirmTime(){await request('/api/time/confirm',{method:'POST',body:'{}'});await refresh()}
        async function beginRemoteButtonPairing(){const message=document.querySelector('#remote-button-message');try{await request('/api/remote-button/pairing',{method:'POST',body:JSON.stringify({duration_seconds:120})});message.textContent='Fenêtre ouverte : maintenez maintenant le bouton physique enfoncé.';await refresh()}catch(error){message.textContent='Impossible d’ouvrir la fenêtre d’association.'}}
        async function removeRemoteButton(id){if(confirm('Oublier ce bouton ?')){await request(`/api/remote-button/${encodeURIComponent(id)}`,{method:'DELETE'});await refresh()}}
        async function eraseHistory(){if(confirm('Erase all session history?')){await request('/api/history',{method:'DELETE'});await refresh()}}
        async function factoryReset(){const confirmation=prompt('Type RESET to erase alarms, history, and diagnostics.');if(confirmation==='RESET'){await request('/api/factory-reset',{method:'POST',body:JSON.stringify({confirmation})});location.href='/'}}
        document.querySelector('#sound-form').addEventListener('submit',async event=>{event.preventDefault();const form=new FormData(event.target);const file=form.get('file');const bytes=new Uint8Array(await file.arrayBuffer());let binary='';for(let index=0;index<bytes.length;index+=32768)binary+=String.fromCharCode(...bytes.subarray(index,index+32768));const payload={id:form.get('id'),sha256:form.get('sha256'),data_base64:btoa(binary)};await request('/api/sounds',{method:'POST',body:JSON.stringify(payload)});event.target.reset();await refreshSounds()})
        refresh(); refreshSounds(); if(location.hash==='#diagnostics')showDiagnostics(); setInterval(refresh,2000);
      </script>
    </body>
    </html>
    """
  end
end
