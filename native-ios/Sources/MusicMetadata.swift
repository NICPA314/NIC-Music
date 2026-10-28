import Foundation
import AVFoundation
import AudioToolbox

struct AudioQuality: Codable, Equatable {
    var codec: String
    var sampleRate: Double
    var bitDepth: Int?
    var channels: Int
    var lossless: Bool
    var atmos: Bool? = nil
    var description: String {
        [atmos == true ? "Dolby Atmos · " + codec : codec, "\(channels) 声道", bitDepth.map { "\($0) 位" }, String(format: "%g kHz", sampleRate / 1000)].compactMap { $0 }.joined(separator: " · ")
    }
    static func read(_ url: URL) -> AudioQuality? {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else { return nil }
        defer { AudioFileClose(file) }
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout.size(ofValue: format))
        guard AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &format) == noErr else { return nil }
        let codec: String
        let lossless: Bool
        var bits = Int(format.mBitsPerChannel)
        switch format.mFormatID {
        case kAudioFormatAppleLossless:
            codec = "ALAC"; lossless = true
            bits = [1: 16, 2: 20, 3: 24, 4: 32][Int(format.mFormatFlags)] ?? bits
        case kAudioFormatFLAC: codec = "FLAC"; lossless = true
        case kAudioFormatLinearPCM: codec = "PCM"; lossless = true
        case kAudioFormatEnhancedAC3: codec = "E-AC-3"; lossless = false
        case kAudioFormatMPEGLayer3: codec = "MP3"; lossless = false
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: codec = "AAC"; lossless = false
        default: codec = "音频"; lossless = false
        }
        return AudioQuality(codec: codec, sampleRate: format.mSampleRate, bitDepth: bits > 0 ? bits : nil, channels: Int(format.mChannelsPerFrame), lossless: lossless, atmos: format.mFormatID == kAudioFormatEnhancedAC3 && AtmosMetadata.read(url))
    }
}

struct EmbeddedTags {
    var title: String?
    var artist: String?
    var artwork: Data?
    var album: String?
    var albumArtist: String?
    var releaseDate: String?
    var copyright: String?
    var recordLabel: String?
    var genre: String?
    var composer: String?
    var trackNumber: Int?
    var discNumber: Int?
}

struct Playlist: Identifiable, Codable, Equatable {
    var artworkFilename: String?
    var pinned: Bool?
    var id = UUID()
    var name: String
    var songIDs: [UUID] = []
}

struct AlbumGroup: Identifiable {
    let id: String
    var songs: [Song]
    var first: Song { songs[0] }
}
