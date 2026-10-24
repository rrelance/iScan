import Foundation

/// Top-level description of a scan bundle, written last as `manifest.json`.
public struct Manifest: Codable, Equatable {
    public struct RoomPassInfo: Codable, Equatable {
        public var surfaceCount: Int
        public var objectCount: Int

        public init(surfaceCount: Int, objectCount: Int) {
            self.surfaceCount = surfaceCount
            self.objectCount = objectCount
        }
    }

    public struct DetailPassInfo: Codable, Equatable {
        public var frameCount: Int
        public var meshFaceCount: Int

        public init(frameCount: Int, meshFaceCount: Int) {
            self.frameCount = frameCount
            self.meshFaceCount = meshFaceCount
        }
    }

    public var schemaVersion: Int
    public var scanId: String
    public var createdAt: Date
    public var device: String
    public var systemVersion: String
    public var units: String
    public var sessionReused: Bool
    /// Nil when the user skipped the RoomPlan pass.
    public var roomPass: RoomPassInfo?
    public var detailPass: DetailPassInfo

    public init(schemaVersion: Int = ScanKit.schemaVersion, scanId: String, createdAt: Date, device: String,
                systemVersion: String, units: String = "meters", sessionReused: Bool,
                roomPass: RoomPassInfo?, detailPass: DetailPassInfo) {
        self.schemaVersion = schemaVersion
        self.scanId = scanId
        self.createdAt = createdAt
        self.device = device
        self.systemVersion = systemVersion
        self.units = units
        self.sessionReused = sessionReused
        self.roomPass = roomPass
        self.detailPass = detailPass
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
