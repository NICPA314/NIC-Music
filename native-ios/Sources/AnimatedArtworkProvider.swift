import AVFoundation
import MediaPlayer
import UIKit

enum AnimatedArtworkProvider {
    // The system requires the video and preview to match the advertised aspect ratio.
    static func key(for ratio: Double?) -> String? {
        guard let ratio else { return nil }
        if abs(ratio - 0.75) < 0.005 { return MPNowPlayingInfoProperty3x4AnimatedArtwork }
        if abs(ratio - 1) < 0.005 { return MPNowPlayingInfoProperty1x1AnimatedArtwork }
        return nil
    }
    static func artwork(url: URL) -> MPMediaItemAnimatedArtwork {
        MPMediaItemAnimatedArtwork(
            artworkID: url.path,
            previewImageRequestHandler: { _ in await AnimatedPreviewCache.shared.preview(url) },
            videoAssetFileURLRequestHandler: { _ in url }
        )
    }
}

private actor AnimatedPreviewCache {
    static let shared = AnimatedPreviewCache()
    private var images: [URL: UIImage] = [:]
    func preview(_ url: URL) async -> UIImage? {
        if let image = images[url] { return image }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        guard let frame = try? await generator.image(at: .zero) else { return nil }
        let image = UIImage(cgImage: frame.image)
        if images.count >= 3 { images.removeAll() }
        images[url] = image
        return image
    }
}
