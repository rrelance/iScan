import Foundation
import Network

struct DiscoveredServer: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let baseURL: URL
}

/// Finds iScan servers advertised over Bonjour (`_iscan._tcp`) on the local network.
final class ServerDiscovery: ObservableObject {
    @Published private(set) var servers: [DiscoveredServer] = []

    private var browser: NWBrowser?
    private var resolving: [NWConnection] = []

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_iscan._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.servers = []
            results.forEach { self?.resolve($0.endpoint) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolving.forEach { $0.cancel() }
        resolving = []
    }

    /// Opens a throwaway connection to learn the service's host and port.
    private func resolve(_ endpoint: NWEndpoint) {
        guard case let .service(name, _, _, _) = endpoint else { return }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .wifi
        let connection = NWConnection(to: endpoint, using: params)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                if case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint,
                   let url = URL(string: "http://\(Self.hostString(host)):\(port.rawValue)") {
                    let server = DiscoveredServer(name: name, baseURL: url)
                    if !self.servers.contains(server) { self.servers.append(server) }
                }
                connection.cancel()
            case .failed, .cancelled:
                self.resolving.removeAll { $0 === connection }
            default:
                break
            }
        }
        resolving.append(connection)
        connection.start(queue: .main)
    }

    private static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let a):
            return "\(a)".components(separatedBy: "%").first ?? "\(a)"
        case .ipv6(let a):
            return "[\("\(a)".components(separatedBy: "%").first ?? "\(a)")]"
        case .name(let n, _):
            return n
        @unknown default:
            return "\(host)"
        }
    }
}
