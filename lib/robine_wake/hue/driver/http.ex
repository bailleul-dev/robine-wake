defmodule RobineWake.Hue.Driver.HTTP do
  @moduledoc "HTTPS client for the Philips Hue Bridge local API v2."

  @behaviour RobineWake.Hue.Driver

  @impl true
  def pair(host) when is_binary(host) do
    body = %{"devicetype" => "robine_wake#alarm_clock", "generateclientkey" => true}

    with {:ok, result} <- request(:post, host, "/api", nil, body),
         {:ok, credentials} <- pairing_credentials(result) do
      {:ok,
       %{
         "host" => host,
         "application_key" => credentials["username"],
         "client_key" => credentials["clientkey"]
       }}
    end
  end

  @impl true
  def targets(config) do
    rooms = get_resources(config, "room")
    zones = get_resources(config, "zone")

    case {rooms, zones} do
      {{:error, room_reason}, {:error, _zone_reason}} ->
        {:error, room_reason}

      _at_least_one_collection_available ->
        targets =
          (available_target_resources(rooms, "room") ++
             available_target_resources(zones, "zone"))
          |> Enum.uniq_by(& &1["id"])
          |> Enum.sort_by(&{&1["kind"], String.downcase(&1["name"])})

        {:ok, targets}
    end
  end

  @impl true
  def get_target(config, id) do
    case request(:get, config["host"], "/clip/v2/resource/grouped_light/#{id}", config) do
      {:ok, %{"data" => [target | _]}} -> {:ok, target}
      {:ok, _} -> {:error, :hue_target_not_found}
      error -> error
    end
  end

  @impl true
  def set_target(config, id, changes) do
    path = "/clip/v2/resource/grouped_light/#{id}"
    set_target_with_fallback(path, config, changes, ["color_temperature", "color"])
  end

  defp set_target_with_fallback(path, config, changes, fallback_keys) do
    case request(:put, config["host"], path, config, changes) do
      {:ok, _} ->
        :ok

      {:error, _reason} = error ->
        case Enum.find(fallback_keys, &Map.has_key?(changes, &1)) do
          nil ->
            error

          unsupported_key ->
            set_target_with_fallback(
              path,
              config,
              Map.delete(changes, unsupported_key),
              List.delete(fallback_keys, unsupported_key)
            )
        end
    end
  end

  defp get_resources(config, type) do
    case request(:get, config["host"], "/clip/v2/resource/#{type}", config) do
      {:ok, %{"data" => resources}} when is_list(resources) -> {:ok, resources}
      {:ok, _} -> {:error, :invalid_hue_response}
      error -> error
    end
  end

  defp target_resources(resources, kind) do
    Enum.flat_map(resources, fn resource ->
      name = get_in(resource, ["metadata", "name"]) || String.capitalize(kind)

      resource
      |> Map.get("services", [])
      |> Enum.filter(&(&1["rtype"] == "grouped_light"))
      |> Enum.map(&%{"id" => &1["rid"], "name" => name, "kind" => kind})
    end)
  end

  defp available_target_resources({:ok, resources}, kind), do: target_resources(resources, kind)
  defp available_target_resources({:error, _reason}, _kind), do: []

  defp pairing_credentials(result) when is_list(result) do
    case Enum.find_value(result, fn item -> item["success"] end) do
      %{"username" => username} = credentials when is_binary(username) ->
        {:ok, credentials}

      _ ->
        pairing_error(result)
    end
  end

  defp pairing_credentials(_), do: {:error, :invalid_hue_response}

  defp pairing_error(result) do
    case Enum.find_value(result, fn item -> get_in(item, ["error", "type"]) end) do
      101 -> {:error, :hue_link_button_required}
      _other -> {:error, :hue_pairing_failed}
    end
  end

  defp request(method, host, path, config, body \\ nil) do
    timeout = Application.get_env(:robine_wake, :hue_request_timeout_ms, 5_000)
    url = ~c"https://#{host}#{path}"
    headers = request_headers(config)
    http_options = [timeout: timeout, connect_timeout: timeout, ssl: [verify: :verify_none]]
    options = [body_format: :binary]

    request =
      if body do
        {url, headers, ~c"application/json", Jason.encode!(body)}
      else
        {url, headers}
      end

    case :httpc.request(method, request, http_options, options) do
      {:ok, {{_version, status, _reason}, _headers, response_body}} when status in 200..299 ->
        with {:ok, decoded} <- decode(response_body),
             :ok <- ensure_no_api_errors(decoded, config) do
          {:ok, decoded}
        end

      {:ok, {{_version, status, _reason}, _headers, response_body}} ->
        {:error, {:hue_http_error, status, safe_decode(response_body)}}

      {:error, reason} ->
        {:error, {:hue_unreachable, reason}}
    end
  rescue
    error -> {:error, {:hue_transport_error, Exception.message(error)}}
  end

  defp request_headers(nil), do: [{~c"accept", ~c"application/json"}]

  defp request_headers(config) do
    [
      {~c"accept", ~c"application/json"},
      {~c"hue-application-key", String.to_charlist(config["application_key"])}
    ]
  end

  defp decode(""), do: {:ok, %{}}

  defp decode(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, :invalid_hue_response}
    end
  end

  defp safe_decode(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> body
    end
  end

  defp ensure_no_api_errors(%{"errors" => [_ | _] = errors}, config) when not is_nil(config),
    do: {:error, {:hue_api_error, errors}}

  defp ensure_no_api_errors(_decoded, _config), do: :ok
end
