/// Device-independent scan logic shared by the iScan app. Everything here
/// compiles on macOS so it can be unit-tested on CI without a device.
public enum ScanKit {
    /// Version of the on-disk scan bundle format.
    public static let schemaVersion = 1
}
