import Foundation
import Network

/// Temporary hardware probe for comparing the host app and RemoteMedia extension network policy.
///
/// This is deliberately REST/URLSession-only. It does not connect HAKit, mutate server URL
/// selection, or log credentials. Remove it after the physical-device A/B matrix is complete.
public enum RemoteMediaNetworkDiagnostics {
    private static let fileLock = NSLock()

    public static func record(_ message: String) {
        RemoteMediaLog.logger.info("\(message, privacy: .public)")
        fileLock.lock()
        defer { fileLock.unlock() }

        let url = AppConstants.AppGroupContainer.appendingPathComponent("remote-media-probe.log")
        let line = "\(timestamp()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let existing = try Data(contentsOf: url)
                try (existing + data).write(to: url, options: .atomic)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            RemoteMediaLog.logger.error("network diagnostics file log failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public static func runHost(for server: Server) async {
        let activeURL = await server.activeURL()
        let activeType = server.info.connection.activeURLType.debugDescription
        logSelection(process: "host", activeURL: activeURL, activeType: activeType)

        await authenticatedRequest(
            process: "host",
            target: "internal",
            server: server,
            baseURL: server.info.connection.urlForTroubleshooting(type: .internal)
        )
    }

    public static func runExtension(for snapshot: RemoteMediaSnapshot) async {
        guard let server = Current.servers.server(forServerIdentifier: snapshot.selection.serverId) else {
            record("network diagnostics process=extension server=missing")
            return
        }

        let activeURL = await server.activeURL()
        let activeType = server.info.connection.activeURLType.debugDescription
        logSelection(process: "extension", activeURL: activeURL, activeType: activeType)

        let internalURL = server.info.connection.urlForTroubleshooting(type: .internal)
        await authenticatedRequest(
            process: "extension",
            target: "internal",
            server: server,
            baseURL: internalURL
        )

        if let internalURL,
           let host = internalURL.host,
           let address = ipv4Addresses(for: host).first,
           let ipURL = replacingHost(internalURL, with: address) {
            await authenticatedRequest(
                process: "extension",
                target: "internal-ip",
                server: server,
                baseURL: ipURL
            )
        } else {
            RemoteMediaLog.logger.info("network diagnostics process=extension target=internal-ip result=unavailable")
        }

        let externalURL = server.info.connection.urlForTroubleshooting(type: .external)
            ?? server.info.connection.urlForTroubleshooting(type: .remoteUI)
        await authenticatedRequest(
            process: "extension",
            target: "external",
            server: server,
            baseURL: externalURL
        )

        let publicURL = publicArtworkURL(from: snapshot.artworkPath)
            ?? URL(string: "https://placehold.co/32x32.png")
        await publicRequest(process: "extension", target: "public", url: publicURL)
    }

    private static func logSelection(process: String, activeURL: URL?, activeType: String) {
        guard let activeURL else {
            record("network diagnostics process=\(process) active=none")
            return
        }
        let message = "network diagnostics process=\(process) target=active " +
            "scheme=\(activeURL.scheme ?? "none") host=<redacted> port=\(port(for: activeURL)) " +
            "activeType=\(activeType)"
        record(message)
    }

    private static func authenticatedRequest(
        process: String,
        target: String,
        server: Server,
        baseURL: URL?
    ) async {
        guard let baseURL else {
            record("network diagnostics process=\(process) target=\(target) result=unavailable")
            return
        }

        let path = await pathSnapshot()
        let header = "network diagnostics process=\(process) target=\(target) " +
            "scheme=\(baseURL.scheme ?? "none") host=<redacted> port=\(port(for: baseURL)) " +
            "NWPath status=\(path.status) NWPath unsatisfiedReason=\(path.unsatisfiedReason)"
        record(header)
        let startMessage = "network diagnostics process=\(process) target=\(target) request started " +
            "timestamp=\(timestamp())"
        record(startMessage)

        do {
            let data = try await HomeAssistantRESTClient.send(
                server: server,
                baseURL: baseURL,
                path: [],
                timeout: 10
            )
            let successMessage = "network diagnostics process=\(process) target=\(target) HTTP result=success " +
                "status=2xx bytes=\(data.count) timestamp=\(timestamp())"
            record(successMessage)
        } catch {
            let failureMessage = "network diagnostics process=\(process) target=\(target) " +
                "HTTP result=failure \(errorSummary(error)) timestamp=\(timestamp())"
            record(failureMessage)
        }
    }

    private static func publicRequest(process: String, target: String, url: URL?) async {
        guard let url else {
            record("network diagnostics process=\(process) target=\(target) result=unavailable")
            return
        }

        let path = await pathSnapshot()
        let host = url.host ?? "none"
        let header = "network diagnostics process=\(process) target=\(target) " +
            "scheme=\(url.scheme ?? "none") host=\(host) port=\(port(for: url)) " +
            "NWPath status=\(path.status) NWPath unsatisfiedReason=\(path.unsatisfiedReason)"
        record(header)
        let startMessage = "network diagnostics process=\(process) target=\(target) request started " +
            "timestamp=\(timestamp())"
        record(startMessage)

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let successMessage = "network diagnostics process=\(process) target=\(target) HTTP result=success " +
                "status=\(status) bytes=\(data.count) timestamp=\(timestamp())"
            record(successMessage)
        } catch {
            let failureMessage = "network diagnostics process=\(process) target=\(target) " +
                "HTTP result=failure \(errorSummary(error)) timestamp=\(timestamp())"
            record(failureMessage)
        }
    }

    private static func publicArtworkURL(from path: String?) -> URL? {
        guard let path,
              let url = URL(string: path),
              let host = url.host?.lowercased(),
              host.hasSuffix("mzstatic.com"),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private static func replacingHost(_ url: URL, with host: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.host = host
        return components.url
    }

    private static func ipv4Addresses(for host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let result else { return [] }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = result
        while let info = current {
            guard let address = info.pointee.ai_addr else {
                current = info.pointee.ai_next
                continue
            }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                address,
                info.pointee.ai_addrlen,
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if status == 0 { addresses.append(String(cString: buffer)) }
            current = info.pointee.ai_next
        }
        return addresses
    }

    private struct PathSnapshot {
        let status: String
        let unsatisfiedReason: String
    }

    private static func pathSnapshot() async -> PathSnapshot {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: PathSnapshot(
                    status: String(describing: path.status),
                    unsatisfiedReason: String(describing: path.unsatisfiedReason)
                ))
            }
            monitor.start(queue: DispatchQueue(label: "io.home-assistant.remote-media.path-diagnostics"))
        }
    }

    private static func errorSummary(_ error: Error) -> String {
        if let error = error as? URLError {
            return "type=URLError code=\(error.errorCode)"
        }
        if let error = error as? HomeAssistantRESTError {
            switch error {
            case .invalidResponse: return "type=HomeAssistantRESTError invalidResponse"
            case let .unacceptableStatus(code, _):
                return "type=HomeAssistantRESTError status=\(code)"
            case .tokenUnavailable: return "type=HomeAssistantRESTError tokenUnavailable"
            }
        }
        return "type=\(String(reflecting: type(of: error)))"
    }

    private static func port(for url: URL) -> Int {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }

    private static func timestamp() -> String {
        String(format: "%.3f", Date().timeIntervalSince1970)
    }
}
