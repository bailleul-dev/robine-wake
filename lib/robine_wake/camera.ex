defmodule RobineWake.Camera do
  @moduledoc false
  use GenServer

  alias RobineWake.{BedDetector, Clock, Settings, WakeSession}

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def observe(state, confidence, attrs \\ %{}),
    do: GenServer.call(__MODULE__, {:observe, state, confidence, attrs})

  def submit_frame(frame, background, profile \\ %{}),
    do: GenServer.call(__MODULE__, {:frame, frame, background, profile})

  def calibrate(attrs \\ %{}), do: GenServer.call(__MODULE__, {:calibrate, attrs}, 15_000)
  def set_background(frame), do: GenServer.call(__MODULE__, {:set_background, frame})
  def reset, do: GenServer.call(__MODULE__, :reset)

  def status, do: GenServer.call(__MODULE__, :status)

  @impl true
  def init(_opts) do
    driver = Application.fetch_env!(:robine_wake, :camera_driver)
    profile = normalize_profile(Settings.detection_profile())

    {:ok,
     %{
       driver: driver,
       capabilities: driver.capabilities(),
       profile: profile,
       last_observation: nil,
       last_frame_at: nil,
       background: nil,
       calibrated: false,
       frames: 0,
       dropped_frames: 0,
       errors: 0
     }}
    |> then(fn result ->
      schedule_capture()
      result
    end)
  end

  @impl true
  def handle_call({:observe, state, confidence, attrs}, _from, camera) do
    observation =
      Map.merge(
        %{
          state: state,
          confidence: confidence,
          motion_score: 0.0,
          foreground_ratio: 0.0,
          quality: :good,
          captured_at_monotonic: Clock.monotonic_ms(),
          profile_revision: 1
        },
        Map.new(attrs)
      )

    {:reply, :ok, publish(camera, observation)}
  end

  def handle_call({:frame, frame, background, profile}, _from, camera) do
    frame = Map.put_new(frame, :captured_at_monotonic, Clock.monotonic_ms())

    case process_frame(camera, frame, background, profile) do
      {:ok, observation, next} -> {:reply, {:ok, observation}, next}
      {:error, reason, next} -> {:reply, {:error, reason}, next}
    end
  end

  def handle_call({:calibrate, attrs}, _from, camera) do
    with {:ok, profile} <- validate_profile(attrs, camera.profile),
         {:ok, frame} <- camera.driver.capture(width: profile.width, height: profile.height),
         :ok <- Settings.put_detection_profile(profile) do
      next = %{
        camera
        | background: frame.pixels,
          calibrated: true,
          profile: profile,
          last_frame_at: frame.captured_at_monotonic
      }

      {:reply, {:ok, %{calibrated: true, quality: frame.quality, profile: profile}}, next}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, %{camera | errors: camera.errors + 1}}
    end
  end

  def handle_call({:set_background, frame}, _from, camera) do
    if valid_frame?(frame) do
      {:reply, :ok, %{camera | background: frame.pixels, calibrated: true}}
    else
      {:reply, {:error, :invalid_frame}, camera}
    end
  end

  def handle_call(:reset, _from, camera) do
    next = %{
      camera
      | background: nil,
        calibrated: false,
        profile: default_profile(),
        last_observation: nil,
        last_frame_at: nil,
        frames: 0,
        dropped_frames: 0,
        errors: 0
    }

    {:reply, :ok, next}
  end

  @impl true
  def handle_call(:status, _from, state) do
    driver_health = state.driver.health()

    public =
      state
      |> Map.drop([:driver, :background])
      |> Map.put(:driver_health, driver_health)
      |> Map.put(:analysis_health, analysis_health(state))

    {:reply, public, state}
  end

  @impl true
  def handle_info(:capture, camera) do
    next = capture_once(camera)
    schedule_capture()
    {:noreply, next}
  end

  defp publish(camera, observation) do
    WakeSession.observe_sync(observation)

    %{
      camera
      | last_observation: observation,
        last_frame_at: observation.captured_at_monotonic,
        frames: camera.frames + 1
    }
  end

  defp capture_once(%{calibrated: false} = camera), do: camera

  defp capture_once(camera) do
    case camera.driver.capture(width: camera.profile.width, height: camera.profile.height) do
      {:ok, frame} ->
        frame =
          frame
          |> Map.put(:roi, camera.profile.roi)
          |> Map.put(:profile_revision, camera.profile.revision)

        detector_settings =
          Map.take(camera.profile, [:pixel_threshold, :occupied_ratio, :vacant_ratio])

        case process_frame(camera, frame, camera.background, detector_settings) do
          {:ok, _observation, next} -> next
          {:error, _reason, next} -> next
        end

      {:error, :use_submit_frame_on_host} ->
        camera

      {:error, _reason} ->
        %{camera | errors: camera.errors + 1}
    end
  end

  defp valid_frame?(%{pixels: pixels, width: width, height: height}),
    do: is_binary(pixels) and byte_size(pixels) == width * height

  defp valid_frame?(_), do: false

  defp process_frame(camera, frame, background, profile) do
    timestamp = Map.get(frame, :captured_at_monotonic)

    if is_integer(timestamp) and
         (is_nil(camera.last_frame_at) or timestamp > camera.last_frame_at) do
      observation = BedDetector.observe(frame, background, profile)
      {:ok, observation, publish(camera, observation)}
    else
      {:error, :stale_frame, %{camera | dropped_frames: camera.dropped_frames + 1}}
    end
  end

  defp analysis_health(%{calibrated: false}),
    do: %{state: :degraded, reason: :calibration_required}

  defp analysis_health(%{last_frame_at: nil}), do: %{state: :degraded, reason: :no_frame}

  defp analysis_health(state) do
    age_ms = max(0, Clock.monotonic_ms() - state.last_frame_at)

    if age_ms > 2_000,
      do: %{state: :degraded, reason: :stale_frame, age_ms: age_ms},
      else: %{state: :available, age_ms: age_ms}
  end

  defp normalize_profile(nil), do: default_profile()

  defp normalize_profile(profile) when is_map(profile) do
    case validate_profile(profile, default_profile(), false) do
      {:ok, normalized} -> normalized
      _error -> default_profile()
    end
  end

  defp validate_profile(attrs, current), do: validate_profile(attrs, current, true)

  defp validate_profile(attrs, current, increment?) when is_map(attrs) do
    roi_attrs = get(attrs, :roi, current.roi)

    profile = %{
      revision: if(increment?, do: current.revision + 1, else: integer(get(attrs, :revision), 1)),
      width: integer(get(attrs, :width), current.width),
      height: integer(get(attrs, :height), current.height),
      roi: normalize_roi(roi_attrs),
      pixel_threshold: integer(get(attrs, :pixel_threshold), current.pixel_threshold),
      occupied_ratio: float(get(attrs, :occupied_ratio), current.occupied_ratio),
      vacant_ratio: float(get(attrs, :vacant_ratio), current.vacant_ratio)
    }

    with :ok <- validate_dimensions(profile),
         :ok <- validate_roi(profile),
         :ok <- validate_detection_thresholds(profile) do
      {:ok, profile}
    end
  end

  defp validate_profile(_attrs, _current, _increment?),
    do: {:error, %{detection_profile: "must be an object"}}

  defp validate_dimensions(%{width: 320, height: 240}), do: :ok
  defp validate_dimensions(_profile), do: invalid_profile()

  defp validate_roi(%{roi: %{x: x, y: y, width: width, height: height}} = profile)
       when x >= 0 and y >= 0 and width > 0 and height > 0 and
              x + width <= profile.width and y + height <= profile.height,
       do: :ok

  defp validate_roi(_profile), do: invalid_profile()

  defp validate_detection_thresholds(profile) do
    if profile.pixel_threshold in 1..100 and profile.occupied_ratio >= 0.05 and
         profile.occupied_ratio <= 0.8 and profile.vacant_ratio >= 0.0 and
         profile.vacant_ratio < profile.occupied_ratio,
       do: :ok,
       else: invalid_profile()
  end

  defp invalid_profile,
    do: {:error, %{detection_profile: "contains incompatible or unsafe values"}}

  defp default_profile do
    %{
      revision: 1,
      width: 320,
      height: 240,
      roi: %{x: 0, y: 0, width: 320, height: 240},
      pixel_threshold: 28,
      occupied_ratio: 0.12,
      vacant_ratio: 0.04
    }
  end

  defp normalize_roi(roi) when is_map(roi) do
    %{
      x: integer(get(roi, :x), -1),
      y: integer(get(roi, :y), -1),
      width: integer(get(roi, :width), -1),
      height: integer(get(roi, :height), -1)
    }
  end

  defp normalize_roi(_roi), do: %{}

  defp get(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp integer(nil, default), do: default
  defp integer(value, _default) when is_integer(value), do: value

  defp integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> default
    end
  end

  defp integer(_value, default), do: default
  defp float(nil, default), do: default
  defp float(value, _default) when is_number(value), do: value / 1

  defp float(value, default) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> default
    end
  end

  defp float(_value, default), do: default

  defp schedule_capture do
    Process.send_after(
      self(),
      :capture,
      Application.fetch_env!(:robine_wake, :camera_interval_ms)
    )
  end
end
