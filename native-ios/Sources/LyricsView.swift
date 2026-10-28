import SwiftUI
import WebKit

struct LyricsView: UIViewRepresentable {
    let song: Song
    let position: Double
    let playing: Bool
    var onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "lyrics")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false; web.backgroundColor = .clear; web.scrollView.backgroundColor = .clear
        context.coordinator.web = web
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist") { web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onError = onError
        context.coordinator.song = song
        context.coordinator.position = position
        context.coordinator.playing = playing
        context.coordinator.sync()
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "lyrics")
        web.stopLoading(); web.loadHTMLString("", baseURL: nil)
    }
    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var web: WKWebView?
        var ready = false
        var song: Song?
        var loaded: Song?
        var position: Double = 0
        var playing = false
        var onError: ((String)->Void)?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String:Any] else { return }
            if body["event"] as? String == "ready" { ready = true; sync() }
            if body["event"] as? String == "error" { onError?(body["message"] as? String ?? "歌词读取失败") }
        }
        func sync() {
            guard ready, let song, let web else { return }
            if loaded != song {
                loaded = song
                // Structured arguments keep lyric text out of executable JS source.
                web.callAsyncJavaScript("window.setLyrics(text, kind)", arguments: ["text":song.lyrics ?? "", "kind":song.lyricKind ?? "lrc"], in: nil, in: .page) { _ in }
            }
            web.callAsyncJavaScript("window.setPlayback(time, playing)", arguments: ["time":position*1000, "playing":playing], in: nil, in: .page) { _ in }
        }
    }
}
