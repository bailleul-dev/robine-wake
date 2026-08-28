defmodule RobineWake.MCP do
  @moduledoc """
  Stateless Model Context Protocol server for Robine Wake.

  The HTTP transport is provided by `RobineWakeWeb.Router`. This module owns
  JSON-RPC dispatch, tool discovery, and the mapping to domain services.
  """

  alias RobineWake.{Alarm, Health, Scheduler, Settings, SoundLibrary, WakeSession}

  @protocol_version "2025-06-18"
  @supported_protocol_versions [@protocol_version, "2025-03-26"]
  @server_version Mix.Project.config()[:version]

  def protocol_version, do: @protocol_version
  def supported_protocol_versions, do: @supported_protocol_versions

  def handle(message, protocol_header \\ nil)

  def handle(%{"jsonrpc" => "2.0", "method" => method} = message, protocol_header)
      when is_binary(method) do
    case Map.fetch(message, "id") do
      {:ok, id} when is_binary(id) or is_integer(id) ->
        handle_request(message, protocol_header)

      {:ok, _invalid_id} ->
        {:response, 400, error_response(nil, -32_600, "Invalid Request")}

      :error ->
        case validate_protocol(protocol_header) do
          :ok ->
            {:accepted, 202}

          {:protocol_error, code, error_message, data} ->
            {:response, 400, error_response(nil, code, error_message, data)}
        end
    end
  end

  def handle(message, _protocol_header) do
    {:response, 400, error_response(request_id(message), -32_600, "Invalid Request")}
  end

  def tools do
    alarm_properties = %{
      "label" => %{"type" => "string", "maxLength" => 80},
      "enabled" => %{"type" => "boolean"},
      "local_time" => %{"type" => "string", "description" => "Local time as HH:MM"},
      "days_of_week" => %{
        "type" => "array",
        "items" => %{"type" => "integer", "minimum" => 1, "maximum" => 7},
        "uniqueItems" => true
      },
      "one_shot_date" => %{
        "type" => ["string", "null"],
        "description" => "Optional ISO 8601 date (YYYY-MM-DD)"
      },
      "timezone" => %{"type" => "string", "description" => "IANA time zone"},
      "sound_id" => %{"type" => "string"},
      "strong_sound_id" => %{"type" => "string"},
      "prewake_seconds" => %{"type" => "integer", "minimum" => 0, "maximum" => 3600},
      "volume_profile" => %{
        "type" => "object",
        "properties" => %{
          "start" => %{"type" => "integer", "minimum" => 0},
          "ceiling" => %{"type" => "integer", "minimum" => 0},
          "ramp_seconds" => %{"type" => "integer", "minimum" => 0, "maximum" => 3600}
        },
        "additionalProperties" => false
      },
      "light_profile" => %{
        "type" => "object",
        "properties" => %{
          "enabled" => %{"type" => "boolean"},
          "target_id" => %{"type" => ["string", "null"]},
          "target_name" => %{"type" => ["string", "null"]},
          "start_brightness" => %{"type" => "integer", "minimum" => 1, "maximum" => 100},
          "end_brightness" => %{"type" => "integer", "minimum" => 1, "maximum" => 100},
          "ramp_seconds" => %{"type" => "integer", "minimum" => 0, "maximum" => 3600},
          "end_behavior" => %{"type" => "string", "enum" => ["restore", "off", "leave"]}
        },
        "additionalProperties" => false
      },
      "dismiss_policy" => %{"type" => "string", "enum" => ["manual", "bed_exit", "either"]},
      "snooze" => %{
        "type" => "object",
        "properties" => %{
          "enabled" => %{"type" => "boolean"},
          "duration_seconds" => %{"type" => "integer", "minimum" => 60, "maximum" => 1800},
          "maximum" => %{"type" => "integer", "minimum" => 0, "maximum" => 10}
        },
        "additionalProperties" => false
      }
    }

    read_only = %{
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "idempotentHint" => true,
      "openWorldHint" => false
    }

    [
      tool(
        "get_state",
        "Get Device State",
        "Read device health, alarms, recent sessions, and the active wake session.",
        %{},
        read_only
      ),
      tool(
        "list_alarms",
        "List Alarms",
        "List configured alarms and their next five occurrences.",
        %{},
        read_only
      ),
      tool(
        "list_sounds",
        "List Sounds",
        "List validated sounds available on this device.",
        %{},
        read_only
      ),
      tool(
        "preview_alarm",
        "Preview Alarm",
        "Validate an alarm without saving it and return its next five occurrences.",
        alarm_properties,
        read_only,
        ["local_time"]
      ),
      tool(
        "create_alarm",
        "Create Alarm",
        "Create and persist an alarm. Use list_sounds first to select valid sound IDs.",
        alarm_properties,
        write_annotations(false),
        ["local_time"]
      ),
      tool(
        "update_alarm",
        "Update Alarm",
        "Update an alarm using its current revision for conflict protection.",
        Map.merge(alarm_properties, %{
          "id" => %{"type" => "string"},
          "revision" => %{"type" => "integer", "minimum" => 1}
        }),
        write_annotations(false),
        ["id", "revision"]
      ),
      tool(
        "delete_alarm",
        "Delete Alarm",
        "Permanently delete an alarm using its current revision.",
        %{
          "id" => %{"type" => "string"},
          "revision" => %{"type" => "integer", "minimum" => 1}
        },
        write_annotations(true),
        ["id", "revision"]
      ),
      tool(
        "trigger_alarm",
        "Trigger Alarm",
        "Start a configured alarm immediately.",
        %{"id" => %{"type" => "string"}},
        write_annotations(false),
        ["id"]
      ),
      tool(
        "snooze_session",
        "Snooze Session",
        "Snooze the active wake session.",
        %{},
        write_annotations(false)
      ),
      tool(
        "dismiss_session",
        "Dismiss Session",
        "Stop and dismiss the active wake session.",
        %{},
        write_annotations(false)
      )
    ]
  end

  defp handle_request(
         %{"id" => id, "method" => "initialize", "params" => %{"protocolVersion" => requested}},
         _header
       )
       when is_binary(requested) do
    negotiated =
      if requested in @supported_protocol_versions, do: requested, else: @protocol_version

    result = %{
      "protocolVersion" => negotiated,
      "capabilities" => %{"tools" => %{"listChanged" => false}},
      "serverInfo" => %{
        "name" => "robine-wake",
        "title" => "Robine Wake",
        "version" => @server_version
      },
      "instructions" =>
        "Control the local Robine Wake alarm clock. Read current state before writes and preserve alarm revisions when updating or deleting."
    }

    {:response, 200, success_response(id, result)}
  end

  defp handle_request(%{"id" => id, "method" => "initialize"}, _header),
    do: {:response, 200, error_response(id, -32_602, "Invalid initialize parameters")}

  defp handle_request(%{"id" => id} = message, protocol_header) do
    with :ok <- validate_protocol(protocol_header),
         {:ok, result} <- dispatch(message) do
      {:response, 200, success_response(id, result)}
    else
      {:protocol_error, code, message, data} ->
        {:response, 400, error_response(id, code, message, data)}

      {:error, code, message} ->
        {:response, 200, error_response(id, code, message)}
    end
  end

  defp dispatch(%{"method" => "ping"}), do: {:ok, %{}}
  defp dispatch(%{"method" => "tools/list"}), do: {:ok, %{"tools" => tools()}}

  defp dispatch(%{"method" => "tools/call", "params" => %{"name" => name} = params})
       when is_binary(name) do
    arguments = Map.get(params, "arguments", %{})

    with %{} = definition <- Enum.find(tools(), &(&1["name"] == name)),
         :ok <- validate_arguments(arguments, definition["inputSchema"]) do
      {:ok, call_tool(name, arguments)}
    else
      nil -> {:error, -32_602, "Unknown tool: #{name}"}
      {:error, details} -> {:error, -32_602, "Invalid tool arguments: #{details}"}
    end
  end

  defp dispatch(%{"method" => "tools/call"}),
    do: {:error, -32_602, "Invalid tool call parameters"}

  defp dispatch(%{"method" => _method}), do: {:error, -32_601, "Method not found"}

  defp call_tool("get_state", _arguments) do
    tool_success(%{
      "health" => normalize(Health.snapshot()),
      "alarms" => Enum.map(Settings.list_alarms(), &alarm_json/1),
      "recent_sessions" => normalize(Settings.recent_sessions()),
      "active_session" => normalize(WakeSession.active())
    })
  end

  defp call_tool("list_alarms", _arguments),
    do: tool_success(%{"alarms" => Enum.map(Settings.list_alarms(), &alarm_json/1)})

  defp call_tool("list_sounds", _arguments),
    do: tool_success(%{"sounds" => normalize(SoundLibrary.list())})

  defp call_tool("preview_alarm", arguments) do
    case Alarm.new(arguments) do
      {:ok, alarm} -> tool_success(%{"alarm" => alarm_json(alarm)})
      {:error, reason} -> tool_error(reason)
    end
  end

  defp call_tool("create_alarm", arguments) do
    case Settings.create_alarm(arguments) do
      {:ok, alarm} -> tool_success(%{"alarm" => alarm_json(alarm)})
      {:error, reason} -> tool_error(reason)
    end
  end

  defp call_tool("update_alarm", %{"id" => id, "revision" => _revision} = arguments) do
    case Settings.update_alarm(id, Map.delete(arguments, "id")) do
      {:ok, alarm} -> tool_success(%{"alarm" => alarm_json(alarm)})
      {:error, reason} -> tool_error(reason)
    end
  end

  defp call_tool("update_alarm", _arguments), do: tool_error(:id_and_revision_required)

  defp call_tool("delete_alarm", %{"id" => id, "revision" => revision}) do
    case Settings.delete_alarm(id, revision) do
      :ok -> tool_success(%{"deleted" => true, "id" => id})
      {:error, reason} -> tool_error(reason)
    end
  end

  defp call_tool("delete_alarm", _arguments), do: tool_error(:id_and_revision_required)

  defp call_tool("trigger_alarm", %{"id" => id}) do
    case Scheduler.trigger_now(id) do
      {:ok, _pid} -> tool_success(%{"state" => "starting", "alarm_id" => id})
      {:error, reason} -> tool_error(reason)
    end
  end

  defp call_tool("trigger_alarm", _arguments), do: tool_error(:id_required)

  defp call_tool("snooze_session", _arguments) do
    case WakeSession.snooze() do
      {:ok, session} -> tool_success(%{"session" => normalize(session)})
      {:error, reason} -> tool_error(reason)
    end
  end

  defp call_tool("dismiss_session", _arguments) do
    case WakeSession.dismiss(:mcp) do
      {:ok, session} -> tool_success(%{"session" => normalize(session)})
      {:error, reason} -> tool_error(reason)
    end
  end

  defp call_tool(_name, _arguments), do: tool_error(:unknown_tool)

  defp validate_arguments(arguments, %{"type" => "object"} = schema)
       when is_map(arguments) do
    required = Map.get(schema, "required", [])
    properties = Map.get(schema, "properties", %{})
    missing = Enum.reject(required, &Map.has_key?(arguments, &1))
    unknown = Map.keys(arguments) -- Map.keys(properties)

    cond do
      missing != [] ->
        {:error, "missing required properties: #{Enum.join(missing, ", ")}"}

      schema["additionalProperties"] == false and unknown != [] ->
        {:error, "unknown properties: #{Enum.join(unknown, ", ")}"}

      true ->
        Enum.reduce_while(arguments, :ok, &validate_argument(&1, &2, properties))
    end
  end

  defp validate_arguments(_arguments, _schema), do: {:error, "arguments must be an object"}

  defp validate_argument({key, value}, :ok, properties) do
    case properties[key] do
      nil -> {:cont, :ok}
      property -> validate_property(key, value, property)
    end
  end

  defp validate_property(key, value, %{"type" => types} = schema) when is_list(types) do
    if Enum.any?(types, &matches_type?(value, &1)),
      do: validate_constraints(key, value, schema),
      else: {:halt, {:error, "#{key} has an invalid type"}}
  end

  defp validate_property(key, value, %{"type" => type} = schema) do
    if matches_type?(value, type),
      do: validate_constraints(key, value, schema),
      else: {:halt, {:error, "#{key} must be #{type}"}}
  end

  defp validate_constraints(key, value, schema) do
    validators = [
      &validate_enum/3,
      &validate_max_length/3,
      &validate_minimum/3,
      &validate_maximum/3,
      &validate_uniqueness/3
    ]

    case Enum.find_value(validators, & &1.(key, value, schema)) do
      nil -> validate_nested_constraints(key, value, schema)
      message -> {:halt, {:error, message}}
    end
  end

  defp validate_enum(key, value, %{"enum" => choices}) when is_list(choices) do
    if value in choices, do: nil, else: "#{key} is not an allowed value"
  end

  defp validate_enum(_key, _value, _schema), do: nil

  defp validate_max_length(key, value, %{"maxLength" => maximum})
       when is_binary(value) and is_integer(maximum) do
    if String.length(value) > maximum, do: "#{key} is too long"
  end

  defp validate_max_length(_key, _value, _schema), do: nil

  defp validate_minimum(key, value, %{"minimum" => minimum})
       when is_number(value) and is_number(minimum) do
    if value < minimum, do: "#{key} is below its minimum"
  end

  defp validate_minimum(_key, _value, _schema), do: nil

  defp validate_maximum(key, value, %{"maximum" => maximum})
       when is_number(value) and is_number(maximum) do
    if value > maximum, do: "#{key} is above its maximum"
  end

  defp validate_maximum(_key, _value, _schema), do: nil

  defp validate_uniqueness(key, value, %{"uniqueItems" => true}) when is_list(value) do
    if Enum.uniq(value) != value, do: "#{key} must contain unique values"
  end

  defp validate_uniqueness(_key, _value, _schema), do: nil

  defp validate_nested_constraints(key, value, %{"items" => item_schema})
       when is_list(value) and is_map(item_schema),
       do: validate_array_items(key, value, item_schema)

  defp validate_nested_constraints(key, value, %{"type" => "object"} = schema)
       when is_map(value) do
    case validate_arguments(value, schema) do
      :ok -> {:cont, :ok}
      {:error, details} -> {:halt, {:error, "#{key}.#{details}"}}
    end
  end

  defp validate_nested_constraints(_key, _value, _schema), do: {:cont, :ok}

  defp validate_array_items(key, values, item_schema) do
    Enum.reduce_while(values, {:cont, :ok}, fn value, _acc ->
      case validate_property(key, value, item_schema) do
        {:cont, :ok} -> {:cont, {:cont, :ok}}
        {:halt, error} -> {:halt, {:halt, error}}
      end
    end)
  end

  defp matches_type?(value, "string"), do: is_binary(value)
  defp matches_type?(value, "integer"), do: is_integer(value)
  defp matches_type?(value, "number"), do: is_number(value)
  defp matches_type?(value, "boolean"), do: is_boolean(value)
  defp matches_type?(value, "array"), do: is_list(value)
  defp matches_type?(value, "object"), do: is_map(value)
  defp matches_type?(value, "null"), do: is_nil(value)
  defp matches_type?(_value, _type), do: false

  defp validate_protocol(nil), do: :ok
  defp validate_protocol(version) when version in @supported_protocol_versions, do: :ok

  defp validate_protocol(version) do
    {:protocol_error, -32_602, "Unsupported protocol version",
     %{
       "supported" => @supported_protocol_versions,
       "requested" => version
     }}
  end

  defp tool(name, title, description, properties, annotations, required \\ []) do
    %{
      "name" => name,
      "title" => title,
      "description" => description,
      "inputSchema" => %{
        "type" => "object",
        "properties" => properties,
        "required" => required,
        "additionalProperties" => false
      },
      "annotations" => annotations
    }
  end

  defp write_annotations(destructive) do
    %{
      "readOnlyHint" => false,
      "destructiveHint" => destructive,
      "idempotentHint" => false,
      "openWorldHint" => false
    }
  end

  defp tool_success(data) do
    normalized = normalize(data)

    %{
      "content" => [%{"type" => "text", "text" => Jason.encode!(normalized, pretty: true)}],
      "structuredContent" => normalized
    }
  end

  defp tool_error(reason) do
    details = normalize(reason)
    data = %{"error" => %{"code" => error_code(reason), "details" => details}}
    Map.put(tool_success(data), "isError", true)
  end

  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code(reason) when is_map(reason), do: "validation_failed"
  defp error_code(_reason), do: "internal_error"

  defp alarm_json(%Alarm{} = alarm) do
    occurrences =
      if alarm.enabled,
        do: Enum.map(Alarm.next_occurrences(alarm, 5), &DateTime.to_iso8601/1),
        else: []

    Map.put(Alarm.to_map(alarm), "next_occurrences", occurrences)
  end

  defp success_response(id, result), do: %{"jsonrpc" => "2.0", "id" => id, "result" => result}

  defp error_response(id, code, message, data \\ nil) do
    error = %{"code" => code, "message" => message}
    error = if is_nil(data), do: error, else: Map.put(error, "data", data)
    %{"jsonrpc" => "2.0", "id" => id, "error" => error}
  end

  defp request_id(message) when is_map(message), do: Map.get(message, "id")
  defp request_id(_message), do: nil

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize(%Date{} = value), do: Date.to_iso8601(value)
  defp normalize(%Time{} = value), do: Time.to_iso8601(value)
  defp normalize(%_{} = value), do: value |> Map.from_struct() |> normalize()

  defp normalize(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), normalize(item)} end)

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value) when is_tuple(value), do: value |> Tuple.to_list() |> normalize()
  defp normalize(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp normalize(value), do: value
end
