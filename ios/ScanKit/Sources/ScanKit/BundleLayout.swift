import Foundation

/// File names and paths inside one scan bundle directory.
public enum BundleLayout {
    public static let manifest = "manifest.json"
    public static let roomJSON = "room.json"
    public static let roomUSDZ = "room.usdz"
    public static let walls = "walls.json"
    public static let mesh = "mesh.ply"
    public static let worldMap = "worldmap.arworldmap"
    public static let framesDir = "frames"

    /// `yyyyMMdd-HHmmss` in the given time zone.
    public static func scanId(for date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    public static func isValidScanId(_ s: String) -> Bool {
        s.range(of: #"^\d{8}-\d{6}$"#, options: .regularExpression) != nil
    }

    /// Paths for frame `index` (1-based, zero-padded to 4 digits).
    public static func framePaths(index: Int) -> (jpg: String, json: String, depth: String, conf: String) {
        let base = "\(framesDir)/" + String(format: "%04d", index)
        return ("\(base).jpg", "\(base).json", "\(base)_depth.png", "\(base)_conf.png")
    }
}
