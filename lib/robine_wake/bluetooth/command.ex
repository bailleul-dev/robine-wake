defmodule RobineWake.Bluetooth.Command do
  @moduledoc "Stable versioned command boundary shared by Bluetooth clients."

  alias RobineWake.{
    Alarm,
    Auth,
    Camera,
    ClockQuality,
    CommandCache,
    EventLog,
    Health,
    Hue,
    RemoteButton,
    Scheduler,
    Settings,
    SoundLibrary,
    WakeSession
  }

  alias RobineWake.LoRa.Server, as: LoRaServer

  @version 1
  @operations [
    "capabilities.get",
    "state.get",
    "alarm.create",
    "alarm.update",
    "alarm.delete",
    "alarm.preview",
    "alarm.trigger",
    "alarm.trigger_strong",
    "session.get",
    "session.snooze",
    "session.dismiss",
    "settings.smartphone_dismiss.set",
    "clock.confirm",
    "camera.calibrate",
    "history.erase",
    "hue.pair",
    "hue.refresh",
    "hue.disconnect",
    "breathing.start",
    "breathing.volume",
    "breathing.stop",
    "remote_button.status",
    "remote_button.pairing.begin",
    "remote_button.pair",
    "remote_button.remove",
    "remote_button.dismiss",
    "device.factory_reset"
  ]

  def execute(%{"v" => @version, "id" => id, "op" => operation} = request)
      when is_binary(id) and is_binary(operation) do
    fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary(request, [:deterministic]))

    case CommandCache.execute(id, fingerprint, fn -> execute_versioned(request) end) do
      {:ok, response} -> response
      {:error, :request_id_reused} -> failure(id, :request_id_reused)
    end
  end

  def execute(%{"v" => @version, "op" => operation} = request) when is_binary(operation) do
    execute_versioned(request)
  end

  def execute(%{"v" => version} = request) when version != @version,
    do: failure(Map.get(request, "id"), :unsupported_version)

  # Kept during the prototype transition. New clients must use v/op/body.
  def execute(%{"action" => _action} = legacy), do: legacy |> migrate_legacy() |> execute()

  def execute(request) when is_map(request),
    do: failure(Map.get(request, "id"), :invalid_envelope)

  def execute(_request), do: failure(nil, :invalid_envelope)

  defp execute_versioned(%{"op" => operation} = request) do
    request_id = Map.get(request, "id")
    body = Map.get(request, "body", %{})

    case dispatch(operation, body) do
      {:ok, result} -> success(request_id, result)
      {:error, reason} -> failure(request_id, reason)
    end
  rescue
    _exception -> failure(Map.get(request, "id"), :internal_error)
  end

  defp dispatch("capabilities.get", _body) do
    {:ok,
     %{
       "contract_version" => @version,
       "security" => "remote-button-hmac-sha256-counter",
       "operations" => available_operations(),
       "response_transport" => "paged-read-v1"
     }}
  end

  defp dispatch("state.get", _body), do: {:ok, state_payload()}

  defp dispatch("alarm.create", body) when is_map(body) do
    with {:ok, alarm} <- Settings.create_alarm(body), do: {:ok, alarm_dto(alarm)}
  end

  defp dispatch("alarm.update", %{"alarm_id" => id, "alarm" => alarm})
       when is_binary(id) and is_map(alarm) do
    with {:ok, updated} <- Settings.update_alarm(id, alarm), do: {:ok, alarm_dto(updated)}
  end

  defp dispatch("alarm.delete", %{"alarm_id" => id, "revision" => revision})
       when is_binary(id) and is_integer(revision) do
    with :ok <- Settings.delete_alarm(id, revision), do: {:ok, %{"deleted" => id}}
  end

  defp dispatch("alarm.preview", body) when is_map(body) do
    with {:ok, alarm} <- Alarm.new(body) do
      {:ok,
       %{
         "next_occurrences" =>
           alarm |> Alarm.next_occurrences(5) |> Enum.map(&DateTime.to_iso8601/1)
       }}
    end
  end

  defp dispatch("alarm.trigger", %{"alarm_id" => id}) when is_binary(id) do
    with {:ok, _pid} <- Scheduler.trigger_now(id), do: {:ok, %{"state" => "starting"}}
  end

  defp dispatch("alarm.trigger_strong", %{"alarm_id" => id}) when is_binary(id) do
    with {:ok, _pid} <- Scheduler.trigger_strong_test(id),
         do: {:ok, %{"state" => "starting", "phase" => "strong"}}
  end

  defp dispatch("session.get", _body) do
    {:ok, %{"active_session" => session_dto(WakeSession.active())}}
  end

  defp dispatch("session.snooze", _body) do
    with {:ok, session} <- WakeSession.snooze(), do: {:ok, session_dto(session)}
  end

  defp dispatch("session.dismiss", _body) do
    with {:ok, session} <- WakeSession.dismiss(:smartphone), do: {:ok, session_dto(session)}
  end

  defp dispatch("settings.smartphone_dismiss.set", %{"enabled" => enabled})
       when is_boolean(enabled) do
    with {:ok, enabled} <- Settings.set_smartphone_dismiss_enabled(enabled),
         do: {:ok, smartphone_dismiss_dto(enabled, false)}
  end

  defp dispatch("clock.confirm", _body) do
    with {:ok, clock} <- ClockQuality.confirm(), do: {:ok, normalize(clock)}
  end

  defp dispatch("camera.calibrate", body) when is_map(body) do
    if camera_enabled?() do
      with {:ok, result} <- Camera.calibrate(body), do: {:ok, normalize(result)}
    else
      {:error, :capability_unavailable}
    end
  end

  defp dispatch("history.erase", _body) do
    with :ok <- Settings.erase_history(), do: {:ok, %{"erased" => true}}
  end

  defp dispatch("hue.pair", %{"bridge_host" => host}) when is_binary(host) do
    Hue.pair(host)
  end

  defp dispatch("hue.refresh", _body) do
    Hue.refresh()
  end

  defp dispatch("hue.disconnect", _body) do
    with :ok <- Hue.disconnect(), do: {:ok, %{"disconnected" => true}}
  end

  defp dispatch(
         "breathing.start",
         %{
           "target_id" => target_id,
           "duration_minutes" => duration_minutes
         } = body
       )
       when is_binary(target_id) and is_integer(duration_minutes) do
    Hue.start_breathing(target_id, duration_minutes, Map.get(body, "volume_percent", 60))
  end

  defp dispatch("breathing.volume", %{"volume_percent" => volume_percent})
       when is_integer(volume_percent),
       do: Hue.set_breathing_volume(volume_percent)

  defp dispatch("breathing.stop", _body), do: Hue.stop_breathing()

  defp dispatch("remote_button.status", _body), do: {:ok, RemoteButton.status()}

  defp dispatch("remote_button.pairing.begin", body) when is_map(body) do
    RemoteButton.begin_pairing(Map.get(body, "duration_seconds", 120))
  end

  defp dispatch("remote_button.pair", %{"button_id" => button_id, "name" => name})
       when is_binary(button_id) and is_binary(name),
       do: RemoteButton.pair(button_id, name)

  defp dispatch("remote_button.remove", %{"button_id" => button_id})
       when is_binary(button_id) do
    with :ok <- RemoteButton.remove(button_id), do: {:ok, %{removed: button_id}}
  end

  defp dispatch("remote_button.dismiss", body) when is_map(body),
    do: RemoteButton.dismiss(body)

  defp dispatch("device.factory_reset", %{"confirmation" => "RESET"}) do
    with :ok <- Settings.reset(),
         :ok <- RemoteButton.reset(),
         :ok <- Hue.reset(),
         :ok <- maybe_reset_camera(),
         :ok <- EventLog.clear(),
         :ok <- Auth.factory_reset() do
      {:ok, %{"factory_reset" => true}}
    end
  end

  defp dispatch(operation, _body) when operation in @operations, do: {:error, :invalid_body}
  defp dispatch(_operation, _body), do: {:error, :unsupported_operation}

  defp state_payload do
    health = Health.snapshot()
    active_session = WakeSession.active()

    %{
      "device" => device_dto(health),
      "alarms" => Enum.map(Settings.list_alarms(), &alarm_dto/1),
      "sounds" => Enum.map(SoundLibrary.list(), &sound_dto/1),
      "recent_sessions" => Enum.map(Settings.recent_sessions(8), &session_dto/1),
      "active_session" => session_dto(active_session),
      "smartphone_dismiss" =>
        smartphone_dismiss_dto(
          Settings.smartphone_dismiss_enabled(),
          Settings.smartphone_dismiss_locked?()
        ),
      "hue" => normalize(Hue.status()),
      "hue_targets" => normalize(Hue.targets()),
      "remote_button" => normalize(RemoteButton.status()),
      "lora" => normalize(LoRaServer.safe_status()),
      "transport" => transport_dto(health)
    }
  end

  defp smartphone_dismiss_dto(enabled, locked),
    do: %{"enabled" => enabled, "locked" => locked}

  defp transport_dto(health) do
    port = Application.get_env(:robine_wake, :web_port, 4000)

    endpoints =
      health
      |> nested([:network, :ipv4_addresses], [])
      |> Enum.map(&"http://#{&1}:#{port}/api/v1/command")

    %{
      "preferred" => "http",
      "http_endpoints" => endpoints,
      "fallback" => "bluetooth"
    }
  end

  defp device_dto(health) do
    %{
      "state" => text(health[:state]),
      "now" => health[:now],
      "target" => health[:target],
      "version" => health[:version],
      "clock_trusted" => nested(health, [:clock, :trusted], false),
      "camera" => %{
        "enabled" => camera_enabled?(),
        "state" => nested(health, [:camera, :driver_health, :state], :unavailable) |> text(),
        "calibrated" => nested(health, [:camera, :calibrated], false),
        "frames" => nested(health, [:camera, :frames], 0)
      },
      "audio" => %{
        "state" => nested(health, [:audio, :capabilities, :state], :unavailable) |> text()
      },
      "network" => %{"state" => nested(health, [:network, :state], :unavailable) |> text()},
      "firmware" => %{
        "version" => nested(health, [:firmware, :version], health[:version]),
        "validation" => nested(health, [:firmware, :validation], :unknown) |> text()
      },
      "updates" => %{
        "state" => nested(health, [:updates, :state], :unavailable) |> text(),
        "reason" => nested(health, [:updates, :reason], nil) |> text()
      }
    }
  end

  defp camera_enabled?, do: Application.get_env(:robine_wake, :camera_enabled, true)

  defp available_operations do
    if camera_enabled?(), do: @operations, else: List.delete(@operations, "camera.calibrate")
  end

  defp maybe_reset_camera do
    if camera_enabled?(), do: Camera.reset(), else: :ok
  end

  defp alarm_dto(%Alarm{} = alarm) do
    alarm
    |> Alarm.to_map()
    |> Map.put(
      "next_occurrences",
      if(alarm.enabled,
        do: alarm |> Alarm.next_occurrences(5) |> Enum.map(&DateTime.to_iso8601/1),
        else: []
      )
    )
  end

  defp sound_dto(sound),
    do: select(sound, [:id, :title, :artist, :duration_ms, :intensity, :source])

  defp session_dto(nil), do: nil

  defp session_dto(session) when is_map(session) do
    select(session, [
      :id,
      :alarm_id,
      :state,
      :terminal_reason,
      :created_at,
      :ended_at,
      :audio_phase,
      :current_gain,
      :snooze_count,
      :smartphone_dismiss_allowed,
      :test_mode,
      :occupancy,
      :confidence
    ])
    |> Map.update("test_mode", false, &(&1 in [true, "true"]))
  end

  defp select(map, keys) do
    Map.new(keys, fn key -> {Atom.to_string(key), fetch(map, key)} end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> normalize()
  end

  defp nested(value, [], default), do: if(is_nil(value), do: default, else: value)

  defp nested(map, [key | rest], default) when is_map(map),
    do: nested(fetch(map, key), rest, default)

  defp nested(_value, _path, default), do: default

  defp fetch(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp success(id, body),
    do: %{"v" => @version, "id" => id, "status" => "ok", "body" => normalize(body)}

  defp failure(id, reason) when is_map(reason), do: failure(id, "validation_failed", reason)
  defp failure(id, reason), do: failure(id, text(reason), nil)

  defp failure(id, code, details) do
    error = %{"code" => code}
    error = if details, do: Map.put(error, "details", normalize(details)), else: error
    %{"v" => @version, "id" => id, "status" => "error", "error" => error}
  end

  defp migrate_legacy(%{"action" => action} = legacy) do
    operation =
      %{
        "get_state" => "state.get",
        "create_alarm" => "alarm.create",
        "update_alarm" => "alarm.update",
        "delete_alarm" => "alarm.delete"
      }[action] || action

    body =
      case action do
        "create_alarm" -> Map.get(legacy, "payload", %{})
        "update_alarm" -> %{"alarm_id" => legacy["alarm_id"], "alarm" => legacy["payload"]}
        "delete_alarm" -> Map.take(legacy, ["alarm_id", "revision"])
        _ -> %{}
      end

    %{"v" => @version, "id" => legacy["id"], "op" => operation, "body" => body}
  end

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize(%Date{} = value), do: Date.to_iso8601(value)
  defp normalize(%Time{} = value), do: Time.to_iso8601(value)
  defp normalize(value) when is_boolean(value) or is_nil(value), do: value
  defp normalize(value) when is_atom(value), do: text(value)

  defp normalize(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), normalize(item)} end)

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value) when is_tuple(value), do: value |> Tuple.to_list() |> normalize()
  defp normalize(value), do: value

  defp text(nil), do: nil
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value), do: to_string(value)
end
