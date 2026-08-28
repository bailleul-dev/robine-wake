import Combine
import Darwin
import Foundation

struct DiscoveredHueBridge: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
}

@MainActor
final class HueBridgeDiscovery: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case searching
        case found
        case unavailable
    }

    @Published private(set) var bridges: [DiscoveredHueBridge] = []
    @Published private(set) var state: State = .idle

    private let browser = NetServiceBrowser()
    private var services: [NetService] = []

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        guard state != .searching else { return }
        bridges = []
        services = []
        state = .searching
        browser.searchForServices(ofType: "_hue._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        services.forEach { $0.stop() }
        services = []
        if state == .searching { state = bridges.isEmpty ? .idle : .found }
    }

    private func resolved(_ service: NetService) {
        guard let host = ipv4Address(of: service) ?? normalizedHostName(of: service) else { return }
        let bridge = DiscoveredHueBridge(id: service.name, name: service.name, host: host)

        bridges.removeAll { $0.id == bridge.id }
        bridges.append(bridge)
        bridges.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        state = .found
    }

    private func ipv4Address(of service: NetService) -> String? {
        for address in service.addresses ?? [] {
            let host = address.withUnsafeBytes { bytes -> String? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                let socketAddress = baseAddress.assumingMemoryBound(to: sockaddr.self)
                guard socketAddress.pointee.sa_family == sa_family_t(AF_INET) else { return nil }

                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    socketAddress,
                    socklen_t(address.count),
                    &buffer,
                    socklen_t(buffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )

                return result == 0 ? String(cString: buffer) : nil
            }

            if let host { return host }
        }

        return nil
    }

    private func normalizedHostName(of service: NetService) -> String? {
        service.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

extension HueBridgeDiscovery: @preconcurrency NetServiceBrowserDelegate {
    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        services.removeAll { $0 === service }
        bridges.removeAll { $0.id == service.name }
        state = bridges.isEmpty ? .searching : .found
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        state = .unavailable
    }
}

extension HueBridgeDiscovery: @preconcurrency NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) { resolved(sender) }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        services.removeAll { $0 === sender }
        if services.isEmpty, bridges.isEmpty { state = .unavailable }
    }
}
