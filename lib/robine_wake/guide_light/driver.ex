defmodule RobineWake.GuideLight.Driver do
  @moduledoc """
  Transport to the ESP32 guide light: carries one API-002 JSON request and
  returns the matching JSON response, whatever the link.
  """

  @type conn :: term()

  @callback open(keyword()) :: {:ok, conn()} | {:error, term()}
  @callback request(conn(), id :: String.t(), request :: binary()) ::
              {:ok, response :: binary()} | {:error, term()}
  @callback close(conn()) :: :ok
end
