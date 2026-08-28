import Foundation

struct Alarm: Codable, Identifiable, Hashable {
    struct VolumeProfile: Codable, Hashable {
        var start: Int
        var ceiling: Int
        var rampSeconds: Int

        enum CodingKeys: String, CodingKey {
            case start, ceiling
            case rampSeconds = "ramp_seconds"
        }
    }

    struct Snooze: Codable, Hashable {
        var enabled: Bool
        var durationSeconds: Int
        var maximum: Int

        enum CodingKeys: String, CodingKey {
            case enabled, maximum
            case durationSeconds = "duration_seconds"
        }
    }

    struct LightProfile: Codable, Hashable {
        var enabled: Bool
        var targetID: String?
        var targetName: String?
        var startBrightness: Int
        var endBrightness: Int
        var rampSeconds: Int
        var endBehavior: String

        enum CodingKeys: String, CodingKey {
            case enabled
            case targetID = "target_id"
            case targetName = "target_name"
            case startBrightness = "start_brightness"
            case endBrightness = "end_brightness"
            case rampSeconds = "ramp_seconds"
            case endBehavior = "end_behavior"
        }
    }

    let id: String
    var label: String
    var enabled: Bool
    var localTime: String
    var daysOfWeek: [Int]
    var oneShotDate: String?
    var timezone: String
    var soundID: String
    var strongSoundID: String
    var prewakeSeconds: Int?
    var volumeProfile: VolumeProfile
    var lightProfile: LightProfile?
    var dismissPolicy: String
    var snooze: Snooze
    var revision: Int
    var nextOccurrences: [String]?

    enum CodingKeys: String, CodingKey {
        case id, label, enabled, timezone, revision, snooze
        case localTime = "local_time"
        case daysOfWeek = "days_of_week"
        case oneShotDate = "one_shot_date"
        case soundID = "sound_id"
        case strongSoundID = "strong_sound_id"
        case prewakeSeconds = "prewake_seconds"
        case volumeProfile = "volume_profile"
        case lightProfile = "light_profile"
        case dismissPolicy = "dismiss_policy"
        case nextOccurrences = "next_occurrences"
    }
}

struct HueStatus: Codable, Hashable {
    struct Breathing: Codable, Hashable {
        struct Audio: Codable, Hashable {
            let active: Bool
            let kind: String?
            let gain: Int?
            let volumePercent: Int?
            let error: String?

            enum CodingKeys: String, CodingKey {
                case active, kind, gain, error
                case volumePercent = "volume_percent"
            }
        }

        let active: Bool
        let targetID: String?
        let targetName: String?
        let phase: String?
        let phaseStartedAt: String?
        let phaseDurationMilliseconds: Int?
        let phaseElapsedMilliseconds: Int?
        let phaseRemainingMilliseconds: Int?
        let cycleCount: Int?
        let durationMinutes: Int?
        let endsAt: String?
        let serverTime: String?
        let remainingSeconds: Int?
        let inhaleSeconds: Int?
        let exhaleSeconds: Int?
        let lowBrightness: Int?
        let highBrightness: Int?
        let audio: Audio?

        enum CodingKeys: String, CodingKey {
            case active, phase, audio
            case targetID = "target_id"
            case targetName = "target_name"
            case phaseStartedAt = "phase_started_at"
            case phaseDurationMilliseconds = "phase_duration_ms"
            case phaseElapsedMilliseconds = "phase_elapsed_ms"
            case phaseRemainingMilliseconds = "phase_remaining_ms"
            case cycleCount = "cycle_count"
            case durationMinutes = "duration_minutes"
            case endsAt = "ends_at"
            case serverTime = "server_time"
            case remainingSeconds = "remaining_seconds"
            case inhaleSeconds = "inhale_seconds"
            case exhaleSeconds = "exhale_seconds"
            case lowBrightness = "low_brightness"
            case highBrightness = "high_brightness"
        }
    }

    let configured: Bool
    let state: String
    let bridgeHost: String?
    let targetCount: Int
    let breathing: Breathing?
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case configured, state, breathing
        case bridgeHost = "bridge_host"
        case targetCount = "target_count"
        case lastError = "last_error"
    }

    func replacingBreathing(with breathing: Breathing?) -> HueStatus {
        HueStatus(
            configured: configured,
            state: state,
            bridgeHost: bridgeHost,
            targetCount: targetCount,
            breathing: breathing,
            lastError: lastError
        )
    }
}

struct HueTarget: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String
}

struct RemoteButtonStatus: Codable, Hashable {
    struct Pairing: Codable, Hashable {
        let active: Bool
        let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case active
            case expiresAt = "expires_at"
        }
    }

    struct Button: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        let pairedAt: String?
        let lastSeenAt: String?
        let lastCounter: Int

        enum CodingKeys: String, CodingKey {
            case id, name
            case pairedAt = "paired_at"
            case lastSeenAt = "last_seen_at"
            case lastCounter = "last_counter"
        }
    }

    let state: String
    let protocolName: String
    let security: String
    let buttons: [Button]
    let pairing: Pairing

    enum CodingKeys: String, CodingKey {
        case state, security, buttons, pairing
        case protocolName = "protocol"
    }
}

struct AlarmSound: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String?
    let durationMilliseconds: Int?
    let intensity: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id, title, artist, intensity, source
        case durationMilliseconds = "duration_ms"
    }
}

struct WakeSession: Codable, Identifiable, Hashable {
    let id: String
    let alarmID: String?
    let state: String?
    let terminalReason: String?
    let createdAt: String?
    let endedAt: String?
    let audioPhase: String?
    let currentGain: Int?
    let snoozeCount: Int?
    let occupancy: String?
    let confidence: Double?
    let smartphoneDismissAllowed: Bool?

    enum CodingKeys: String, CodingKey {
        case id, state, occupancy, confidence
        case alarmID = "alarm_id"
        case terminalReason = "terminal_reason"
        case createdAt = "created_at"
        case endedAt = "ended_at"
        case audioPhase = "audio_phase"
        case currentGain = "current_gain"
        case snoozeCount = "snooze_count"
        case smartphoneDismissAllowed = "smartphone_dismiss_allowed"
    }
}

struct SmartphoneDismissSetting: Codable, Hashable {
    let enabled: Bool
    let locked: Bool
}

struct DeviceState: Codable, Hashable {
    struct Component: Codable, Hashable {
        let state: String
    }

    struct Camera: Codable, Hashable {
        let state: String
        let calibrated: Bool
        let frames: Int
    }

    struct Firmware: Codable, Hashable {
        let version: String?
        let validation: String?
    }

    struct Updates: Codable, Hashable {
        let state: String
        let reason: String?
    }

    let state: String
    let now: String?
    let target: String?
    let version: String?
    let clockTrusted: Bool
    let camera: Camera
    let audio: Component
    let network: Component
    let firmware: Firmware
    let updates: Updates

    enum CodingKeys: String, CodingKey {
        case state, now, target, version, camera, audio, network, firmware, updates
        case clockTrusted = "clock_trusted"
    }
}

struct RobineState: Codable {
    struct Transport: Codable {
        let preferred: String
        let httpEndpoints: [String]
        let fallback: String

        enum CodingKeys: String, CodingKey {
            case preferred, fallback
            case httpEndpoints = "http_endpoints"
        }
    }

    let device: DeviceState
    let alarms: [Alarm]
    let sounds: [AlarmSound]
    let recentSessions: [WakeSession]
    let activeSession: WakeSession?
    let hue: HueStatus?
    let hueTargets: [HueTarget]?
    let remoteButton: RemoteButtonStatus?
    let smartphoneDismiss: SmartphoneDismissSetting?
    let transport: Transport?

    enum CodingKeys: String, CodingKey {
        case device, alarms, sounds, transport, hue
        case hueTargets = "hue_targets"
        case remoteButton = "remote_button"
        case smartphoneDismiss = "smartphone_dismiss"
        case recentSessions = "recent_sessions"
        case activeSession = "active_session"
    }
}

struct AlarmDraft: Identifiable {
    let id: String?
    var label: String
    var enabled: Bool
    var hour: Int
    var minute: Int
    var daysOfWeek: Set<Int>
    var timezone: String
    var soundID: String
    var strongSoundID: String
    var startVolume: Int
    var ceilingVolume: Int
    var prewakeMinutes: Int
    var dismissPolicy: String
    var snoozeEnabled: Bool
    var snoozeMinutes: Int
    var snoozeMaximum: Int
    var revision: Int?
    var lightEnabled: Bool
    var lightTargetID: String?
    var lightTargetName: String?
    var lightStartBrightness: Int
    var lightEndBrightness: Int
    var lightRampMinutes: Int
    var lightEndBehavior: String

    init(alarm: Alarm? = nil, sounds: [AlarmSound]) {
        id = alarm?.id
        label = alarm?.label ?? "Mon réveil"
        enabled = alarm?.enabled ?? true

        let timeParts = (alarm?.localTime ?? "07:00").split(separator: ":")
        hour = Int(timeParts.first ?? "7") ?? 7
        minute = Int(timeParts.dropFirst().first ?? "0") ?? 0
        daysOfWeek = Set(alarm?.daysOfWeek ?? [1, 2, 3, 4, 5])
        timezone = alarm?.timezone ?? TimeZone.current.identifier
        soundID = alarm?.soundID ?? sounds.first(where: { $0.intensity == "gentle" })?.id ?? sounds.first?.id ?? "default"
        strongSoundID = alarm?.strongSoundID ?? sounds.first(where: { $0.intensity == "strong" })?.id ?? sounds.last?.id ?? "default"
        startVolume = alarm?.volumeProfile.start ?? 15
        ceilingVolume = alarm?.volumeProfile.ceiling ?? 85
        prewakeMinutes = max(1, (alarm?.prewakeSeconds ?? alarm?.volumeProfile.rampSeconds ?? 1_200) / 60)
        dismissPolicy = "manual"
        snoozeEnabled = alarm?.snooze.enabled ?? true
        snoozeMinutes = max(1, (alarm?.snooze.durationSeconds ?? 480) / 60)
        snoozeMaximum = alarm?.snooze.maximum ?? 3
        revision = alarm?.revision
        lightEnabled = alarm?.lightProfile?.enabled ?? false
        lightTargetID = alarm?.lightProfile?.targetID
        lightTargetName = alarm?.lightProfile?.targetName
        lightStartBrightness = alarm?.lightProfile?.startBrightness ?? 1
        lightEndBrightness = alarm?.lightProfile?.endBrightness ?? 70
        lightRampMinutes = max(1, (alarm?.lightProfile?.rampSeconds ?? 900) / 60)
        lightEndBehavior = alarm?.lightProfile?.endBehavior ?? "restore"
    }

    var time: Date {
        get { Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now }
        set {
            hour = Calendar.current.component(.hour, from: newValue)
            minute = Calendar.current.component(.minute, from: newValue)
        }
    }

    var payload: [String: Any] {
        var lightProfile: [String: Any] = [
            "enabled": lightEnabled,
            "start_brightness": lightStartBrightness,
            "end_brightness": lightEndBrightness,
            "ramp_seconds": lightRampMinutes * 60,
            "end_behavior": lightEndBehavior
        ]
        if let lightTargetID { lightProfile["target_id"] = lightTargetID }
        if let lightTargetName { lightProfile["target_name"] = lightTargetName }

        var value: [String: Any] = [
            "label": label.trimmingCharacters(in: .whitespacesAndNewlines),
            "enabled": enabled,
            "local_time": String(format: "%02d:%02d", hour, minute),
            "days_of_week": daysOfWeek.sorted(),
            "timezone": timezone,
            "sound_id": soundID,
            "strong_sound_id": strongSoundID,
            "prewake_seconds": prewakeMinutes * 60,
            "volume_profile": [
                "start": startVolume,
                "ceiling": ceilingVolume,
                "ramp_seconds": prewakeMinutes * 60
            ],
            "light_profile": lightProfile,
            "dismiss_policy": "manual",
            "snooze": [
                "enabled": snoozeEnabled,
                "duration_seconds": snoozeMinutes * 60,
                "maximum": snoozeMaximum
            ]
        ]

        if let revision { value["revision"] = revision }
        return value
    }
}
