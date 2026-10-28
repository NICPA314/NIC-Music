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
}

@MainActor @Observable final class MusicLibrary: NSObject, AVAudioPlayerDelegate {
    var songs: [Song] = []
    var currentID: UUID?
    var playing = false
    var position: Double = 0
    var duration: Double = 0
    var importing = false
    var error: String?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    let folder = URL.documentsDirectory.appendingPathComponent("Music", isDirectory: true)
    var current: Song? { songs.first { $0.id == currentID } }
    override init() {
        super.init()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let index = folder.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: index.path) { songs = try JSONDecoder().decode([Song].self, from: Data(contentsOf: index)) }
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
        do { try JSONEncoder().encode(songs).write(to: folder.appendingPathComponent("library.json"), options: .atomic) }
        catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
    func importSongs(_ urls: [URL]) async {
        importing = true
        defer { importing = false }
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let id = UUID(), filename = UUID().uuidString + "." + url.pathExtension
            let destination = folder.appendingPathComponent(filename)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                // Validate before adding an item that could never be played.
                _ = try AVAudioPlayer(contentsOf: destination)
                let metadata = try await AVURLAsset(url: destination).load(.commonMetadata)
                var title = url.deletingPathExtension().lastPathComponent, artist = "未知艺人"
                var artwork: Data?
                for item in metadata {
                    if item.commonKey == .commonKeyTitle, let value = try? await item.load(.stringValue) { title = value }
                    if item.commonKey == .commonKeyArtist, let value = try? await item.load(.stringValue) { artist = value }
                    if item.commonKey == .commonKeyArtwork { artwork = try? await item.load(.dataValue) }
                }
                songs.append(Song(id: id, title: title, artist: artist, filename: filename, artwork: artwork))
                save()
            } catch { try? FileManager.default.removeItem(at: destination); self.error = "无法导入 \(url.lastPathComponent)：\(error.localizedDescription)" }
        }
    }
    func play(_ song: Song) {
        do {
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
    func next(_ step: Int) { guard let i = songs.firstIndex(where: { $0.id == currentID }), !songs.isEmpty else { return }; play(songs[(i+step+songs.count)%songs.count]) }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in if flag { self.next(1) } else { self.pause() } } }
    func addLyrics(_ url: URL, to id: UUID) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard let i = songs.firstIndex(where: { $0.id == id }) else { return }
            songs[i].lyrics = text; songs[i].lyricKind = url.pathExtension.lowercased(); save()
        } catch { self.error = "歌词导入失败：\(error.localizedDescription)" }
    }
    private func nowPlaying() {
        guard let song = current else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle:song.title, MPMediaItemPropertyArtist:song.artist, MPMediaItemPropertyPlaybackDuration:duration, MPNowPlayingInfoPropertyElapsedPlaybackTime:position, MPNowPlayingInfoPropertyPlaybackRate:playing ? 1.0 : 0.0]
        if let data = song.artwork, let image = UIImage(data: data) { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
