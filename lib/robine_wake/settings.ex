defmodule RobineWake.Settings do
  @moduledoc false
  use GenServer

  require Logger
  alias RobineWake.{Alarm, Clock, Id, Persistence, SoundLibrary}

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def list_alarms, do: GenServer.call(__MODULE__, :list_alarms)
  def get_alarm(id), do: GenServer.call(__MODULE__, {:get_alarm, id})
  def create_alarm(attrs), do: GenServer.call(__MODULE__, {:create_alarm, attrs})
  def update_alarm(id, attrs), do: GenServer.call(__MODULE__, {:update_alarm, id, attrs})
  def delete_alarm(id, revision), do: GenServer.call(__MODULE__, {:delete_alarm, id, revision})
  def record_session(attrs), do: GenServer.call(__MODULE__, {:record_session, attrs})

  def record_missed_if_current(alarm_id, revision, scheduled_for, reason),
    do:
      GenServer.call(
        __MODULE__,
        {:record_missed_if_current, alarm_id, revision, scheduled_for, reason}
      )

  def update_session(id, attrs), do: GenServer.call(__MODULE__, {:update_session, id, attrs})

  def session_recorded?(alarm_id, scheduled_for),
    do: GenServer.call(__MODULE__, {:session_recorded?, alarm_id, scheduled_for})

  def recent_sessions(limit \\ 20), do: GenServer.call(__MODULE__, {:recent_sessions, limit})
  def erase_history, do: GenServer.call(__MODULE__, :erase_history)
  def export_configuration, do: GenServer.call(__MODULE__, :export_configuration)
  def smartphone_dismiss_enabled, do: GenServer.call(__MODULE__, :smartphone_dismiss_enabled)

  def remote_dismiss_enabled?,
    do: Application.get_env(:robine_wake, :remote_dismiss_enabled, false)

  def smartphone_dismiss_locked?,
    do: not remote_dismiss_enabled?() or not is_nil(RobineWake.WakeSession.active())

  def set_smartphone_dismiss_enabled(enabled) when is_boolean(enabled) do
    if smartphone_dismiss_locked?() do
      {:error, :smartphone_dismiss_setting_locked}
    else
      GenServer.call(__MODULE__, {:set_smartphone_dismiss_enabled, enabled})
    end
  end

  def set_smartphone_dismiss_enabled(_enabled),
    do: {:error, %{smartphone_dismiss_enabled: "must be a boolean"}}

  def detection_profile, do: GenServer.call(__MODULE__, :detection_profile)
  def remote_buttons, do: GenServer.call(__MODULE__, :remote_buttons)

  def put_remote_button(id, name, secret),
    do: GenServer.call(__MODULE__, {:put_remote_button, id, name, secret})

  def authorize_remote_button(id, counter, mac),
    do: GenServer.call(__MODULE__, {:authorize_remote_button, id, counter, mac})

  def remove_remote_button(id), do: GenServer.call(__MODULE__, {:remove_remote_button, id})

  def put_detection_profile(profile),
    do: GenServer.call(__MODULE__, {:put_detection_profile, profile})

  def snapshot, do: GenServer.call(__MODULE__, :snapshot)
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(_opts) do
    path = Application.fetch_env!(:robine_wake, :data_path)

    state =
      case Persistence.load(path) do
        {:ok, data} ->
          decode(data, path)

        {:error, reason} ->
          Logger.error("Settings storage could not be read: #{inspect(reason)}")

          %{
            path: path,
            alarms: %{},
            sessions: [],
            settings: %{},
            created_at: DateTime.to_iso8601(Clock.utc_now()),
            degraded: reason
          }
      end

    state = purge_sessions(state)
    schedule_purge()
    {:ok, state}
  end

  @impl true
  def handle_call(:list_alarms, _from, state), do: {:reply, sorted_alarms(state), state}

  def handle_call({:get_alarm, id}, _from, state) do
    case Map.fetch(state.alarms, id) do
      {:ok, alarm} -> {:reply, {:ok, alarm}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:create_alarm, attrs}, _from, state) do
    with {:ok, alarm} <- Alarm.new(attrs),
         :ok <- validate_sound(alarm),
         false <- Map.has_key?(state.alarms, alarm.id),
         new_state = %{state | alarms: Map.put(state.alarms, alarm.id, alarm)},
         :ok <- persist(new_state) do
      notify_scheduler()
      {:reply, {:ok, alarm}, new_state}
    else
      true -> {:reply, {:error, :already_exists}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:update_alarm, id, attrs}, _from, state) do
    with {:ok, current} <- fetch_alarm(state, id),
         :ok <- check_revision(current, attrs),
         merged <- current |> Alarm.to_map() |> Map.merge(stringify_keys(attrs)),
         {:ok, alarm} <- Alarm.new(Map.put(merged, "revision", current.revision + 1)),
         :ok <- validate_sound(alarm),
         new_state = %{state | alarms: Map.put(state.alarms, id, alarm)},
         :ok <- persist(new_state) do
      notify_scheduler()
      {:reply, {:ok, alarm}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete_alarm, id, revision}, _from, state) do
    with {:ok, alarm} <- fetch_alarm(state, id),
         :ok <- check_revision(alarm, %{revision: revision}) do
      delete_alarm_from_state(id, state)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:record_session, attrs}, _from, state) do
    session = normalize_session(attrs)
    new_state = %{state | sessions: [session | state.sessions] |> Enum.take(500)}

    case persist(new_state) do
      :ok -> {:reply, {:ok, session}, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:record_missed_if_current, alarm_id, revision, scheduled_for, reason},
        _from,
        state
      ) do
    scheduled_iso = iso8601(scheduled_for)

    cond do
      not match?(%Alarm{revision: ^revision, enabled: true}, state.alarms[alarm_id]) ->
        {:reply, :stale, state}

      Enum.any?(state.sessions, fn session ->
        session["alarm_id"] == alarm_id and session["scheduled_for"] == scheduled_iso
      end) ->
        {:reply, :already_recorded, state}

      true ->
        session =
          normalize_session(%{
            id: Id.generate(),
            alarm_id: alarm_id,
            scheduled_for: scheduled_for,
            state: :missed,
            terminal_reason: reason,
            ended_at: Clock.utc_now()
          })

        next = %{state | sessions: [session | state.sessions] |> Enum.take(500)}

        case persist(next) do
          :ok -> {:reply, :recorded, next}
          {:error, persist_reason} -> {:reply, {:error, persist_reason}, state}
        end
    end
  end

  def handle_call({:update_session, id, attrs}, _from, state) do
    {sessions, found} =
      Enum.map_reduce(state.sessions, false, fn session, found ->
        if session["id"] == id do
          {Map.merge(session, stringify_keys(attrs)), true}
        else
          {session, found}
        end
      end)

    if found do
      new_state = %{state | sessions: sessions}

      case persist(new_state) do
        :ok -> {:reply, :ok, new_state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:session_recorded?, alarm_id, scheduled_for}, _from, state) do
    iso = iso8601(scheduled_for)

    result =
      Enum.any?(state.sessions, &(&1["alarm_id"] == alarm_id and &1["scheduled_for"] == iso))

    {:reply, result, state}
  end

  def handle_call({:recent_sessions, limit}, _from, state),
    do: {:reply, Enum.take(state.sessions, limit), state}

  def handle_call(:erase_history, _from, state) do
    next = %{state | sessions: []}

    case persist(next) do
      :ok -> {:reply, :ok, next}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:export_configuration, _from, state) do
    export = %{
      format: "robine-wake-configuration",
      format_version: 1,
      exported_at: DateTime.to_iso8601(Clock.utc_now()),
      alarms: state |> sorted_alarms() |> Enum.map(&Alarm.to_map/1),
      detection_profile: state.settings["detection_profile"],
      smartphone_dismiss_enabled: smartphone_dismiss_enabled(state)
    }

    {:reply, export, state}
  end

  def handle_call(:smartphone_dismiss_enabled, _from, state),
    do: {:reply, smartphone_dismiss_enabled(state), state}

  def handle_call({:set_smartphone_dismiss_enabled, enabled}, _from, state) do
    next = %{state | settings: Map.put(state.settings, "smartphone_dismiss_enabled", enabled)}

    case persist(next) do
      :ok ->
        notify_scheduler()
        {:reply, {:ok, enabled}, next}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:detection_profile, _from, state),
    do: {:reply, state.settings["detection_profile"], state}

  def handle_call(:remote_buttons, _from, state) do
    buttons =
      state.settings
      |> Map.get("remote_buttons", %{})
      |> Map.values()
      |> Enum.map(&Map.drop(&1, ["secret_hex"]))
      |> Enum.sort_by(&{&1["name"], &1["id"]})

    {:reply, buttons, state}
  end

  def handle_call({:put_remote_button, id, name, secret}, _from, state)
      when is_binary(id) and is_binary(name) and is_binary(secret) and byte_size(secret) == 32 do
    button = %{
      "id" => id,
      "name" => String.trim(name),
      "secret_hex" => Base.encode16(secret, case: :lower),
      "last_counter" => 0,
      "paired_at" => DateTime.to_iso8601(Clock.utc_now()),
      "last_seen_at" => nil
    }

    buttons = state.settings |> Map.get("remote_buttons", %{}) |> Map.put(id, button)
    next = %{state | settings: Map.put(state.settings, "remote_buttons", buttons)}

    case persist(next) do
      :ok -> {:reply, :ok, next}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:authorize_remote_button, id, counter, mac}, _from, state) do
    buttons = Map.get(state.settings, "remote_buttons", %{})

    result =
      with {:ok, button} <- Map.fetch(buttons, id),
           {:ok, secret} <- Base.decode16(button["secret_hex"] || "", case: :mixed),
           expected <- RobineWake.RemoteButton.mac(secret, id, counter),
           true <- Plug.Crypto.secure_compare(expected, String.downcase(mac)) do
        authorize_remote_counter(state, buttons, button, counter)
      else
        :error -> {:error, :remote_button_not_paired}
        false -> {:error, :invalid_remote_button_signature}
        {:error, _reason} -> {:error, :invalid_remote_button_secret}
      end

    case result do
      {:ok, freshness, next} -> {:reply, {:ok, freshness}, next}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:remove_remote_button, id}, _from, state) do
    buttons = Map.get(state.settings, "remote_buttons", %{})

    if Map.has_key?(buttons, id) do
      next_buttons = Map.delete(buttons, id)
      next = %{state | settings: Map.put(state.settings, "remote_buttons", next_buttons)}

      case persist(next) do
        :ok -> {:reply, :ok, next}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :remote_button_not_paired}, state}
    end
  end

  def handle_call({:put_detection_profile, profile}, _from, state) do
    settings = Map.put(state.settings, "detection_profile", normalize(profile))
    next = %{state | settings: settings}

    case persist(next) do
      :ok -> {:reply, :ok, next}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:snapshot, _from, state) do
    {:reply,
     %{
       alarms: sorted_alarms(state),
       sessions: Enum.take(state.sessions, 20),
       remote_buttons: state.settings |> Map.get("remote_buttons", %{}) |> map_size(),
       smartphone_dismiss_enabled: smartphone_dismiss_enabled(state),
       degraded: state[:degraded]
     }, state}
  end

  def handle_call(:reset, _from, state) do
    next = %{state | alarms: %{}, sessions: [], settings: %{}, degraded: nil}

    case persist(next) do
      :ok ->
        notify_scheduler()
        {:reply, :ok, next}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:purge, state) do
    next = purge_sessions(state)
    if next.sessions != state.sessions, do: persist(next)
    schedule_purge()
    {:noreply, next}
  end

  defp decode(data, path) do
    alarms =
      data
      |> Map.get("alarms", [])
      |> Enum.reduce(%{}, fn raw, acc ->
        case Alarm.new(raw) do
          {:ok, alarm} -> Map.put(acc, alarm.id, alarm)
          _ -> acc
        end
      end)

    %{
      path: path,
      alarms: alarms,
      sessions: Map.get(data, "sessions", []),
      # The Philips Hue bridge and its application key are gone with Hue.
      settings: data |> Map.get("settings", %{}) |> Map.delete("hue_bridge"),
      created_at: Map.get(data, "created_at", DateTime.to_iso8601(Clock.utc_now())),
      degraded: nil
    }
  end

  defp persist(state) do
    data = %{
      "schema_version" => 1,
      "created_at" => state.created_at,
      "alarms" => state |> sorted_alarms() |> Enum.map(&Alarm.to_map/1),
      "sessions" => state.sessions,
      "settings" => state.settings,
      "updated_at" => DateTime.to_iso8601(Clock.utc_now())
    }

    Persistence.save(state.path, data)
  end

  defp sorted_alarms(state),
    do: state.alarms |> Map.values() |> Enum.sort_by(&{&1.local_time, &1.id})

  defp smartphone_dismiss_enabled(state),
    do: remote_dismiss_enabled?() and Map.get(state.settings, "smartphone_dismiss_enabled", true)

  defp fetch_alarm(state, id) do
    case Map.fetch(state.alarms, id) do
      {:ok, alarm} -> {:ok, alarm}
      :error -> {:error, :not_found}
    end
  end

  defp delete_alarm_from_state(id, state) do
    new_state = %{state | alarms: Map.delete(state.alarms, id)}

    case persist(new_state) do
      :ok ->
        notify_scheduler()
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp check_revision(current, attrs) do
    requested = Map.get(attrs, :revision, Map.get(attrs, "revision"))

    if requested == current.revision,
      do: :ok,
      else: {:error, :revision_conflict}
  end

  defp authorize_remote_counter(state, buttons, button, counter) do
    previous = button["last_counter"] || 0

    cond do
      counter < previous ->
        {:error, :remote_button_replay}

      counter == previous and previous > 0 ->
        {:ok, :duplicate, state}

      true ->
        updated = %{
          button
          | "last_counter" => counter,
            "last_seen_at" => DateTime.to_iso8601(Clock.utc_now())
        }

        next_buttons = Map.put(buttons, button["id"], updated)
        next = %{state | settings: Map.put(state.settings, "remote_buttons", next_buttons)}

        case persist(next) do
          :ok -> {:ok, :fresh, next}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp validate_sound(alarm) do
    cond do
      not SoundLibrary.available?(alarm.sound_id) ->
        {:error, %{sound_id: "does not reference an available validated sound"}}

      not SoundLibrary.available?(alarm.strong_sound_id) ->
        {:error, %{strong_sound_id: "does not reference an available validated sound"}}

      true ->
        :ok
    end
  end

  defp normalize_session(attrs) do
    attrs
    |> stringify_keys()
    |> Map.put_new("created_at", DateTime.to_iso8601(Clock.utc_now()))
  end

  defp stringify_keys(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)

  defp normalize(%DateTime{} = value), do: utc_iso8601(value)
  defp normalize(value) when is_map(value), do: stringify_keys(value)
  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(nil), do: nil
  defp normalize(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize(value), do: value
  defp iso8601(%DateTime{} = value), do: utc_iso8601(value)

  defp iso8601(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> utc_iso8601(datetime)
      _ -> value
    end
  end

  defp utc_iso8601(value),
    do: value |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_iso8601()

  defp notify_scheduler do
    if Process.whereis(RobineWake.Scheduler), do: send(RobineWake.Scheduler, :settings_changed)

    if Process.whereis(RobineWake.EventStream),
      do: RobineWake.EventStream.publish("state.changed")
  end

  defp purge_sessions(state) do
    retention_days = Application.fetch_env!(:robine_wake, :session_retention_days)
    cutoff = DateTime.add(Clock.utc_now(), -retention_days, :day)

    sessions =
      Enum.filter(state.sessions, fn session ->
        case DateTime.from_iso8601(session["ended_at"] || session["created_at"] || "") do
          {:ok, timestamp, _offset} -> DateTime.compare(timestamp, cutoff) != :lt
          _ -> true
        end
      end)

    %{state | sessions: sessions}
  end

  defp schedule_purge, do: Process.send_after(self(), :purge, :timer.hours(24))
end
