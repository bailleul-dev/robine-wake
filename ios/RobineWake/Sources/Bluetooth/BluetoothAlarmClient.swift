@preconcurrency import CoreBluetooth
import Combine
import Foundation

@MainActor
final class BluetoothAlarmClient: NSObject, ObservableObject {
    enum CommandTransport: String {
        case http = "Wi-Fi"
        case bluetooth = "Bluetooth"
    }

    enum ConnectionState: String {
        case bluetoothUnavailable = "Bluetooth indisponible"
        case scanning = "Recherche du réveil…"
        case connecting = "Connexion…"
        case connected = "À proximité"
        case disconnected = "Déconnecté"
    }

    private struct ErrorPayload: Decodable {
        let code: String
    }

    private struct BaseEnvelope: Decodable {
        let v: Int
        let id: String?
        let status: String
        let error: ErrorPayload?
    }

    private struct StateEnvelope: Decodable {
        let v: Int
        let id: String?
        let status: String
        let body: RobineState?
        let error: ErrorPayload?
    }

    private struct SessionEnvelope: Decodable {
        struct Body: Decodable {
            let activeSession: WakeSession?

            enum CodingKeys: String, CodingKey {
                case activeSession = "active_session"
            }
        }

        let body: Body?
    }

    private struct ServerEventEnvelope: Decodable {
        struct Payload: Decodable {
            let hue: HueStatus?
        }

        let data: Payload?
    }

    private struct PendingRequest {
        let id: String
        let operation: String
    }

    private struct PageAccumulator {
        let sequence: UInt32
        let pageCount: Int
        let totalBytes: Int
        let crc32: UInt32
        var nextPageIndex: Int
        var payload: Data
    }

    private struct ResponsePage {
        let isFinal: Bool
        let sequence: UInt32
        let index: Int
        let count: Int
        let totalBytes: Int
        let crc32: UInt32
        let payload: Data

        init(data: Data) throws {
            guard data.count >= 20,
                  data[0] == 0x52,
                  data[1] == 0x57,
                  data[2] == 1 else {
                throw BluetoothError.invalidTransport("En-tête de réponse invalide")
            }

            isFinal = data[3] & 0x01 == 0x01
            sequence = data.uint32(at: 4)
            index = Int(data.uint16(at: 8))
            count = Int(data.uint16(at: 10))
            totalBytes = Int(data.uint32(at: 12))
            crc32 = data.uint32(at: 16)
            payload = data.subdata(in: 20..<data.count)

            guard count > 0, index < count, totalBytes <= 1_048_576 else {
                throw BluetoothError.invalidTransport("Métadonnées de page invalides")
            }
        }
    }

    private static let serviceUUID = CBUUID(string: "8AD00001-A7A9-4EF7-A259-67C9C65E4C10")
    private static let commandUUID = CBUUID(string: "8AD00002-A7A9-4EF7-A259-67C9C65E4C10")
    private static let responseUUID = CBUUID(string: "8AD00003-A7A9-4EF7-A259-67C9C65E4C10")
    private static let endpointDefaultsKey = "robineWake.httpCommandEndpoint.v1"
    private static let eventIDDefaultsKey = "robineWake.lastServerEventID.v1"

    @Published private(set) var state: ConnectionState = .scanning
    @Published private(set) var alarms: [Alarm] = []
    @Published private(set) var sounds: [AlarmSound] = []
    @Published private(set) var device: DeviceState?
    @Published private(set) var recentSessions: [WakeSession] = []
    @Published private(set) var activeSession: WakeSession?
    @Published private(set) var hue: HueStatus?
    @Published private(set) var hueTargets: [HueTarget] = []
    @Published private(set) var remoteButton: RemoteButtonStatus?
    @Published private(set) var breathingSynchronizedAt: Date?
    @Published private(set) var isBusy = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var signalStrength: Int?
    @Published private(set) var activeTransport: CommandTransport?
    @Published private(set) var httpEndpoint: URL?
    @Published var lastError: String?

    var canSendCommands: Bool {
        httpEndpoint != nil || bluetoothReady
    }

    var connectionLabel: String {
        activeTransport?.rawValue ?? state.rawValue
    }

    var isPairingHue: Bool {
        isBusy && pendingRequest?.operation == "hue.pair"
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?
    private var writeChunks: [Data] = []
    private var pageAccumulator: PageAccumulator?
    private var pendingRequest: PendingRequest?
    private var requestTransport: CommandTransport?
    private var eventStreamTask: Task<Void, Never>?

    private var bluetoothReady: Bool {
        state == .connected && commandCharacteristic != nil && responseCharacteristic != nil
    }

    override init() {
        super.init()
        if let saved = UserDefaults.standard.string(forKey: Self.endpointDefaultsKey) {
            httpEndpoint = URL(string: saved)
        }
        central = CBCentralManager(delegate: self, queue: .main)

        if httpEndpoint != nil {
            Task { [weak self] in
                self?.startEventStream()
                self?.refresh()
            }
        }
    }

    func reconnect() {
        guard central.state == .poweredOn else { return }
        central.stopScan()
        state = .scanning
        central.scanForPeripherals(withServices: [Self.serviceUUID])
    }

    func refresh() {
        send(operation: "state.get")
    }

    func refreshSession() {
        guard canSendCommands, !isBusy else { return }
        send(operation: "session.get")
    }

    func save(_ draft: AlarmDraft) {
        if let alarmID = draft.id {
            send(operation: "alarm.update", body: ["alarm_id": alarmID, "alarm": draft.payload])
        } else {
            send(operation: "alarm.create", body: draft.payload)
        }
    }

    func delete(_ alarm: Alarm) {
        send(operation: "alarm.delete", body: ["alarm_id": alarm.id, "revision": alarm.revision])
    }

    func setEnabled(_ enabled: Bool, for alarm: Alarm) {
        var draft = AlarmDraft(alarm: alarm, sounds: sounds)
        draft.enabled = enabled
        save(draft)
    }

    func trigger(_ alarm: Alarm) {
        launchFullAlarm(id: alarm.id)
    }

    func launchFullAlarm(id: String) {
        send(operation: "alarm.trigger", body: ["alarm_id": id])
    }

    func testStrongAlarm(id: String) {
        send(operation: "alarm.trigger_strong", body: ["alarm_id": id])
    }

    func snooze() { send(operation: "session.snooze") }
    func dismissSession() { send(operation: "session.dismiss") }
    func confirmClock() { send(operation: "clock.confirm") }
    func eraseHistory() { send(operation: "history.erase") }
    func pairHue(bridgeHost: String) {
        send(operation: "hue.pair", body: ["bridge_host": bridgeHost.trimmingCharacters(in: .whitespacesAndNewlines)])
    }
    func refreshHue() { send(operation: "hue.refresh") }
    func disconnectHue() { send(operation: "hue.disconnect") }
    func startBreathing(targetID: String, durationMinutes: Int, volumePercent: Int) {
        send(
            operation: "breathing.start",
            body: [
                "target_id": targetID,
                "duration_minutes": durationMinutes,
                "volume_percent": volumePercent
            ]
        )
    }
    func setBreathingVolume(_ volumePercent: Int) {
        send(operation: "breathing.volume", body: ["volume_percent": volumePercent])
    }
    func stopBreathing() { send(operation: "breathing.stop") }
    func beginRemoteButtonPairing() {
        send(operation: "remote_button.pairing.begin", body: ["duration_seconds": 120])
    }
    func removeRemoteButton(id: String) {
        send(operation: "remote_button.remove", body: ["button_id": id])
    }

    private func send(operation: String, body: [String: Any] = [:]) {
        guard !isBusy else { return }

        let requestID = UUID().uuidString.lowercased()
        let command: [String: Any] = ["v": 1, "id": requestID, "op": operation, "body": body]

        do {
            let data = try JSONSerialization.data(withJSONObject: command, options: [.sortedKeys])
            pageAccumulator = nil
            pendingRequest = PendingRequest(id: requestID, operation: operation)
            isBusy = true
            lastError = nil

            if let httpEndpoint {
                sendOverHTTP(data, to: httpEndpoint, operation: operation)
            } else {
                sendOverBluetooth(data)
            }
        } catch {
            fail(error)
        }
    }

    private func sendOverHTTP(_ data: Data, to endpoint: URL, operation: String) {
        requestTransport = .http

        Task { [weak self] in
            guard let self else { return }

            do {
                var request = URLRequest(
                    url: endpoint,
                    timeoutInterval: operation.hasPrefix("hue.") || operation.hasPrefix("breathing.") ? 20 : 5
                )
                request.httpMethod = "POST"
                request.httpBody = data
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                let (responseData, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw TransportError.httpRejected
                }

                activeTransport = .http
                handleResponse(responseData)
            } catch {
                fallbackToBluetooth(data, httpError: error)
            }
        }
    }

    private func fallbackToBluetooth(_ data: Data, httpError: Error) {
        forgetHTTPTransport()

        guard bluetoothReady else {
            finishRequest()
            reconnect()
            lastError = TransportError.unreachable(httpError.localizedDescription).localizedDescription
            return
        }

        sendOverBluetooth(data)
    }

    private func sendOverBluetooth(_ data: Data) {
        guard let peripheral, commandCharacteristic != nil, responseCharacteristic != nil else {
            fail(TransportError.bluetoothUnavailable)
            return
        }

        requestTransport = .bluetooth
        var framed = data
        framed.append(0x0A)
        let writeLength = max(20, peripheral.maximumWriteValueLength(for: .withResponse))
        writeChunks = framed.chunked(maximumLength: writeLength)
        writeNextChunk()
    }

    private func writeNextChunk() {
        guard let peripheral, let commandCharacteristic, !writeChunks.isEmpty else { return }
        peripheral.writeValue(writeChunks.removeFirst(), for: commandCharacteristic, type: .withResponse)
    }

    private func consumePage(_ data: Data) throws -> Data? {
        let page = try ResponsePage(data: data)

        if pageAccumulator == nil {
            guard page.index == 0 else {
                throw BluetoothError.invalidTransport("La première page est manquante")
            }
            pageAccumulator = PageAccumulator(
                sequence: page.sequence,
                pageCount: page.count,
                totalBytes: page.totalBytes,
                crc32: page.crc32,
                nextPageIndex: 0,
                payload: Data()
            )
        }

        guard var accumulator = pageAccumulator,
              page.sequence == accumulator.sequence,
              page.index == accumulator.nextPageIndex,
              page.count == accumulator.pageCount,
              page.totalBytes == accumulator.totalBytes,
              page.crc32 == accumulator.crc32 else {
            throw BluetoothError.invalidTransport("Pages incohérentes ou désordonnées")
        }

        accumulator.payload.append(page.payload)
        accumulator.nextPageIndex += 1
        pageAccumulator = accumulator

        guard page.isFinal else { return nil }
        guard accumulator.nextPageIndex == accumulator.pageCount,
              accumulator.payload.count == accumulator.totalBytes,
              accumulator.payload.crc32 == accumulator.crc32 else {
            throw BluetoothError.invalidTransport("Réponse Bluetooth incomplète ou corrompue")
        }

        pageAccumulator = nil
        return accumulator.payload
    }

    private func handleResponse(_ data: Data) {
        do {
            let base = try JSONDecoder().decode(BaseEnvelope.self, from: data)
            guard base.v == 1 else { throw BluetoothError.unsupportedVersion(base.v) }
            guard base.id == pendingRequest?.id else { throw BluetoothError.responseMismatch }
            guard base.status == "ok" else {
                throw BluetoothError.commandRejected(base.error?.code ?? "unknown_error")
            }

            if pendingRequest?.operation == "state.get" {
                let envelope = try JSONDecoder().decode(StateEnvelope.self, from: data)
                guard let stateBody = envelope.body else {
                    throw BluetoothError.invalidResponse
                }
                alarms = stateBody.alarms.sorted { $0.localTime < $1.localTime }
                sounds = stateBody.sounds
                device = stateBody.device
                recentSessions = stateBody.recentSessions
                activeSession = stateBody.activeSession
                hue = stateBody.hue
                breathingSynchronizedAt = stateBody.hue?.breathing?.active == true ? .now : nil
                hueTargets = stateBody.hueTargets ?? []
                remoteButton = stateBody.remoteButton
                rememberHTTPTransport(stateBody.transport)
                lastUpdated = .now
                finishRequest()
            } else if pendingRequest?.operation == "session.get" {
                let envelope = try JSONDecoder().decode(SessionEnvelope.self, from: data)
                activeSession = envelope.body?.activeSession
                finishRequest()
            } else {
                finishRequest()
                refresh()
            }
        } catch {
            fail(error)
        }
    }

    private func finishRequest() {
        isBusy = false
        pendingRequest = nil
        writeChunks.removeAll(keepingCapacity: true)
        requestTransport = nil
    }

    private func rememberHTTPTransport(_ transport: RobineState.Transport?) {
        guard let candidate = transport?.httpEndpoints.first,
              let url = URL(string: candidate),
              url.scheme == "http" || url.scheme == "https" else { return }

        let changed = httpEndpoint != url
        httpEndpoint = url
        UserDefaults.standard.set(candidate, forKey: Self.endpointDefaultsKey)

        if changed {
            eventStreamTask?.cancel()
            eventStreamTask = nil
        }
        startEventStream()
    }

    private func forgetHTTPTransport() {
        httpEndpoint = nil
        UserDefaults.standard.removeObject(forKey: Self.endpointDefaultsKey)
        eventStreamTask?.cancel()
        eventStreamTask = nil
    }

    private func startEventStream() {
        guard eventStreamTask == nil,
              let commandEndpoint = httpEndpoint,
              var components = URLComponents(url: commandEndpoint, resolvingAgainstBaseURL: false) else { return }

        components.path = "/api/v1/events"
        components.query = nil
        guard let eventURL = components.url else { return }

        eventStreamTask = Task { [weak self] in
            await self?.runEventStream(eventURL)
        }
    }

    private func runEventStream(_ url: URL) async {
        var reconnectNanoseconds: UInt64 = 1_000_000_000

        while !Task.isCancelled {
            do {
                try await consumeEventStream(url)
                reconnectNanoseconds = 1_000_000_000
            } catch is CancellationError {
                return
            } catch {
                reconnectNanoseconds = min(reconnectNanoseconds * 2, 10_000_000_000)
            }

            try? await Task.sleep(nanoseconds: reconnectNanoseconds)
        }
    }

    private func consumeEventStream(_ url: URL) async throws {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let lastID = UserDefaults.standard.integer(forKey: Self.eventIDDefaultsKey)
        if lastID > 0 {
            request.setValue(String(lastID), forHTTPHeaderField: "Last-Event-ID")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TransportError.httpRejected
        }

        var eventName: String?
        var eventID: Int?
        var eventData = Data()

        for try await line in bytes.lines {
            try Task.checkCancellation()

            if line.isEmpty {
                if let eventName {
                    receiveServerEvent(name: eventName, id: eventID, data: eventData)
                }
                eventName = nil
                eventID = nil
                eventData.removeAll(keepingCapacity: true)
            } else if line.hasPrefix("event:") {
                eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("id:") {
                eventID = Int(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("data:") {
                let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if !eventData.isEmpty { eventData.append(0x0A) }
                eventData.append(contentsOf: value.utf8)
            }
        }

        throw TransportError.eventStreamEnded
    }

    private func receiveServerEvent(name: String, id: Int?, data: Data) {
        if let id {
            UserDefaults.standard.set(id, forKey: Self.eventIDDefaultsKey)
        }

        if name == "breathing.changed",
           let envelope = try? JSONDecoder().decode(ServerEventEnvelope.self, from: data),
           let synchronizedHue = envelope.data?.hue {
            hue = synchronizedHue
            breathingSynchronizedAt = synchronizedHue.breathing?.active == true ? .now : nil
            return
        }

        guard !isBusy else { return }

        switch name {
        case "ready", "state.changed": refresh()
        case "session.changed": refreshSession()
        default: break
        }
    }

    private func fail(_ error: Error) {
        finishRequest()
        pageAccumulator = nil
        lastError = (error as? BluetoothError)?.localizedDescription ?? error.localizedDescription
    }
}

extension BluetoothAlarmClient: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            state = .bluetoothUnavailable
            return
        }
        reconnect()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        central.stopScan()
        self.peripheral = peripheral
        signalStrength = RSSI.intValue
        peripheral.delegate = self
        state = .connecting
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connected
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        state = .disconnected
        commandCharacteristic = nil
        responseCharacteristic = nil
        signalStrength = nil
        if requestTransport == .bluetooth { finishRequest() }
        reconnect()
    }
}

extension BluetoothAlarmClient: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return fail(error!) }
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics([Self.commandUUID, Self.responseUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else { return fail(error!) }

        service.characteristics?.forEach { characteristic in
            switch characteristic.uuid {
            case Self.commandUUID: commandCharacteristic = characteristic
            case Self.responseUUID: responseCharacteristic = characteristic
            default: break
            }
        }

        if commandCharacteristic != nil, responseCharacteristic != nil { refresh() }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            fail(error)
        } else if !writeChunks.isEmpty {
            writeNextChunk()
        } else if let responseCharacteristic {
            peripheral.readValue(for: responseCharacteristic)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            fail(error)
        } else if let value = characteristic.value {
            do {
                if let response = try consumePage(value) {
                    activeTransport = .bluetooth
                    handleResponse(response)
                } else if let responseCharacteristic {
                    peripheral.readValue(for: responseCharacteristic)
                }
            } catch {
                fail(error)
            }
        }
    }
}

private enum BluetoothError: LocalizedError {
    case commandRejected(String)
    case invalidTransport(String)
    case unsupportedVersion(Int)
    case responseMismatch
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .commandRejected(let code):
            return [
                "stale_revision": "Cette alarme a changé. Actualisez avant de réessayer.",
                "not_found": "Cet élément n’existe plus sur le réveil.",
                "validation_failed": "Certains réglages ne sont pas valides.",
                "hue_link_button_required": "Appuyez sur le bouton rond du pont Hue, puis réessayez.",
                "invalid_hue_bridge_address": "L’adresse du pont Hue n’est pas valide.",
                "hue_pairing_failed": "Le pont Hue a refusé l’association.",
                "hue_target_not_found": "Cette pièce ou zone Hue n’est plus disponible.",
                "wake_session_active": "Une alarme utilise déjà la lumière Hue.",
                "unsupported_operation": "Cette fonction nécessite une version plus récente du réveil.",
                "pairing_window_closed": "La fenêtre d’association du bouton est fermée.",
                "remote_button_not_paired": "Ce bouton n’est plus associé au réveil."
            ][code] ?? "Le réveil a refusé la commande (\(code))."
        case .invalidTransport(let message): return message
        case .unsupportedVersion(let version): return "Version Bluetooth non prise en charge : \(version)."
        case .responseMismatch: return "La réponse ne correspond pas à la commande envoyée."
        case .invalidResponse: return "Le réveil a envoyé une réponse incomplète."
        }
    }
}

private enum TransportError: LocalizedError {
    case httpRejected
    case bluetoothUnavailable
    case unreachable(String)
    case eventStreamEnded

    var errorDescription: String? {
        switch self {
        case .httpRejected:
            return "Le réveil a refusé la connexion HTTP."
        case .bluetoothUnavailable:
            return "Le réveil est inaccessible en Wi-Fi et en Bluetooth."
        case .unreachable:
            return "Le réveil est inaccessible sur le réseau local. Recherche Bluetooth en cours…"
        case .eventStreamEnded:
            return "Le flux d’événements du réveil a été interrompu."
        }
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    func uint32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24) |
            (UInt32(self[offset + 1]) << 16) |
            (UInt32(self[offset + 2]) << 8) |
            UInt32(self[offset + 3])
    }

    var crc32: UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in self {
            var value = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                value = value & 1 == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
            }
            crc = (crc >> 8) ^ value
        }
        return crc ^ 0xFFFF_FFFF
    }

    func chunked(maximumLength: Int) -> [Data] {
        stride(from: 0, to: count, by: maximumLength).map { offset in
            subdata(in: offset..<Swift.min(offset + maximumLength, count))
        }
    }
}
