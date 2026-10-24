import Foundation

public struct UploadFile: Equatable {
    public var path: String
    public var size: Int

    public init(path: String, size: Int) {
        self.path = path
        self.size = size
    }
}

/// Works out which files of a scan bundle still need to go to the PC.
public enum UploadPlan {
    /// Every file under `dir` as a sorted posix-relative path, skipping dotfiles.
    public static func localFiles(in dir: URL) throws -> [UploadFile] {
        let root = dir.standardizedFileURL.resolvingSymlinksInPath().path
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        var files: [UploadFile] = []
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.resolvingSymlinksInPath().path
            let rel = String(full.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            files.append(UploadFile(path: rel, size: values.fileSize ?? 0))
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Local files the server lacks or has at a different size; `manifest.json` always goes last.
    public static func pending(local: [UploadFile], remote: [UploadFile]) -> [UploadFile] {
        let have = Dictionary(remote.map { ($0.path, $0.size) }, uniquingKeysWith: { a, _ in a })
        let todo = local.filter { have[$0.path] != $0.size }
        return todo.filter { $0.path != BundleLayout.manifest } + todo.filter { $0.path == BundleLayout.manifest }
    }
}
