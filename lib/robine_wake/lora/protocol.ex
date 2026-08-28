defmodule RobineWake.LoRa.Protocol do
  @moduledoc false

  alias RobineWake.RemoteButton

  @version 1
  @maximum_packet_bytes 255
  @valid_id ~r/\A[a-zA-Z0-9_-]{1,64}\z/

  def handle(payload) when is_binary(payload) and byte_size(payload) <= @maximum_packet_bytes do
    with {:ok, request} <- Jason.decode(payload),
         :ok <- validate_request(request),
         {:ok, body} <- dispatch(request["op"], request["body"] || %{}) do
      encode(%{"v" => @version, "id" => request["id"], "status" => "ok", "body" => body})
    else
      {:error, reason} -> error_response(request_id(payload), reason)
      _ -> error_response(request_id(payload), :invalid_lora_request)
    end
  end

  def handle(_payload), do: error_response(nil, :lora_packet_too_large)

  def request_key(payload) when is_binary(payload), do: :crypto.hash(:sha256, payload)

  defp validate_request(%{"v" => @version, "id" => id, "op" => operation, "body" => body})
       when is_binary(id) and is_binary(operation) and is_map(body) do
    if Regex.match?(@valid_id, id), do: :ok, else: {:error, :invalid_lora_request_id}
  end

  defp validate_request(_request), do: {:error, :invalid_lora_request}

  defp dispatch("pair", %{"button_id" => button_id, "name" => name}) do
    case RemoteButton.pair(button_id, name) do
      {:ok, response} ->
        {:ok,
         %{
           "secret_hex" => response.secret_hex,
           "next_counter" => response.next_counter
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp dispatch("dismiss", body) when is_map(body) do
    case RemoteButton.dismiss(body) do
      {:ok, response} ->
        {:ok,
         response
         |> Map.take([:accepted, :duplicate, :button_id, :counter])
         |> stringify_keys()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp dispatch("ping", _body), do: {:ok, %{"ready" => true}}
  defp dispatch(_operation, _body), do: {:error, :unsupported_lora_operation}

  defp error_response(id, reason) do
    encode(%{
      "v" => @version,
      "id" => id,
      "status" => "error",
      "error" => %{"code" => to_string(reason)}
    })
  end

  defp request_id(payload) do
    case Jason.decode(payload) do
      {:ok, %{"id" => id}} when is_binary(id) -> id
      _ -> nil
    end
  end

  defp encode(envelope) do
    encoded = Jason.encode!(envelope)

    if byte_size(encoded) <= @maximum_packet_bytes,
      do: {:ok, encoded},
      else: {:error, :lora_response_too_large}
  end

  defp stringify_keys(map),
    do: Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)
end
