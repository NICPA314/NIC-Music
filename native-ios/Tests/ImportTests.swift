import XCTest
import AVFoundation
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
        try FileManager.default.removeItem(at: source)
        library.play(song)
        XCTAssertTrue(library.playing, library.error ?? "")
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertGreaterThan(library.position, 0.1)
        library.pause()
        let reloaded = MusicLibrary(folder: library.folder)
        XCTAssertEqual(reloaded.songs.first?.title, "Metadata Title")
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.folder.appendingPathComponent(song.filename).path))
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
        XCTAssertEqual([c, b, a, d].sorted(by: Song.playlistOrder).map(\.title), [d.title, a.title, b.title, c.title])
    }
    func testIndexWriteFailureRollsBackCopiedAudio() async throws {
        try FileManager.default.createDirectory(at: library.folder.appendingPathComponent("library.json"), withIntermediateDirectories: false)
        await library.importSongs([fixture("01. Wrong Filename")])
        XCTAssertTrue(library.songs.isEmpty)
        XCTAssertTrue(library.importSummary?.contains("1 个文件失败") == true)
        let files = try await MusicFileImporter.shared.audioFiles(in: library.folder)
        XCTAssertTrue(files.isEmpty)
    }
}
