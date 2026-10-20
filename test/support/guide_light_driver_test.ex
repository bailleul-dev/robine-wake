defmodule RobineWake.GuideLight.Driver.Test do
  @moduledoc false
  @behaviour RobineWake.GuideLight.Driver
  @table :robine_wake_guide_light_driver_test

  def reset do
    table()
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc "Bodies of the `light.set` requests, in order."
  def commands do
    for {"light.set", body} <- requests(), do: body
  end

  @doc "Operations and bodies of every request, in order."
  def requests do
    table()

    @table
    |> :ets.tab2list()
    |> Enum.filter(fn {key, _value} -> match?({:command, _}, key) end)
    |> Enum.sort_by(fn {{:command, sequence}, _value} -> sequence end)
    |> Enum.map(&elem(&1, 1))
  end

  @doc "Request ids, in order."
  def ids do
    table()

    @table
    |> :ets.tab2list()
    |> Enum.filter(fn {key, _value} -> match?({:id, _}, key) end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  def set_result(result) do
    table()
    :ets.insert(@table, {:result, result})
    :ok
  end

  @doc "How many links were opened and closed since the last reset."
  def link_counts do
    table()

    count = fn key ->
      case :ets.lookup(@table, key) do
        [{^key, count}] -> count
        [] -> 0
      end
    end

    %{opened: count.(:opened), closed: count.(:closed)}
  end

  @impl true
  def open(_options) do
    :ets.update_counter(table(), :opened, 1, {:opened, 0})
    {:ok, :test_link}
  end

  @impl true
  def request(:test_link, id, request) do
    %{v: 1, id: ^id, op: operation, body: body} = Jason.decode!(request, keys: :atoms)
    sequence = :erlang.unique_integer([:positive, :monotonic])
    :ets.insert(table(), [{{:command, sequence}, {operation, body}}, {{:id, sequence}, id}])

    case :ets.lookup(table(), :result) do
      [{:result, {:error, _reason} = error}] -> error
      [{:result, {:response, response}}] -> {:ok, Jason.encode!(Map.put(response, :id, id))}
      _ -> {:ok, Jason.encode!(%{v: 1, id: id, status: "ok", body: %{}})}
    end
  end

  @impl true
  def close(:test_link) do
    :ets.update_counter(table(), :closed, 1, {:closed, 0})
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
