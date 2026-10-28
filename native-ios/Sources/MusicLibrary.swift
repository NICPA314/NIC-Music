import SwiftUI
import AVFoundation
import MediaPlayer

struct Song: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var artist: String
    var filename: String
    var artwork: Data?
    var lyrics: String?
    var lyricKind: String?
    var videoFilename: String?
    var customArtwork: Bool?
    var album: String?
    var albumArtist: String?
    var releaseDate: String?
    var copyright: String?
    var recordLabel: String?
    var genre: String?
    var composer: String?
    var trackNumber: Int?
    var discNumber: Int?
    var quality: AudioQuality?
    var favorite: Bool?
    var contentHash: String?
    var libraryAlbumTitle: String?
    var libraryAlbumKey: String?
    var sourceNumber: Int?
    var storagePlaylistID: UUID?
    var artworkFilename: String?
    var videoAspectRatio: Double?
    var albumTitle: String { libraryAlbumTitle ?? album ?? "未知专辑" }
    var metadataAlbumKey: String { Self.normalized(album ?? "未知专辑") + "\u{1F}" + Self.normalized(albumArtist ?? artist) }
    var albumKey: String { libraryAlbumKey ?? metadataAlbumKey }
    static func normalized(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased() }
    static func playlistOrder(_ a: Song, _ b: Song) -> Bool {
        if a.sourceNumber != b.sourceNumber, a.sourceNumber != nil || b.sourceNumber != nil { return (a.sourceNumber ?? Int.max) < (b.sourceNumber ?? Int.max) }
        for (left, right) in [(a.artist, b.artist), (a.releaseDate ?? "9999", b.releaseDate ?? "9999"), (a.album ?? "", b.album ?? "")] {
            if left != right { return left.localizedStandardCompare(right) == .orderedAscending }
        }
        if a.discNumber != b.discNumber { return (a.discNumber ?? 1) < (b.discNumber ?? 1) }
        if a.trackNumber != b.trackNumber { return (a.trackNumber ?? Int.max) < (b.trackNumber ?? Int.max) }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}

@MainActor @Observable final class MusicLibrary: NSObject, AVAudioPlayerDelegate {
    var songs: [Song] = []
    var playlists: [Playlist] = []
    var artistArtwork: [String: Data] = [:]
    var currentID: UUID?
    private var queueIDs: [UUID] = []
    var queue: [Song] { queueIDs.compactMap { id in songs.first { $0.id == id } } }
    var playing = false
    var position: Double = 0
    var duration: Double = 0
    var importing = false
    var importProgress = ""
    var importSummary: String?
    var importingAttachment = false
    var error: String?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    let folder: URL
    var current: Song? { songs.first { $0.id == currentID } }
    var librarySongs: [Song] { songs.filter { $0.storagePlaylistID == nil } }
    override convenience init() {
        self.init(folder: URL.documentsDirectory.appendingPathComponent("Music", isDirectory: true))
    }
    init(folder: URL) {
        self.folder = folder
        super.init()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let index = folder.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: index.path) { songs = try JSONDecoder().decode([Song].self, from: Data(contentsOf: index)) }
            for i in songs.indices {
                if let file = songs[i].artworkFilename { songs[i].artwork = try? Data(contentsOf: folder.appendingPathComponent(file)) }
            }
            let lists = folder.appendingPathComponent("playlists.json")
            if FileManager.default.fileExists(atPath: lists.path) { playlists = try JSONDecoder().decode([Playlist].self, from: Data(contentsOf: lists)) }
            let artists = folder.appendingPathComponent("artists.json")
            if FileManager.default.fileExists(atPath: artists.path) { artistArtwork = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: artists)) }
        } catch { self.error = "资料库读取失败：\(error.localizedDescription)" }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next(1) }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next(-1) }; return .success }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.pause() } }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self, let player = self.player else { return }; self.position = player.currentTime }
        }
    }
    func save() {
        do { try persist(songs) }
        catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
    private func persist(_ value: [Song]) throws {
        // Keep large cover blobs out of the index, which is atomically updated per song.
        let index = value.map { song in var entry = song; if entry.artworkFilename != nil { entry.artwork = nil }; return entry }
        try JSONEncoder().encode(index).write(to: folder.appendingPathComponent("library.json"), options: .atomic)
    }
    func importDirectory(_ directory: URL, playlistID: UUID? = nil) async {
        guard !importing else { return }
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        importing = true; importSummary = nil; importProgress = "正在扫描文件夹…"
        do {
            let urls = try await MusicFileImporter.shared.audioFiles(in: directory)
            importing = false
            if urls.isEmpty { importSummary = "文件夹中没有可导入的音频。"; importProgress = "" }
            else { await importSongs(urls, companions: true, playlistID: playlistID, folderRoot: directory) }
        } catch { importing = false; importProgress = ""; self.error = "文件夹读取失败：\(error.localizedDescription)" }
    }
    func importSongs(_ urls: [URL], companions: Bool = false, playlistID: UUID? = nil, folderRoot: URL? = nil) async {
        guard !importing, !urls.isEmpty else { return }
        importing = true
        NSLog("NICImport: starting coordinated import of %ld file(s)", urls.count)
        importSummary = nil
        defer { importing = false; importProgress = "" }
        var imported = 0
        var skipped = 0
        var directoryAlbums: [String: (key: String, title: String)] = [:]
        var failures: [String] = []
        var importedIDs: [UUID] = []
        for (index, url) in urls.enumerated() {
            importProgress = "正在读取音频和元数据 \(index + 1)/\(urls.count)：\(url.lastPathComponent)"
            var copied: Song?
            do {
                var song = try await MusicFileImporter.shared.importAudio(url, into: folder, companions: companions)
                copied = song
                if let hash = song.contentHash, let existing = songs.first(where: { $0.contentHash == hash && $0.storagePlaylistID == playlistID }) {
                    importedIDs.append(existing.id); skipped += 1
                    try? FileManager.default.removeItem(at: folder.appendingPathComponent(song.filename))
                    if let video = song.videoFilename { try? FileManager.default.removeItem(at: folder.appendingPathComponent(video)) }
                    continue
                }
                let directory = url.deletingLastPathComponent()
                let existingAlbum = librarySongs.first { $0.metadataAlbumKey == song.metadataAlbumKey }
                if playlistID == nil, let root = folderRoot, directory.standardizedFileURL != root.standardizedFileURL {
                    let title = directory.lastPathComponent
                    let folderKey = "folder:" + Song.normalized(title) + "\u{1F}" + Song.normalized(song.albumArtist ?? song.artist)
                    let match = librarySongs.first { $0.albumKey == folderKey } ?? librarySongs.first {
                        $0.metadataAlbumKey == song.metadataAlbumKey && ($0.libraryAlbumKey == nil || Song.normalized($0.albumTitle) == Song.normalized(title))
                    }
                    let group = directoryAlbums[directory.path] ?? (key: match?.albumKey ?? folderKey, title: match?.albumTitle ?? title)
                    directoryAlbums[directory.path] = group
                    song.libraryAlbumKey = group.key; song.libraryAlbumTitle = group.title
                } else if let existingAlbum {
                    song.libraryAlbumKey = existingAlbum.albumKey; song.libraryAlbumTitle = existingAlbum.albumTitle
                }
                song.storagePlaylistID = playlistID
                let location: [String]
                if let playlistID, let playlist = playlists.first(where: { $0.id == playlistID }) {
                    location = ["Playlists", playlist.name + "-" + playlistID.uuidString.prefix(8)]
                } else if let stored = librarySongs.first(where: { $0.albumKey == song.albumKey && $0.filename.hasPrefix("Albums/") }) {
                    location = stored.filename.split(separator: "/").dropLast().map(String.init)
                } else { location = ["Albums", song.albumArtist ?? song.artist, song.albumTitle] }
                song.filename = try await MusicFileImporter.shared.place(song.filename, in: folder, location: location, originalName: url.lastPathComponent)
                copied = song
                if let video = song.videoFilename {
                    song.videoFilename = try await MusicFileImporter.shared.place(video, in: folder, location: location, originalName: url.deletingPathExtension().lastPathComponent + ".cover.mp4")
                    copied = song
                }
                if let artwork = song.artwork {
                    song.artworkFilename = try await MusicFileImporter.shared.storeArtwork(artwork, beside: song.filename, in: folder)
                    copied = song
                }
                importProgress = "正在保存 \(index + 1)/\(urls.count)：\(url.lastPathComponent)"
                let updated = songs + [song]
                try persist(updated)
                songs = updated
                imported += 1
                importedIDs.append(song.id)
            } catch {
                if let copied { try? FileManager.default.removeItem(at: folder.appendingPathComponent(copied.filename)) }
                if let video = copied?.videoFilename { try? FileManager.default.removeItem(at: folder.appendingPathComponent(video)) }
                if let artwork = copied?.artworkFilename { try? FileManager.default.removeItem(at: folder.appendingPathComponent(artwork)) }
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        if let playlistID, let i = playlists.firstIndex(where: { $0.id == playlistID }) {
            let sorted = songs.filter { importedIDs.contains($0.id) }.sorted(by: Song.playlistOrder).map(\.id)
            playlists[i].songIDs += sorted.filter { !playlists[i].songIDs.contains($0) }
            savePlaylists()
        }
        importSummary = "已导入 \(imported) 首歌曲，跳过 \(skipped) 首重复歌曲" + (failures.isEmpty ? "。" : "，\(failures.count) 个文件失败。\n" + failures.joined(separator: "\n"))
        NSLog("NICImport: completed %ld, skipped %ld, failed %ld", imported, skipped, failures.count)
    }
    func createPlaylist(_ name: String) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        playlists.append(Playlist(name: title)); savePlaylists()
    }
    private func savePlaylists() {
        do { try JSONEncoder().encode(playlists).write(to: folder.appendingPathComponent("playlists.json"), options: .atomic) }
        catch { self.error = "播放列表保存失败：\(error.localizedDescription)" }
    }
    func toggleFavorite() {
        guard let i = songs.firstIndex(where: { $0.id == currentID }) else { return }
        songs[i].favorite = !(songs[i].favorite ?? false); save()
    }
    func setArtistArtwork(_ url: URL, artist: String) async {
        do {
            let (file, data) = try await MusicFileImporter.shared.importCover(url, video: false, into: folder)
            defer { try? FileManager.default.removeItem(at: file) }
            var updated = artistArtwork; updated[artist] = data
            try JSONEncoder().encode(updated).write(to: folder.appendingPathComponent("artists.json"), options: .atomic)
            artistArtwork = updated
        } catch { self.error = "艺人封面保存失败：\(error.localizedDescription)" }
    }
    func play(_ song: Song, queue: [Song]? = nil) {
        do {
            if let queue { queueIDs = queue.map(\.id) }
            else if !queueIDs.contains(song.id) {
                if let id = song.storagePlaylistID, let playlist = playlists.first(where: { $0.id == id }) { queueIDs = playlist.songIDs }
                else { queueIDs = librarySongs.map(\.id) }
            }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let next = try AVAudioPlayer(contentsOf: folder.appendingPathComponent(song.filename))
            player?.stop(); player = next; next.delegate = self
            currentID = song.id; position = 0; duration = next.duration
            playing = next.play(); nowPlaying()
        } catch { self.error = "播放失败：\(error.localizedDescription)" }
    }
    func resume() { playing = player?.play() ?? false; nowPlaying() }
    func pause() { player?.pause(); playing = false; nowPlaying() }
    func toggle() { playing ? pause() : resume() }
    func seek(_ seconds: Double) { player?.currentTime = min(max(seconds,0),duration); position = player?.currentTime ?? 0; nowPlaying() }
    func next(_ step: Int) { let ordered = queue; guard let i = ordered.firstIndex(where: { $0.id == currentID }), !ordered.isEmpty else { return }; play(ordered[(i+step+ordered.count)%ordered.count]) }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in if flag { self.next(1) } else { self.pause() } } }
    func addLyrics(_ url: URL, to id: UUID) async {
        guard !importingAttachment else { return }
        importingAttachment = true
        defer { importingAttachment = false }
        do {
            let text = try await MusicFileImporter.shared.readLyrics(url)
            guard let i = songs.firstIndex(where: { $0.id == id }) else { return }
            var updated = songs
            updated[i].lyrics = text; updated[i].lyricKind = url.pathExtension.lowercased()
            try persist(updated); songs = updated
        } catch { self.error = "歌词导入失败：\(error.localizedDescription)" }
    }
    func addCover(_ url: URL, video: Bool, to id: UUID) async {
        guard !importingAttachment else { return }
        importingAttachment = true
        defer { importingAttachment = false }
        var importedURL: URL?
        var importedArtwork: String?
        do {
            let (file, thumbnail) = try await MusicFileImporter.shared.importCover(url, video: video, into: folder)
            importedURL = file
            guard let i = songs.firstIndex(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
            let previous = songs[i].videoFilename
            let previousArtwork = songs[i].artworkFilename
            let artwork = try await MusicFileImporter.shared.storeArtwork(thumbnail, beside: songs[i].filename, in: folder)
            importedArtwork = artwork
            var videoFilename: String?
            if video {
                let location = songs[i].filename.split(separator: "/").dropLast().map(String.init)
                let name = URL(fileURLWithPath: songs[i].filename).deletingPathExtension().lastPathComponent + ".cover." + file.pathExtension.lowercased()
                videoFilename = try await MusicFileImporter.shared.place(file.lastPathComponent, in: folder, location: location, originalName: name)
                importedURL = folder.appendingPathComponent(videoFilename!)
            }
            var updated = songs
            updated[i].artwork = thumbnail; updated[i].customArtwork = true
            updated[i].artworkFilename = artwork
            updated[i].videoFilename = videoFilename
            if video, let preview = UIImage(data: thumbnail) { updated[i].videoAspectRatio = Double(preview.size.width / preview.size.height) }
            else { updated[i].videoAspectRatio = nil }
            try persist(updated); songs = updated
            if !video { try? FileManager.default.removeItem(at: file) }
            nowPlaying()
            if let previous { try? FileManager.default.removeItem(at: folder.appendingPathComponent(previous)) }
            if let previousArtwork { try? FileManager.default.removeItem(at: folder.appendingPathComponent(previousArtwork)) }
        } catch {
            if let importedURL { try? FileManager.default.removeItem(at: importedURL) }
            if let importedArtwork { try? FileManager.default.removeItem(at: folder.appendingPathComponent(importedArtwork)) }
            self.error = "封面导入失败：\(error.localizedDescription)"
        }
    }
    private func nowPlaying() {
        guard let song = current else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle:song.title, MPMediaItemPropertyArtist:song.artist, MPMediaItemPropertyPlaybackDuration:duration, MPNowPlayingInfoPropertyElapsedPlaybackTime:position, MPNowPlayingInfoPropertyPlaybackRate:playing ? 1.0 : 0.0]
        if let data = song.artwork, let image = UIImage(data: data) { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        if let filename = song.videoFilename,
           let key = AnimatedArtworkProvider.key(for: song.videoAspectRatio),
           MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys.contains(key) {
            info[key] = AnimatedArtworkProvider.artwork(url: folder.appendingPathComponent(filename))
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
