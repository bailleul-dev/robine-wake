defmodule RobineWake.GuideLight.Driver.HTTP do
  @moduledoc "Posts requests to the ESP32 command endpoint over Wi-Fi (`url:` option)."

  @behaviour RobineWake.GuideLight.Driver

  @impl true
  def open(options) do
    case Keyword.fetch(options, :url) do
      {:ok, url} when is_binary(url) ->
        {:ok, %{url: url, timeout: Keyword.get(options, :timeout_ms, 1_000)}}

      _ ->
        {:error, :guide_light_url_missing}
    end
  end

  @impl true
  def request(%{url: url, timeout: timeout}, _id, request) do
    http_request = {~c"#{url}/api/v1/command", [], ~c"application/json", request}
    http_options = [timeout: timeout, connect_timeout: timeout]

    case :httpc.request(:post, http_request, http_options, body_format: :binary) do
      {:ok, {{_version, 200, _reason}, _headers, response}} ->
        {:ok, response}

      {:ok, {{_version, status, _reason}, _headers, _response}} ->
        {:error, {:guide_light_http_error, status}}

      {:error, reason} ->
        {:error, {:guide_light_unreachable, reason}}
    end
  end

  @impl true
  def close(_conn), do: :ok
end
