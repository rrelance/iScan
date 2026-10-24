import Foundation
import RoomPlan
import ScanKit

/// Writes the RoomPlan result: Apple's own `room.json` and `room.usdz`, plus our stable `walls.json`.
enum RoomExport {
    static func summary(_ room: CapturedRoom) -> RoomSummary {
        func records(_ surfaces: [CapturedRoom.Surface], kind: String) -> [SurfaceRecord] {
            surfaces.map {
                SurfaceRecord(kind: kind, category: String(describing: $0.category), transform: flatten($0.transform),
                              dimensions: [$0.dimensions.x, $0.dimensions.y, $0.dimensions.z],
                              confidence: String(describing: $0.confidence))
            }
        }
        let objects = room.objects.map {
            SurfaceRecord(kind: "object", category: String(describing: $0.category), transform: flatten($0.transform),
                          dimensions: [$0.dimensions.x, $0.dimensions.y, $0.dimensions.z],
                          confidence: String(describing: $0.confidence))
        }
        return RoomSummary(walls: records(room.walls, kind: "wall"), doors: records(room.doors, kind: "door"),
                           windows: records(room.windows, kind: "window"),
                           openings: records(room.openings, kind: "opening"), objects: objects)
    }

    static func write(_ room: CapturedRoom, to dir: URL) throws {
        try JSONEncoder().encode(room).write(to: dir.appendingPathComponent(BundleLayout.roomJSON), options: .atomic)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(summary(room)).write(to: dir.appendingPathComponent(BundleLayout.walls), options: .atomic)
        try room.export(to: dir.appendingPathComponent(BundleLayout.roomUSDZ))
    }
}
