defmodule RobineWake.Persistence do
  @moduledoc false

  @schema_version 1

  def load(path) do
    case File.read(path) do
      {:ok, contents} -> decode(contents)
      {:error, :enoent} -> {:ok, empty()}
      {:error, reason} -> {:error, reason}
    end
  end

  def save(path, data) do
    directory = Path.dirname(path)
    temporary = path <> ".tmp"

    with :ok <- File.mkdir_p(directory),
         {:ok, encoded} <- Jason.encode(data, pretty: true),
         :ok <- File.write(temporary, encoded <> "\n", [:binary, :sync]),
         :ok <- File.chmod(temporary, 0o600) do
      File.rename(temporary, path)
    end
  end

  def empty do
    %{
      "schema_version" => @schema_version,
      "alarms" => [],
      "sessions" => [],
      "settings" => %{}
    }
  end

  defp decode(contents) do
    case Jason.decode(contents) do
      {:ok, %{"schema_version" => @schema_version} = data} -> {:ok, data}
      {:ok, %{"schema_version" => version}} -> {:error, {:unsupported_schema, version}}
      {:ok, _data} -> {:error, :missing_schema_version}
      {:error, reason} -> {:error, reason}
    end
  end
end
