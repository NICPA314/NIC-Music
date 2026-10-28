import XCTest
@testable import NICMusic

final class AtmosMetadataTests: XCTestCase {
    func testJOCConfigurationAndOrdinaryEAC3AreDistinct() {
        XCTAssertTrue(AtmosMetadata.hasJOC(Data([0x18, 0, 0x20, 0x0f, 0, 1, 0x10])))
        XCTAssertFalse(AtmosMetadata.hasJOC(Data([0x18, 0, 0x20, 0x0f, 0])))
        XCTAssertFalse(AtmosMetadata.hasJOC(Data([0x18, 0, 0x20, 0x0f, 0, 0, 0x10])))
        XCTAssertFalse(AtmosMetadata.hasJOC(Data([0x18, 0, 0x20, 0x0f, 0, 1])))
    }
    func testOnlyEC3SampleEntryCanIdentifyAtmos() throws {
        func box(_ kind: String, _ payload: Data) -> Data {
            var size = UInt32(payload.count + 8).bigEndian
            return withUnsafeBytes(of: &size) { Data($0) } + Data(kind.utf8) + payload
        }
        let config = box("dec3", Data([0x18, 0, 0x20, 0x0f, 0, 1, 0x10]))
        for (entry, expected) in [("ec-3", true), ("mp4a", false)] {
            let sample = box(entry, Data(repeating: 0, count: 28) + config)
            let stsd = box("stsd", Data([0,0,0,0,0,0,0,1]) + sample)
            let moov = box("moov", box("trak", box("mdia", box("minf", box("stbl", stsd)))))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            defer { try? FileManager.default.removeItem(at: url) }
            try moov.write(to: url)
            XCTAssertEqual(AtmosMetadata.read(url), expected)
        }
    }
}
