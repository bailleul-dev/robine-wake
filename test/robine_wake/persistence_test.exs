defmodule RobineWake.PersistenceTest do
  use ExUnit.Case, async: true

  alias RobineWake.Persistence

  test "a failed encode does not replace the last valid document" do
    path = "tmp/persistence/atomic.json"
    File.rm(path)
    valid = Persistence.empty() |> Map.put("settings", %{"value" => 42})

    assert :ok = Persistence.save(path, valid)
    assert {:error, _reason} = Persistence.save(path, Map.put(valid, "invalid", self()))
    assert {:ok, ^valid} = Persistence.load(path)
  end

  test "rejects corrupt, missing, and future schema versions" do
    directory = "tmp/persistence"
    File.mkdir_p!(directory)

    corrupt = Path.join(directory, "corrupt.json")
    missing = Path.join(directory, "missing.json")
    future = Path.join(directory, "future.json")
    File.write!(corrupt, "{not-json")
    File.write!(missing, Jason.encode!(%{"alarms" => []}))
    File.write!(future, Jason.encode!(%{"schema_version" => 999}))

    assert {:error, _reason} = Persistence.load(corrupt)
    assert {:error, :missing_schema_version} = Persistence.load(missing)
    assert {:error, {:unsupported_schema, 999}} = Persistence.load(future)
  end
end
