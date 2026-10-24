import Foundation

/// One RoomPlan surface or object in our own stable schema (`walls.json`).
/// `transform` is 16 floats, column-major; `dimensions` is RoomPlan's [x, y, z] in meters.
public struct SurfaceRecord: Codable, Equatable {
    public var kind: String
    public var category: String
    public var transform: [Float]
    public var dimensions: [Float]
    public var confidence: String

    public init(kind: String, category: String, transform: [Float], dimensions: [Float], confidence: String) {
        self.kind = kind
        self.category = category
        self.transform = transform
        self.dimensions = dimensions
        self.confidence = confidence
    }
}

/// The RoomPlan pass result, decoupled from `CapturedRoom`'s private Codable layout.
public struct RoomSummary: Codable, Equatable {
    public var schemaVersion: Int
    public var walls: [SurfaceRecord]
    public var doors: [SurfaceRecord]
    public var windows: [SurfaceRecord]
    public var openings: [SurfaceRecord]
    public var objects: [SurfaceRecord]

    public init(schemaVersion: Int = ScanKit.schemaVersion, walls: [SurfaceRecord], doors: [SurfaceRecord],
                windows: [SurfaceRecord], openings: [SurfaceRecord], objects: [SurfaceRecord]) {
        self.schemaVersion = schemaVersion
        self.walls = walls
        self.doors = doors
        self.windows = windows
        self.openings = openings
        self.objects = objects
    }
}
