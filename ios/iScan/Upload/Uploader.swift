import Foundation
import ScanKit

enum UploadState: Equatable {
    case idle, uploading, done, failed(String)
}

/// Resumable per-file upload of one scan bundle to the PC server.
@MainActor
final class Uploader: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var state: UploadState = .idle

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private struct Status: Decodable { let files: [RemoteFile] }
    private struct RemoteFile: Codable { let path: String; let size: Int }
    private struct Missing: Decodable { let missing: [String] }

    func upload(scanDir: URL, scanId: String, base: URL) async {
        state = .uploading
        progress = 0
        do {
            try await checkHealth(base)
            let local = try UploadPlan.localFiles(in: scanDir)
            try await send(pending(local: local, base: base, scanId: scanId), scanDir: scanDir, scanId: scanId, base: base)

            var missing = try await complete(local, base: base, scanId: scanId)
            if !missing.isEmpty {
                try await send(local.filter { missing.contains($0.path) }, scanDir: scanDir, scanId: scanId, base: base)
                missing = try await complete(local, base: base, scanId: scanId)
            }
            guard missing.isEmpty else {
                throw UploadError.message("The PC is still missing: \(missing.prefix(5).joined(separator: ", "))")
            }
            progress = 1
            state = .done
        } catch {
            state = .failed((error as? UploadError)?.description ?? error.localizedDescription)
        }
    }

    // MARK: Steps

    private func checkHealth(_ base: URL) async throws {
        var request = URLRequest(url: base.appendingPathComponent("api/health"))
        request.timeoutInterval = 5
        do {
            let (_, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        } catch {
            throw UploadError.message("Can't reach \(base.host ?? base.absoluteString). Is the iScan server running "
                                      + "on your PC, and is Windows Firewall allowing port 8787?")
        }
    }

    private func pending(local: [UploadFile], base: URL, scanId: String) async throws -> [UploadFile] {
        let (data, _) = try await session.data(from: base.appendingPathComponent("api/scans/\(scanId)/status"))
        let remote = try JSONDecoder().decode(Status.self, from: data).files.map { UploadFile(path: $0.path, size: $0.size) }
        return UploadPlan.pending(local: local, remote: remote)
    }

    /// Uploads files three at a time (manifest.json alone, last), with retries.
    private func send(_ files: [UploadFile], scanDir: URL, scanId: String, base: URL) async throws {
        let total = max(1, files.reduce(0) { $0 + $1.size })
        var sent = 0
        let body = files.filter { $0.path != BundleLayout.manifest }
        let tail = files.filter { $0.path == BundleLayout.manifest }
        for batch in stride(from: 0, to: body.count, by: 3).map({ Array(body[$0..<min($0 + 3, body.count)]) }) + [tail] {
            try await withThrowingTaskGroup(of: Int.self) { group in
                for file in batch {
                    group.addTask { try await self.put(file, scanDir: scanDir, scanId: scanId, base: base) }
                }
                for try await size in group {
                    sent += size
                    progress = Double(sent) / Double(total) * 0.99
                }
            }
        }
    }

    private nonisolated func put(_ file: UploadFile, scanDir: URL, scanId: String, base: URL) async throws -> Int {
        var request = URLRequest(url: base.appendingPathComponent("api/scans/\(scanId)/files/\(file.path)"))
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let source = scanDir.appendingPathComponent(file.path)
        var lastError: Error = URLError(.unknown)
        for attempt in 0..<4 {
            if attempt > 0 { try await Task.sleep(nanoseconds: UInt64(1 << (attempt - 1)) * 1_000_000_000) }
            do {
                let (_, response) = try await session.upload(for: request, fromFile: source)
                if (response as? HTTPURLResponse)?.statusCode == 200 { return file.size }
                lastError = UploadError.message("The PC rejected \(file.path)")
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func complete(_ local: [UploadFile], base: URL, scanId: String) async throws -> [String] {
        var request = URLRequest(url: base.appendingPathComponent("api/scans/\(scanId)/complete"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["files": local.map { RemoteFile(path: $0.path, size: $0.size) }])
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return []
        case 409: return try JSONDecoder().decode(Missing.self, from: data).missing
        default: throw UploadError.message("The PC couldn't finish the upload")
        }
    }
}

enum UploadError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self { case .message(let m): return m }
    }
}
