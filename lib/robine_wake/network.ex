defmodule RobineWake.Network do
  @moduledoc "Observable network capability boundary; alarm operation never depends on it."

  use GenServer

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def status, do: GenServer.call(__MODULE__, :status)

  @impl true
  def init(_opts), do: {:ok, Application.fetch_env!(:robine_wake, :network_driver)}

  @impl true
  def handle_call(:status, _from, driver), do: {:reply, driver.status(), driver}
end
