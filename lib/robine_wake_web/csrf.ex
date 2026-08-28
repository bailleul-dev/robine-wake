defmodule RobineWakeWeb.CSRF do
  @moduledoc "Per-boot CSRF token for the authenticated local interface."

  use GenServer

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def token, do: GenServer.call(__MODULE__, :token)

  def valid?(candidate) when is_binary(candidate) do
    expected = token()

    byte_size(candidate) == byte_size(expected) and
      Plug.Crypto.secure_compare(candidate, expected)
  end

  def valid?(_candidate), do: false

  @impl true
  def init(_opts) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    {:ok, token}
  end

  @impl true
  def handle_call(:token, _from, token), do: {:reply, token, token}
end
