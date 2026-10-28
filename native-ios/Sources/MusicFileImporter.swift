import Foundation
import AVFoundation
import UIKit
import CryptoKit

// File-provider coordination and decoding must never block SwiftUI's main actor.
actor MusicFileImporter {
    static let shared = MusicFileImporter()

    func artistPortrait(beside audio: URL, within root: URL) -> Data? {
        let boundary = root.standardizedFileURL.path
        var directory = audio.deletingLastPathComponent().standardizedFileURL
        var directories: [URL] = []
        while directory.path == boundary || directory.path.hasPrefix(boundary + "/") {
            directories.append(directory)
            if directory.path == boundary { break }
            directory.deleteLastPathComponent()
        }
        // Prefer the artist's parent directory to an album's local folder image.
        let candidates = Array(directories.dropFirst()) + Array(directories.prefix(1))
        for directory in candidates {
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for ext in ["jpg", "jpeg", "png", "heic", "webp"] {
                if let file = files.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == "folder" && $0.pathExtension.lowercased() == ext }),
                   let data = try? Data(contentsOf: file), UIImage(data: data) != nil { return data }
            }
        }
        return nil
    }

    func storeArtwork(_ data: Data, beside audio: String, in folder: URL) throws -> String {
        let bytes: Data
        let ext: String
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            bytes = data; ext = "png"
        } else if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            bytes = data; ext = "jpg"
        } else {
            guard let image = UIImage(data: data), let converted = image.pngData() else { throw CocoaError(.fileReadCorruptFile) }
            bytes = converted; ext = "png"
        }
        let stem = (audio as NSString).deletingPathExtension
        let name = stem + ".cover-" + UUID().uuidString.prefix(8) + "." + ext
        try bytes.write(to: folder.appendingPathComponent(name), options: .atomic)
        return name
    }

    func place(_ stagedFilename: String, in folder: URL, location: [String], originalName: String) throws -> String {
        func safe(_ component: String) -> String {
            let invalid = CharacterSet(charactersIn: "/\\:?*<>|\"").union(.controlCharacters)
            let value = component.components(separatedBy: invalid).joined(separator: "_").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            return String((value.isEmpty ? "未命名" : value).prefix(100))
        }
        let relative = location.map(safe).joined(separator: "/")
        let directory = folder.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = safe(originalName)
        var destination = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent(UUID().uuidString.prefix(8) + "-" + name)
        }
        try FileManager.default.moveItem(at: folder.appendingPathComponent(stagedFilename), to: destination)
        return relative + "/" + destination.lastPathComponent
    }

    func copy(_ source: URL, into folder: URL) throws -> URL {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
        var coordinationError: NSError?
        var copyError: Error?
        var copied = false
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
            do { try FileManager.default.copyItem(at: readableURL, to: destination); copied = true }
            catch { copyError = error }
        }
        if let failure = coordinationError ?? (copyError as NSError?) {
            try? FileManager.default.removeItem(at: destination)
            throw failure
        }
        guard copied else { throw CocoaError(.fileReadUnknown) }
        return destination
    }

    func importAudio(_ source: URL, into folder: URL, companions: Bool = false, progress: @Sendable (String) async -> Void = { _ in }) async throws -> Song {
        await progress("正在复制到应用")
        ImportDiagnostics.record("audio copy started")
        let destination = try copy(source, into: folder.appendingPathComponent("Audio", isDirectory: true))
        ImportDiagnostics.record("audio copy completed")
        var videoCopy: URL?
        var videoAspectRatio: Double?
        do {
            await progress("正在验证音频")
            let audio = try AVAudioPlayer(contentsOf: destination)
            guard audio.duration > 0, audio.prepareToPlay() else { throw CocoaError(.fileReadCorruptFile) }
            await progress("正在读取元数据")
            ImportDiagnostics.record("metadata started")
            let tags = try await Self.metadata(at: destination)
            ImportDiagnostics.record("metadata completed, title=\(tags.title != nil)")
            guard let title = tags.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ImportError.missingTitle
            }
            var artwork = tags.artwork.flatMap { UIImage(data: $0) == nil ? nil : $0 }
            var lyrics: String?, lyricKind: String?
            if companions {
                await progress("正在读取封面与歌词")
                let siblings = try FileManager.default.contentsOfDirectory(at: source.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                if artwork == nil {
                    let imageTypes = ["jpg", "jpeg", "png", "heic", "webp"]
                    for ext in imageTypes {
                        if let cover = siblings.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == "cover" && $0.pathExtension.lowercased() == ext }),
                           let data = try? Data(contentsOf: cover), UIImage(data: data) != nil { artwork = data; break }
                    }
                }
                for ext in ["ttml", "lrc"] {
                    if let sidecar = siblings.first(where: { $0.deletingPathExtension().lastPathComponent == source.deletingPathExtension().lastPathComponent && $0.pathExtension.lowercased() == ext }),
                       let text = try? readLyrics(sidecar) { lyrics = text; lyricKind = ext; break }
                }
                for name in ["tall_animated_artwork.mp4", "portrait_animated_artwork.mp4", "square_animated_artwork.mp4", "cover.mp4"] {
                    if let video = siblings.first(where: { $0.lastPathComponent.lowercased() == name }) {
                        if let (file, poster) = try? await importCover(video, video: true, into: folder) {
                            videoCopy = file
                            if let preview = UIImage(data: poster) { videoAspectRatio = Double(preview.size.width / preview.size.height) }
                            if artwork == nil { artwork = poster }
                        }
                        break
                    }
                }
            }
            await progress("正在检查重复文件")
            let handle = try FileHandle(forReadingFrom: destination)
            defer { try? handle.close() }
            var hash = SHA256()
            while let block = try handle.read(upToCount: 1024 * 1024), !block.isEmpty { hash.update(data: block) }
            let fingerprint = hash.finalize().map { String(format: "%02x", $0) }.joined()
            let stem = source.deletingPathExtension().lastPathComponent
            let pattern = #"^\s*(?:\[(\d{1,4})\]|(\d{1,4})[.\s_\-])"#
            let regex = try NSRegularExpression(pattern: pattern)
            var number: Int?
            if let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)) {
                for group in 1...2 { if let range = Range(match.range(at: group), in: stem) { number = Int(stem[range]) } }
            }
            return Song(id: UUID(), title: title, artist: tags.artist ?? "未知艺人",
                        filename: "Audio/" + destination.lastPathComponent, artwork: artwork, lyrics: lyrics,
                        lyricKind: lyricKind, videoFilename: videoCopy?.lastPathComponent, album: tags.album, albumArtist: tags.albumArtist,
                        releaseDate: tags.releaseDate, copyright: tags.copyright, recordLabel: tags.recordLabel,
                        genre: tags.genre, composer: tags.composer, trackNumber: tags.trackNumber,
                        discNumber: tags.discNumber, quality: AudioQuality.read(destination), contentHash: fingerprint, sourceNumber: number,
                        videoAspectRatio: videoAspectRatio)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if let videoCopy { try? FileManager.default.removeItem(at: videoCopy) }
            throw error
        }
    }

    // Preserve embedded tags; a filename is never substituted for the song title.
    static func metadata(at url: URL) async throws -> EmbeddedTags {
        let asset = AVURLAsset(url: url)
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(30)); asset.cancelLoading() } catch {}
        }
        defer { timeout.cancel() }
        var items = (try? await asset.load(.commonMetadata)) ?? []
        // Some containers expose tags only in their native metadata format.
        for format in (try? await asset.load(.availableMetadataFormats)) ?? [] {
            if let native = try? await asset.loadMetadata(for: format) { items += native }
        }
        var tags = EmbeddedTags()
        for item in items {
            if tags.artwork == nil, item.commonKey == .commonKeyArtwork { tags.artwork = try? await item.load(.dataValue); continue }
            let identifier = item.identifier?.rawValue.lowercased() ?? ""
            let key = (item.key as? String)?.lowercased() ?? ""
            let value = try? await item.load(.stringValue)
            if tags.title == nil, item.commonKey == .commonKeyTitle { tags.title = value }
            if tags.artist == nil, item.commonKey == .commonKeyArtist { tags.artist = value }
            if tags.album == nil, item.commonKey == .commonKeyAlbumName { tags.album = value }
            if tags.albumArtist == nil, item.identifier == .iTunesMetadataAlbumArtist { tags.albumArtist = value }
            if tags.copyright == nil, item.commonKey == .commonKeyCopyrights || identifier.hasSuffix("cprt") { tags.copyright = value }
            if tags.releaseDate == nil, item.identifier == .iTunesMetadataReleaseDate || identifier.hasSuffix("©day") || key == "date" || key == "releasetime" { tags.releaseDate = value }
            if tags.recordLabel == nil, key == "label" || key == "publisher" || identifier.hasSuffix("label") || identifier.hasSuffix("publisher") { tags.recordLabel = value }
            if tags.genre == nil, item.identifier == .iTunesMetadataUserGenre || identifier.hasSuffix("©gen") || key == "genre" { tags.genre = value }
            if tags.composer == nil, item.identifier == .iTunesMetadataComposer || identifier.hasSuffix("©wrt") || key == "composer" { tags.composer = value }
            if identifier.hasSuffix("trkn") || identifier.hasSuffix("disk"), let data = try? await item.load(.dataValue), data.count >= 4 {
                let number = Int(data[2]) * 256 + Int(data[3])
                if identifier.hasSuffix("trkn") { tags.trackNumber = number }
                else { tags.discNumber = number }
            }
        }
        return tags
    }

    func audioFiles(in directory: URL) throws -> [URL] {
        var result: [URL] = []
        var scanError: Error?
        let extensions: Set<String> = ["m4a", "mp3", "flac", "wav", "aif", "aiff", "aac", "caf"]
        guard let iterator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in scanError = error; return false }) else { throw CocoaError(.fileReadUnknown) }
        for case let url as URL in iterator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true, values.isSymbolicLink != true, extensions.contains(url.pathExtension.lowercased()) { result.append(url) }
        }
        if let scanError { throw scanError }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    enum ImportError: LocalizedError {
        case missingTitle
        var errorDescription: String? { "未能读取音频内的歌曲标题元数据。文件未入库，请保留源文件以便检查标签兼容性。" }
    }

    func readLyrics(_ source: URL) throws -> String {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Lyrics", isDirectory: true)
        let copy = try copy(source, into: temporary)
        defer { try? FileManager.default.removeItem(at: copy) }
        let data = try Data(contentsOf: copy)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return text
    }

    func importCover(_ source: URL, video: Bool, into folder: URL) async throws -> (URL, Data) {
        let destination = try copy(source, into: folder)
        do {
            let image: UIImage
            if video {
                let asset = AVURLAsset(url: destination)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard !tracks.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 1200, height: 1200)
                let frame = try await generator.image(at: .zero)
                image = UIImage(cgImage: frame.image)
            } else {
                guard let decoded = UIImage(contentsOfFile: destination.path) else { throw CocoaError(.fileReadCorruptFile) }
                image = decoded
            }
            let scale = min(1, 1200 / max(image.size.width, image.size.height))
            let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            guard let data = thumbnail.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileReadCorruptFile) }
            return (destination, data)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
