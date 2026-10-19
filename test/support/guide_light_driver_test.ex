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
    table()

    @table
    |> :ets.tab2list()
    |> Enum.filter(fn {key, _value} -> match?({:command, _}, key) end)
    |> Enum.sort_by(fn {{:command, sequence}, _value} -> sequence end)
    |> Enum.map(&elem(&1, 1))
  end

  def set_result(result) do
    table()
    :ets.insert(@table, {:result, result})
    :ok
  end

  @impl true
  def open(_options), do: {:ok, :test_link}

  @impl true
  def request(:test_link, id, request) do
    %{v: 1, id: ^id, op: "light.set", body: body} = Jason.decode!(request, keys: :atoms)
    sequence = :erlang.unique_integer([:positive, :monotonic])
    :ets.insert(table(), {{:command, sequence}, body})

    case :ets.lookup(table(), :result) do
      [{:result, {:error, _reason} = error}] -> error
      _ -> {:ok, Jason.encode!(%{v: 1, id: id, status: "ok", body: %{}})}
    end
  end

  @impl true
  def close(:test_link), do: :ok

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
