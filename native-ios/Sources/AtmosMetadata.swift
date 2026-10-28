import Foundation

// EC3SpecificBox extension type A identifies Dolby Digital Plus JOC.
// Unknown or truncated boxes never produce an Atmos badge.
enum AtmosMetadata {
    static func hasJOC(_ data: Data) -> Bool {
        let bytes = Array(data)
        var bit = 0
        func read(_ count: Int) -> Int? {
            guard bit + count <= bytes.count * 8 else { return nil }
            var value = 0
            for _ in 0..<count { value = (value << 1) | Int((bytes[bit / 8] >> (7 - bit % 8)) & 1); bit += 1 }
            return value
        }
        guard read(13) != nil, let streams = read(3) else { return false }
        for _ in 0...streams {
            guard read(19) != nil, let dependent = read(4), read(dependent > 0 ? 9 : 1) != nil else { return false }
        }
        guard let extensionByte = read(8), extensionByte & 1 == 1,
              let complexity = read(8), complexity > 0 else { return false }
        return true
    }
    static func read(_ url: URL) -> Bool {
        guard let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        do {
            let end = try file.seekToEnd(); try file.seek(toOffset: 0)
            for _ in 0..<4096 {
                let position = try file.offset()
                guard position + 8 <= end, let header = try file.read(upToCount: 8), header.count == 8 else { return false }
                var size = header.prefix(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                var headerSize: UInt64 = 8
                if size == 1 {
                    guard let wide = try file.read(upToCount: 8), wide.count == 8 else { return false }
                    size = wide.reduce(0) { ($0 << 8) | UInt64($1) }; headerSize = 16
                } else if size == 0 { size = end - position }
                guard size >= headerSize, size <= end - position else { return false }
                if String(data: header.suffix(4), encoding: .ascii) == "moov" {
                    guard size - headerSize <= 16 * 1024 * 1024,
                          let data = try file.read(upToCount: Int(size - headerSize)) else { return false }
                    return walk(Array(data), 0, data.count, depth: 0, ec3: false)
                }
                try file.seek(toOffset: position + size)
            }
        } catch { return false }
        return false
    }
    private static func walk(_ bytes: [UInt8], _ start: Int, _ end: Int, depth: Int, ec3: Bool) -> Bool {
        guard depth < 12, start <= end, end <= bytes.count else { return false }
        var offset = start
        while offset + 8 <= end {
            let size = bytes[offset..<offset+4].reduce(0) { ($0 << 8) | Int($1) }
            guard size >= 8, size <= end - offset else { return false }
            let kind = String(bytes: bytes[offset+4..<offset+8], encoding: .ascii) ?? ""
            let payload = offset + 8, limit = offset + size
            if kind == "dec3", ec3 { return hasJOC(Data(bytes[payload..<limit])) }
            let skip: Int?
            switch kind {
            case "trak", "mdia", "minf", "stbl": skip = 0
            case "stsd": skip = 8
            case "ec-3": skip = 28
            default: skip = nil
            }
            if let skip, payload + skip <= limit,
               walk(bytes, payload + skip, limit, depth: depth + 1, ec3: ec3 || kind == "ec-3") { return true }
            offset = limit
        }
        return false
    }
}
