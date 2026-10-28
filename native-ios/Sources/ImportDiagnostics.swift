import Foundation

// Bounded local diagnostics also ship in test IPAs. No source paths, filenames
// or music metadata are recorded, and nothing is sent over the network.
enum ImportDiagnostics {
    private static let lock = NSLock()
    static var version: String {
        "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))"
    }
    private static var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("ImportDiagnostics.log")
    }
    static func report() -> String {
        lock.lock(); defer { lock.unlock() }
        let events = fileURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "尚无导入记录"
        return "NIC Music \(version)\niOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n\(events)"
    }
    static func record(_ event: String) {
        lock.lock(); defer { lock.unlock() }
        guard let url = fileURL,
              let data = "\(Date().timeIntervalSince1970) \(event)\n".data(using: .utf8) else { return }
        if let old = try? Data(contentsOf: url), old.count > 65536 {
            try? Data(old.suffix(32768)).write(to: url, options: .atomic)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let file = try? FileHandle(forWritingTo: url) else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: data)
    }
}
