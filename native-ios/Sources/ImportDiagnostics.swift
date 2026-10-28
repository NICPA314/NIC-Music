import Foundation

// Local debug-build trace: no source paths, filenames or metadata are recorded.
// This also survives simulator logging failures while testing document providers.
enum ImportDiagnostics {
    static func record(_ event: String) {
#if DEBUG
        guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let data = "\(Date().timeIntervalSince1970) \(event)\n".data(using: .utf8) else { return }
        let url = cache.appendingPathComponent("ImportDiagnostics.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let file = try? FileHandle(forWritingTo: url) else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: data)
#endif
    }
}
