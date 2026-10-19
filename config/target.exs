import Config

config :nerves, :firmware, fwup_conf: "config/rpi3-fwup.conf"

config :logger, backends: [RingLogger]
config :shoehorn, init: [:nerves_runtime, :nerves_pack]
config :nerves, :erlinit, update_clock: true

keys =
  System.user_home!()
  |> Path.join(".ssh/id_{rsa,ecdsa,ed25519}.pub")
  |> Path.wildcard()

config :nerves_ssh, authorized_keys: Enum.map(keys, &File.read!/1)

config :nerves_ssh,
  subsystems: [
    :ssh_sftpd.subsystem_spec(cwd: ~c"/"),
    {~c"fwup",
     {SSHSubsystemFwup,
      [
        devpath: "/dev/mmcblk0",
        fwup_extra_options: ["--public-key-file", "/etc/robine-wake/fwup-key.pub"],
        precheck_callback: {RobineWake.UpdatePolicy, :precheck, []}
      ]}}
  ]

wifi_config =
  case {
    System.get_env("ROBINE_WIFI_SSID"),
    System.get_env("ROBINE_WIFI_PASSPHRASE")
  } do
    {nil, nil} ->
      nil

    {"", ""} ->
      nil

    {ssid, passphrase}
    when is_binary(ssid) and byte_size(ssid) in 1..32 and is_binary(passphrase) and
           byte_size(passphrase) in 8..63 ->
      %{
        type: VintageNetWiFi,
        vintage_net_wifi: %{
          networks: [
            %{
              ssid: ssid,
              psk: passphrase,
              key_mgmt: :wpa_psk
            }
          ]
        },
        ipv4: %{method: :dhcp}
      }

    _ ->
      raise "ROBINE_WIFI_SSID and ROBINE_WIFI_PASSPHRASE must both be set; SSID length is 1-32 bytes and passphrase length is 8-63 bytes"
  end

config :vintage_net,
  regulatory_domain: "FR",
  config:
    [{"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}] ++
      if(wifi_config, do: [{"wlan0", wifi_config}], else: [])

config :mdns_lite,
  hosts: [:hostname, "robine-wake"],
  ttl: 120,
  services: [
    %{protocol: "http", transport: "tcp", port: 4000},
    %{protocol: "ssh", transport: "tcp", port: 22}
  ]

config :robine_wake,
  audio_driver: RobineWake.Audio.Driver.Alsa,
  airplay_enabled: true,
  bluetooth_audio_enabled: true,
  # The onboard controller now belongs to BlueZ (Bluetooth audio receiver);
  # the BlueHeron BLE control service is disabled and not started.
  bluetooth_enabled: false,
  bluetooth_driver: RobineWake.Bluetooth.Driver.BlueHeron,
  # NeoPixel guide light on the ESP32, wired to GPIO 14/15 (mini UART).
  guide_light: [driver: RobineWake.GuideLight.Driver.UART, device: "ttyS0"],
  lora_enabled: true,
  lora_driver: RobineWake.LoRa.Driver.SX1276,
  lora_options: [
    spi_bus: "spidev0.0",
    frequency_hz: 868_100_000,
    bandwidth_hz: 125_000,
    spreading_factor: 9,
    coding_rate: 5,
    sync_word: 0x12,
    tx_power_dbm: 14
  ],
  camera_driver: RobineWake.Camera.Driver.Rpi,
  camera_enabled: false,
  network_driver: RobineWake.Network.Driver.System,
  initial_time_quality: :untrusted,
  auto_confirm_ntp: true,
  data_path: "/data/robine_wake.json",
  critical_event_path: "/data/robine_wake_critical_events.json",
  auth_path: "/data/robine_wake_auth.json",
  firmware_public_key_path: "/etc/robine-wake/fwup-key.pub",
  default_sound_path: "/data/sounds/default.wav",
  alsa_device: "auto",
  web_ip: {0, 0, 0, 0}
