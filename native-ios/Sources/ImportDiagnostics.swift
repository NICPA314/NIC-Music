import Foundation

// Bounded local diagnostics also ship in test IPAs. No source paths, filenames
// or music metadata are recorded, and nothing is sent over the network.
enum ImportDiagnostics {
    private static let lock = NSLock()
    static var version: String {
        "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))"
    }
    private static var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("NIC-Music.log")
    }
    static func report() -> String {
        lock.lock(); defer { lock.unlock() }
        let events = fileURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "尚无导入记录"
        return "NIC Music \(version)\niOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n\(events)"
    }
    static func record(_ event: String) {
        // Off by default. CI test IPAs explicitly opt in, including Release builds.
        let setting = Bundle.main.object(forInfoDictionaryKey: "NICDiagnosticLoggingEnabled")
        guard (setting as? Bool == true) || (setting as? String == "YES") else { return }
        lock.lock(); defer { lock.unlock() }
        guard let url = fileURL,
              let data = "\(Date().timeIntervalSince1970) \(event)\n".data(using: .utf8) else { return }
        if let old = try? Data(contentsOf: url), old.count > 65536 {
            try? Data(old.suffix(32768)).write(to: url, options: .atomic)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let header = "NIC Music \(version)\niOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
            FileManager.default.createFile(atPath: url.path, contents: header.data(using: .utf8))
        }
        guard let file = try? FileHandle(forWritingTo: url) else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: data)
    }
}
