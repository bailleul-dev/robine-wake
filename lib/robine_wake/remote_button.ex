defmodule RobineWake.RemoteButton do
  @moduledoc "Authenticated LoRa remote-button pairing and alarm dismissal."

  use GenServer

  alias RobineWake.{Clock, EventLog, EventStream, Settings, WakeSession}

  @default_pairing_seconds 120
  @minimum_pairing_seconds 30
  @maximum_pairing_seconds 300
  @maximum_counter 9_007_199_254_740_991
  @mac_domain "rw-remote-v1"

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def status, do: GenServer.call(__MODULE__, :status)

  def begin_pairing(duration_seconds \\ @default_pairing_seconds),
    do: GenServer.call(__MODULE__, {:begin_pairing, duration_seconds})

  def pair(button_id, name), do: GenServer.call(__MODULE__, {:pair, button_id, name})
  def remove(button_id), do: GenServer.call(__MODULE__, {:remove, button_id})
  def dismiss(attrs), do: GenServer.call(__MODULE__, {:dismiss, attrs})
  def reset, do: GenServer.call(__MODULE__, :reset)

  def mac(secret, button_id, counter)
      when is_binary(secret) and is_binary(button_id) and is_integer(counter) do
    :crypto.mac(:hmac, :sha256, secret, signed_message(button_id, counter))
    |> Base.encode16(case: :lower)
  end

  def signed_message(button_id, counter),
    do: Enum.join([@mac_domain, button_id, Integer.to_string(counter), "dismiss"], <<0>>)

  @impl true
  def init(_opts), do: {:ok, %{pairing_deadline_ms: nil, pairing_expires_at: nil}}

  @impl true
  def handle_call(:status, _from, state), do: {:reply, public_status(state), state}

  def handle_call({:begin_pairing, duration_seconds}, _from, state)
      when duration_seconds in @minimum_pairing_seconds..@maximum_pairing_seconds do
    deadline = Clock.monotonic_ms() + duration_seconds * 1_000
    expires_at = Clock.utc_now() |> DateTime.add(duration_seconds, :second)

    next = %{state | pairing_deadline_ms: deadline, pairing_expires_at: expires_at}

    EventLog.emit(:remote_button_pairing_started,
      source: :remote_button,
      payload: %{duration_seconds: duration_seconds}
    )

    EventStream.publish("state.changed")
    {:reply, {:ok, public_status(next)}, next}
  end

  def handle_call({:begin_pairing, _duration_seconds}, _from, state),
    do: {:reply, {:error, :invalid_pairing_duration}, state}

  def handle_call({:pair, button_id, name}, _from, state) do
    with :ok <- require_pairing_window(state),
         :ok <- validate_button_id(button_id),
         :ok <- validate_name(name),
         secret <- :crypto.strong_rand_bytes(32),
         :ok <- Settings.put_remote_button(button_id, name, secret) do
      next = %{state | pairing_deadline_ms: nil, pairing_expires_at: nil}

      EventLog.emit(:remote_button_paired,
        source: :remote_button,
        payload: %{button_id: button_id}
      )

      EventStream.publish("state.changed")

      {:reply,
       {:ok,
        %{
          button_id: button_id,
          algorithm: "hmac-sha256",
          protocol: @mac_domain,
          secret_hex: Base.encode16(secret, case: :lower),
          next_counter: 1
        }}, next}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:remove, button_id}, _from, state) do
    case Settings.remove_remote_button(button_id) do
      :ok ->
        EventLog.emit(:remote_button_removed,
          source: :remote_button,
          payload: %{button_id: button_id}
        )

        EventStream.publish("state.changed")
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:dismiss, attrs}, _from, state) when is_map(attrs) do
    button_id = Map.get(attrs, "button_id", Map.get(attrs, :button_id))
    counter = Map.get(attrs, "counter", Map.get(attrs, :counter))
    signature = Map.get(attrs, "mac", Map.get(attrs, :mac))

    result =
      with :ok <- validate_button_id(button_id),
           :ok <- validate_counter(counter),
           :ok <- validate_signature(signature),
           {:ok, freshness} <-
             Settings.authorize_remote_button(button_id, counter, signature) do
        complete_dismiss(button_id, counter, freshness)
      end

    case result do
      {:ok, response} ->
        {:reply, {:ok, response}, state}

      {:error, reason} ->
        EventLog.emit(:remote_button_rejected,
          source: :remote_button,
          severity: :warning,
          payload: %{button_id: button_id, reason: reason}
        )

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:dismiss, _attrs}, _from, state),
    do: {:reply, {:error, :invalid_remote_button_command}, state}

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | pairing_deadline_ms: nil, pairing_expires_at: nil}}
  end

  defp complete_dismiss(button_id, counter, :duplicate) do
    {:ok, %{accepted: true, duplicate: true, button_id: button_id, counter: counter}}
  end

  defp complete_dismiss(button_id, counter, :fresh) do
    with {:ok, session} <- WakeSession.dismiss(:remote_button) do
      EventLog.emit(:remote_button_dismissed,
        source: :remote_button,
        payload: %{button_id: button_id, counter: counter}
      )

      EventStream.publish("session.changed")

      {:ok,
       %{
         accepted: true,
         duplicate: false,
         button_id: button_id,
         counter: counter,
         session: session
       }}
    end
  end

  defp public_status(state) do
    active = pairing_active?(state)

    %{
      state: if(Settings.remote_buttons() == [], do: :unpaired, else: :available),
      transport: :lora,
      frequency_hz:
        Application.get_env(:robine_wake, :lora_options, [])
        |> Keyword.get(:frequency_hz, 868_100_000),
      protocol: @mac_domain,
      security: :hmac_sha256_counter,
      buttons: Settings.remote_buttons(),
      pairing: %{
        active: active,
        expires_at: if(active, do: DateTime.to_iso8601(state.pairing_expires_at), else: nil)
      }
    }
  end

  defp require_pairing_window(state) do
    if pairing_active?(state), do: :ok, else: {:error, :pairing_window_closed}
  end

  defp pairing_active?(%{pairing_deadline_ms: deadline}) when is_integer(deadline),
    do: Clock.monotonic_ms() < deadline

  defp pairing_active?(_state), do: false

  defp validate_button_id(value) when is_binary(value) do
    if String.match?(value, ~r/\A[a-zA-Z0-9_-]{1,48}\z/),
      do: :ok,
      else: {:error, :invalid_button_id}
  end

  defp validate_button_id(_value), do: {:error, :invalid_button_id}

  defp validate_name(value) when is_binary(value) do
    if String.length(String.trim(value)) in 1..64,
      do: :ok,
      else: {:error, :invalid_button_name}
  end

  defp validate_name(_value), do: {:error, :invalid_button_name}

  defp validate_counter(value) when is_integer(value) and value in 1..@maximum_counter, do: :ok
  defp validate_counter(_value), do: {:error, :invalid_remote_button_counter}

  defp validate_signature(value) when is_binary(value) do
    if String.match?(value, ~r/\A[0-9a-fA-F]{64}\z/),
      do: :ok,
      else: {:error, :invalid_remote_button_signature}
  end

  defp validate_signature(_value), do: {:error, :invalid_remote_button_signature}
end
