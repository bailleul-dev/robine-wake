defmodule RobineWake.Auth do
  @moduledoc "Password verification, first-run provisioning, and login throttling."

  use GenServer

  require Logger
  alias RobineWake.Clock

  @window_ms :timer.minutes(5)
  @lock_ms :timer.minutes(1)
  @maximum_failures 5

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def provisioned?, do: GenServer.call(__MODULE__, :provisioned?)
  def status, do: GenServer.call(__MODULE__, :status)

  def verify(username, password, peer),
    do: GenServer.call(__MODULE__, {:verify, username, password, peer})

  def provision(password), do: GenServer.call(__MODULE__, {:provision, password})
  def factory_reset, do: GenServer.call(__MODULE__, :factory_reset)
  def clear_rate_limits, do: GenServer.call(__MODULE__, :clear_rate_limits)

  @impl true
  def init(_opts) do
    path = Application.fetch_env!(:robine_wake, :auth_path)
    username = Application.get_env(:robine_wake, :admin_username, "admin")

    credential =
      case load(path) do
        {:ok, stored} -> stored
        _ -> credential_from_config()
      end

    Application.delete_env(:robine_wake, :admin_password)

    {:ok, %{path: path, username: username, credential: credential, attempts: %{}}}
  end

  @impl true
  def handle_call(:provisioned?, _from, state),
    do: {:reply, not is_nil(state.credential), state}

  def handle_call(:status, _from, state) do
    {:reply,
     %{
       state: if(state.credential, do: :available, else: :degraded),
       provisioned: not is_nil(state.credential),
       username: state.username,
       reason: if(state.credential, do: nil, else: :password_setup_required)
     }, state}
  end

  def handle_call({:verify, username, password, peer}, _from, state) do
    now = Clock.monotonic_ms()
    key = {peer, username}
    attempts = prune_attempts(state.attempts, now)

    case Map.get(attempts, key) do
      %{locked_until: locked_until} when locked_until > now ->
        {:reply, {:error, :rate_limited}, %{state | attempts: attempts}}

      _ ->
        valid =
          is_binary(password) and username == state.username and
            verify_password(password, state.credential)

        if valid do
          {:reply, :ok, %{state | attempts: Map.delete(attempts, key)}}
        else
          Logger.warning(
            "Authentication failed for user=#{inspect(username)} peer=#{inspect(peer)}"
          )

          next_attempts = record_failure(attempts, key, now)
          {:reply, {:error, :invalid_credentials}, %{state | attempts: next_attempts}}
        end
    end
  end

  def handle_call({:provision, password}, _from, %{credential: nil} = state) do
    if valid_password?(password) do
      credential = hash_password(password)

      case persist(state.path, credential) do
        :ok -> {:reply, :ok, %{state | credential: credential}}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :weak_password}, state}
    end
  end

  def handle_call({:provision, _password}, _from, state),
    do: {:reply, {:error, :already_provisioned}, state}

  def handle_call(:clear_rate_limits, _from, state),
    do: {:reply, :ok, %{state | attempts: %{}}}

  def handle_call(:factory_reset, _from, state) do
    case File.rm(state.path) do
      :ok -> {:reply, :ok, %{state | credential: nil, attempts: %{}}}
      {:error, :enoent} -> {:reply, :ok, %{state | credential: nil, attempts: %{}}}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp credential_from_config do
    case Application.get_env(:robine_wake, :admin_password) do
      password when is_binary(password) and byte_size(password) > 0 -> hash_password(password)
      _ -> nil
    end
  end

  defp hash_password(password) do
    salt = :crypto.strong_rand_bytes(16)
    iterations = Application.fetch_env!(:robine_wake, :password_iterations)
    digest = :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, 32)

    %{
      "algorithm" => "pbkdf2-hmac-sha256",
      "iterations" => iterations,
      "salt" => Base.encode64(salt),
      "digest" => Base.encode64(digest)
    }
  end

  defp verify_password(_password, nil), do: false

  defp verify_password(password, credential) do
    with "pbkdf2-hmac-sha256" <- credential["algorithm"],
         iterations when is_integer(iterations) <- credential["iterations"],
         {:ok, salt} <- Base.decode64(credential["salt"] || ""),
         {:ok, expected} <- Base.decode64(credential["digest"] || "") do
      actual = :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, byte_size(expected))
      byte_size(actual) == byte_size(expected) and Plug.Crypto.secure_compare(actual, expected)
    else
      _ -> false
    end
  end

  defp valid_password?(password),
    do: is_binary(password) and String.length(password) >= 12 and String.length(password) <= 128

  defp record_failure(attempts, key, now) do
    previous = Map.get(attempts, key, %{failures: [], locked_until: 0})
    failures = [now | Enum.filter(previous.failures, &(now - &1 <= @window_ms))]
    locked_until = if length(failures) >= @maximum_failures, do: now + @lock_ms, else: 0
    Map.put(attempts, key, %{failures: failures, locked_until: locked_until})
  end

  defp prune_attempts(attempts, now) do
    Map.filter(attempts, fn {_key, value} ->
      value.locked_until > now or Enum.any?(value.failures, &(now - &1 <= @window_ms))
    end)
  end

  defp load(path) do
    with {:ok, encoded} <- File.read(path),
         {:ok, credential} <- Jason.decode(encoded),
         true <- is_map(credential) do
      {:ok, credential}
    else
      _ -> {:error, :invalid_auth_file}
    end
  end

  defp persist(path, credential) do
    temporary = path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, encoded} <- Jason.encode(credential, pretty: true),
         :ok <- File.write(temporary, encoded <> "\n", [:binary, :sync]),
         :ok <- File.chmod(temporary, 0o600) do
      File.rename(temporary, path)
    end
  end
end
