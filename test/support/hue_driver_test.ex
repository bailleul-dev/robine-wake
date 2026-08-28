defmodule RobineWake.Hue.Driver.Test do
  @moduledoc false
  @behaviour RobineWake.Hue.Driver
  @table :robine_wake_hue_driver_test

  def reset do
    table()
    :ets.delete_all_objects(@table)
    :ok
  end

  def commands do
    table()

    @table
    |> :ets.tab2list()
    |> Enum.filter(fn {key, _value} -> match?({:command, _}, key) end)
    |> Enum.sort_by(fn {{:command, sequence}, _value} -> sequence end)
    |> Enum.map(&elem(&1, 1))
  end

  def set_delay(milliseconds) when is_integer(milliseconds) and milliseconds >= 0 do
    table()
    :ets.insert(@table, {:set_delay, milliseconds})
    :ok
  end

  def set_targets_result(result) do
    table()
    :ets.insert(@table, {:targets_result, result})
    :ok
  end

  @impl true
  def pair("button-required"), do: {:error, :hue_link_button_required}

  def pair(host) do
    {:ok,
     %{
       "host" => host,
       "application_key" => "test-application-key",
       "client_key" => "test-client-key"
     }}
  end

  @impl true
  def targets(_config) do
    case :ets.lookup(table(), :targets_result) do
      [{:targets_result, result}] -> result
      [] -> {:ok, [%{"id" => "bedroom-group", "name" => "Chambre", "kind" => "room"}]}
    end
  end

  @impl true
  def get_target(_config, id) do
    record({:get, id})

    {:ok,
     %{
       "on" => %{"on" => false},
       "dimming" => %{"brightness" => 42.0},
       "color" => %{"xy" => %{"x" => 0.31, "y" => 0.33}}
     }}
  end

  @impl true
  def set_target(_config, id, changes) do
    case :ets.lookup(table(), :set_delay) do
      [{:set_delay, milliseconds}] -> Process.sleep(milliseconds)
      [] -> :ok
    end

    record({:set, id, changes})
    :ok
  end

  defp record(command) do
    table()
    sequence = :erlang.unique_integer([:positive, :monotonic])
    :ets.insert(@table, {{:command, sequence}, command})
    :ok
  end

  defp table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :ordered_set])
        rescue
          ArgumentError -> @table
        end

      reference ->
        reference
    end
  end
end
