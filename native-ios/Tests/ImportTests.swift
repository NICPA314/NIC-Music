import XCTest
import AVFoundation
import MediaPlayer
import UIKit
@testable import NICMusic

@MainActor final class ImportTests: XCTestCase {
    private var root: URL!
    private var library: MusicLibrary!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        library = MusicLibrary(folder: root.appendingPathComponent("Library"))
    }
    override func tearDown() async throws {
        library.pause()
        try? FileManager.default.removeItem(at: root)
        library = nil
    }
    private func fixture(_ name: String) -> URL { Bundle(for: Self.self).url(forResource: name, withExtension: "m4a", subdirectory: "Fixtures")! }
    private func copy(_ source: URL, to relative: String) throws -> URL {
        let destination = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
    func testImportUsesMetadataAndPlaysAfterOriginalRemoved() async throws {
        let source = try copy(fixture("01. Wrong Filename"), to: "Source/99. Not The Title.m4a")
        await library.importSongs([source])
        XCTAssertEqual(library.songs.count, 1, library.importSummary ?? "")
        let song = try XCTUnwrap(library.songs.first)
        XCTAssertEqual(song.title, "Metadata Title")
        XCTAssertEqual(song.artist, "Test Artist")
        XCTAssertEqual(song.album, "Test Album")
        XCTAssertNotNil(song.artwork)
        XCTAssertEqual(song.quality?.codec, "ALAC")
        XCTAssertEqual(song.trackNumber, 1)
        XCTAssertEqual(song.releaseDate, "2024-01-02")
        XCTAssertEqual(song.recordLabel, "Fixture Records")
        try FileManager.default.removeItem(at: source)
        library.play(song)
        XCTAssertTrue(library.playing, library.error ?? "")
        // Simulator audio startup and the main run loop can lag on CI. Wait
        // for observable playback, with a deadline, instead of assuming 700 ms.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (library.position <= 0.1 || library.audioEnergy <= 0), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(library.position, 0.1)
        XCTAssertGreaterThan(library.audioEnergy, 0)
        library.pause()
        XCTAssertEqual(library.audioEnergy, 0)
        let reloaded = MusicLibrary(folder: library.folder)
        XCTAssertEqual(reloaded.songs.first?.title, "Metadata Title")
        XCTAssertEqual(reloaded.songs.first?.artwork, song.artwork)
        XCTAssertNotNil(reloaded.songs.first?.artworkFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.folder.appendingPathComponent(song.filename).path))
        XCTAssertEqual(try Data(contentsOf: library.folder.appendingPathComponent(song.filename)), try Data(contentsOf: fixture("01. Wrong Filename")))
    }
    func testMissingTitleDoesNotUseFilename() async throws {
        var data = try Data(contentsOf: fixture("01. Wrong Filename"))
        let titleKey = Data([0xA9, 0x6E, 0x61, 0x6D])
        let range = try XCTUnwrap(data.range(of: titleKey))
        data.replaceSubrange(range, with: Data("xxxx".utf8))
        let source = root.appendingPathComponent("Do Not Use This Filename.m4a")
        try data.write(to: source)
        await library.importSongs([source])
        XCTAssertTrue(library.songs.isEmpty)
        XCTAssertTrue(library.importSummary?.contains("歌曲标题元数据") == true)
    }
    func testMixedBatchReportsFailureAndDoesNotLeaveBadCopy() async throws {
        let invalid = root.appendingPathComponent("bad.m4a")
        try Data("not audio".utf8).write(to: invalid)
        await library.importSongs([invalid, fixture("01. Wrong Filename")])
        XCTAssertEqual(library.songs.count, 1)
        XCTAssertTrue(library.importSummary?.contains("1 个文件失败") == true)
        XCTAssertFalse(library.importing)
    }
    func testNestedFoldersWinAndRepeatedImportMerges() async throws {
        _ = try copy(fixture("01. Wrong Filename"), to: "Input/Artist/Folder A/01.m4a")
        _ = try copy(fixture("02. Second"), to: "Input/Artist/Folder A/02.m4a")
        _ = try copy(fixture("03. Third"), to: "Input/Folder B/03.m4a")
        let input = root.appendingPathComponent("Input")
        await library.importDirectory(input)
        XCTAssertEqual(Set(library.songs.map(\.albumTitle)), ["Folder A", "Folder B"])
        XCTAssertEqual(Set(library.songs.map(\.albumKey)).count, 2)
        await library.importDirectory(input)
        XCTAssertEqual(library.songs.count, 3)
        XCTAssertTrue(library.importSummary?.contains("跳过 3") == true)
    }
    func testFlatFolderUsesMetadataAndCoverFallback() async throws {
        _ = try copy(fixture("01. Wrong Filename"), to: "Input/01.m4a")
        _ = try copy(fixture("02. Second"), to: "Input/02.m4a")
        let image = Bundle(for: Self.self).url(forResource: "cover", withExtension: "png", subdirectory: "Fixtures")!
        _ = try copy(image, to: "Input/cover.png")
        await library.importDirectory(root.appendingPathComponent("Input"))
        XCTAssertEqual(Set(library.songs.map(\.albumTitle)), ["Test Album"])
        let first = try XCTUnwrap(library.songs.first { $0.title == "Metadata Title" })
        let second = try XCTUnwrap(library.songs.first { $0.title == "Second Track" })
        XCTAssertNotNil(first.artwork)
        XCTAssertEqual(second.artwork, try Data(contentsOf: image))
        XCTAssertNotEqual(first.artwork, second.artwork, "Embedded cover must take precedence")
    }
    func testLaterSongReusesExistingAlbumDirectory() async throws {
        let first = try copy(fixture("01. Wrong Filename"), to: "First/Artist/Folder Album/01.m4a")
        await library.importDirectory(root.appendingPathComponent("First"))
        let directory = try XCTUnwrap(library.songs.first).filename.split(separator: "/").dropLast().joined(separator: "/")
        let second = try copy(fixture("02. Second"), to: "Later/02.m4a")
        await library.importSongs([second])
        XCTAssertEqual(library.songs.count, 2)
        XCTAssertEqual(Set(library.songs.map(\.albumKey)).count, 1)
        XCTAssertEqual(library.songs.last?.filename.split(separator: "/").dropLast().joined(separator: "/"), directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path), "Import must preserve the source")
    }
    func testPlaylistsUseIndependentCopiesAndNumericFilenameOrder() async throws {
        library.createPlaylist("One"); library.createPlaylist("Two")
        let first = library.playlists[0].id, second = library.playlists[1].id
        await library.importSongs([fixture("02. Second"), fixture("01. Wrong Filename")], playlistID: first)
        await library.importSongs([fixture("01. Wrong Filename")], playlistID: second)
        XCTAssertEqual(library.songs.count, 3)
        XCTAssertEqual(library.librarySongs.count, 0)
        let ordered = library.playlists[0].songIDs.compactMap { id in library.songs.first { $0.id == id } }
        XCTAssertEqual(ordered.map(\.title), ["Metadata Title", "Second Track"])
        let copies = library.songs.filter { $0.title == "Metadata Title" }
        XCTAssertNotEqual(copies[0].filename, copies[1].filename)
        await library.importSongs([fixture("01. Wrong Filename")], playlistID: first)
        XCTAssertEqual(library.songs.count, 3)
        XCTAssertEqual(library.playlists[0].songIDs.count, 2)
    }
    func testUnnumberedPlaylistOrderUsesArtistDateDiscTrack() {
        let a = Song(id: UUID(), title: "Last alphabetically", artist: "A", filename: "", album: "Album", releaseDate: "2020", trackNumber: 1, discNumber: 1)
        var b = a; b.title = "First alphabetically"; b.trackNumber = 2
        var c = a; c.artist = "B"; c.releaseDate = "2000"
        var d = a; d.album = "Older"; d.releaseDate = "2010"
        XCTAssertEqual([c, b, a, d].sorted(by: Song.playlistOrder), [d, a, b, c])
    }
    func testIndexWriteFailureRollsBackCopiedAudio() async throws {
        try FileManager.default.createDirectory(at: library.folder.appendingPathComponent("library.json"), withIntermediateDirectories: false)
        await library.importSongs([fixture("01. Wrong Filename")])
        XCTAssertTrue(library.songs.isEmpty)
        XCTAssertTrue(library.importSummary?.contains("1 个文件失败") == true)
        let files = try await MusicFileImporter.shared.audioFiles(in: library.folder)
        XCTAssertTrue(files.isEmpty)
    }
    func testVideoAndStaticCoversAreStoredIndependentlyOfSource() async throws {
        await library.importSongs([fixture("01. Wrong Filename")])
        let id = try XCTUnwrap(library.songs.first?.id)
        let video = Bundle(for: Self.self).url(forResource: "cover", withExtension: "mp4", subdirectory: "Fixtures")!
        let source = try copy(video, to: "Source/cover.mp4")
        await library.addCover(source, video: true, to: id)
        let filename = try XCTUnwrap(library.songs.first?.videoFilename, library.error ?? "")
        XCTAssertTrue(filename.hasPrefix("Albums/"))
        XCTAssertEqual(library.songs.first?.videoAspectRatio, 1)
        XCTAssertEqual(AnimatedArtworkProvider.key(for: library.songs.first?.videoAspectRatio), MPNowPlayingInfoProperty1x1AnimatedArtwork)
        try FileManager.default.removeItem(at: source)
        let asset = AVURLAsset(url: library.folder.appendingPathComponent(filename))
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
        let image = Bundle(for: Self.self).url(forResource: "cover", withExtension: "png", subdirectory: "Fixtures")!
        await library.addCover(image, video: false, to: id)
        XCTAssertEqual(library.songs.first?.videoFilename, filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.folder.appendingPathComponent(filename).path))
        XCTAssertEqual(library.songs.first?.title, "Metadata Title")
        XCTAssertEqual(library.songs.first?.videoAspectRatio, 1)
    }
    func testTallVideoWinsOverSquareAndUsesLockScreenRatio() async throws {
        _ = try copy(fixture("01. Wrong Filename"), to: "Input/01.m4a")
        let square = Bundle(for: Self.self).url(forResource: "cover", withExtension: "mp4", subdirectory: "Fixtures")!
        let tall = Bundle(for: Self.self).url(forResource: "cover-tall", withExtension: "mp4", subdirectory: "Fixtures")!
        _ = try copy(square, to: "Input/square_animated_artwork.mp4")
        _ = try copy(tall, to: "Input/tall_animated_artwork.mp4")
        await library.importDirectory(root.appendingPathComponent("Input"))
        let song = try XCTUnwrap(library.songs.first)
        XCTAssertEqual(song.videoAspectRatio, 0.75)
        XCTAssertEqual(AnimatedArtworkProvider.key(for: song.videoAspectRatio), MPNowPlayingInfoProperty3x4AnimatedArtwork)
        XCTAssertNil(AnimatedArtworkProvider.key(for: 16.0 / 9.0))
        let filename = try XCTUnwrap(song.videoFilename)
        XCTAssertEqual(try Data(contentsOf: library.folder.appendingPathComponent(filename)), try Data(contentsOf: tall))
    }
    func testArtistFolderPortraitPersistsAfterSourceRemoval() async throws {
        _ = try copy(fixture("01. Wrong Filename"), to: "Input/Artist/Album/01.m4a")
        let photo = Bundle(for: Self.self).url(forResource: "cover", withExtension: "png", subdirectory: "Fixtures")!
        let albumPhoto = Bundle(for: Self.self).url(forResource: "embedded", withExtension: "png", subdirectory: "Fixtures")!
        _ = try copy(photo, to: "Input/Artist/folder.png")
        _ = try copy(albumPhoto, to: "Input/Artist/Album/folder.png")
        await library.importDirectory(root.appendingPathComponent("Input"))
        XCTAssertEqual(library.artistArtwork["Test Artist"], try Data(contentsOf: photo))
        try FileManager.default.removeItem(at: root.appendingPathComponent("Input"))
        let reloaded = MusicLibrary(folder: library.folder)
        XCTAssertEqual(reloaded.artistArtwork["Test Artist"], try Data(contentsOf: photo))
        XCTAssertEqual(try Data(contentsOf: library.folder.appendingPathComponent("Albums/Test Artist/folder.png")), try Data(contentsOf: photo))
    }
    func testPlaylistCustomCoverIsCopiedPersistedAndReset() async throws {
        library.createPlaylist("My Playlist")
        let id = try XCTUnwrap(library.playlists.first?.id)
        let photo = Bundle(for: Self.self).url(forResource: "cover", withExtension: "png", subdirectory: "Fixtures")!
        let source = try copy(photo, to: "Source/cover.png")
        await library.setPlaylistArtwork(source, playlistID: id)
        let file = try XCTUnwrap(library.playlists.first?.artworkFilename, library.error ?? "")
        XCTAssertTrue(file.hasPrefix("Playlists/"))
        try FileManager.default.removeItem(at: source)
        let reloaded = MusicLibrary(folder: library.folder)
        XCTAssertEqual(reloaded.playlistArtwork[id], try Data(contentsOf: photo))
        await library.setPlaylistArtwork(nil, playlistID: id)
        XCTAssertNil(library.playlists.first?.artworkFilename)
        XCTAssertNil(library.playlistArtwork[id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.folder.appendingPathComponent(file).path))
    }
    func testPlaylistPinPersistsWithoutRemovingFromFullList() throws {
        library.createPlaylist("Pinned")
        library.createPlaylist("Other")
        let id = try XCTUnwrap(library.playlists.first?.id)
        library.togglePlaylistPin(id)
        let reloaded = MusicLibrary(folder: library.folder)
        XCTAssertEqual(reloaded.playlists.count, 2)
        XCTAssertEqual(reloaded.playlists.filter { $0.pinned == true }.map(\.id), [id])
        library.togglePlaylistPin(id)
        XCTAssertFalse(library.playlists.contains { $0.pinned == true })
        XCTAssertEqual(library.playlists.count, 2)
    }
    func testCustomAlbumCoverUsesStandardNameAndAppliesToLaterTracks() async throws {
        await library.importSongs([fixture("01. Wrong Filename"), fixture("02. Second")])
        let album = try XCTUnwrap(library.songs.first?.albumKey)
        let photo = Bundle(for: Self.self).url(forResource: "cover", withExtension: "png", subdirectory: "Fixtures")!
        await library.setAlbumArtwork(photo, albumKey: album)
        await library.importSongs([fixture("03. Third")])
        XCTAssertEqual(library.songs.count, 3)
        for song in library.songs {
            XCTAssertEqual(URL(fileURLWithPath: try XCTUnwrap(song.artworkFilename)).lastPathComponent, "cover.png")
            XCTAssertEqual(song.artwork, try Data(contentsOf: photo))
        }
        let reloaded = MusicLibrary(folder: library.folder)
        XCTAssertTrue(reloaded.songs.allSatisfy { $0.customArtwork == true })
    }
    func testAlbumLocalFolderImageIsNotUsedAsArtistPortrait() async throws {
        _ = try copy(fixture("02. Second"), to: "Input/Artist/Album/02.m4a")
        let photo = Bundle(for: Self.self).url(forResource: "cover", withExtension: "png", subdirectory: "Fixtures")!
        _ = try copy(photo, to: "Input/Artist/Album/folder.png")
        await library.importDirectory(root.appendingPathComponent("Input"))
        XCTAssertNil(library.artistArtwork["Test Artist"])
        XCTAssertNil(library.songs.first?.artwork)
    }
    func testCustomArtistPortraitKeepsOriginalWithBoundedPreview() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1800, height: 1800), format: format).image { context in
            UIColor.systemPink.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1800, height: 1800))
        }
        let data = try XCTUnwrap(image.pngData())
        let source = root.appendingPathComponent("portrait.png")
        try data.write(to: source)
        await library.setArtistArtwork(source, artist: "Test Artist")
        let preview = try XCTUnwrap(library.artistArtwork["Test Artist"].flatMap { UIImage(data: $0) })
        XCTAssertLessThanOrEqual(preview.size.width, 1024)
        XCTAssertEqual(try Data(contentsOf: library.folder.appendingPathComponent("Albums/Test Artist/folder.png")), data)
    }
    func testRandomQueueVisitsEachTrackAndSingleSongStops() async throws {
        await library.importSongs([fixture("01. Wrong Filename"), fixture("02. Second"), fixture("03. Third")])
        let songs = library.librarySongs
        XCTAssertEqual(songs.count, 3)
        let first = try XCTUnwrap(songs.first)
        library.play(first, queue: songs)
        library.changePlaybackMode(.random)
        var visited: Set<UUID> = [first.id]
        for _ in 0..<2 {
            library.next(1)
            let id = try XCTUnwrap(library.currentID)
            XCTAssertFalse(visited.contains(id))
            visited.insert(id)
        }
        XCTAssertEqual(visited.count, 3)
        library.play(first, queue: [first])
        library.next(1)
        XCTAssertFalse(library.playing)
        XCTAssertEqual(library.currentID, first.id)
    }
    func testAppInboxImportsAlbumWithoutExternalPicker() async throws {
        let source = try copy(fixture("01. Wrong Filename"), to: "待导入/Artist/Album/01.m4a")
        await library.importInboxContents()
        let song = try XCTUnwrap(library.librarySongs.first)
        XCTAssertEqual(song.title, "Metadata Title")
        XCTAssertEqual(song.albumTitle, "Album")
        try FileManager.default.removeItem(at: source.deletingLastPathComponent())
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.folder.appendingPathComponent(song.filename).path))
        library.play(song)
        XCTAssertTrue(library.playing, library.error ?? "")
    }

}
