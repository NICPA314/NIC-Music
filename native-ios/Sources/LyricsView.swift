import SwiftUI
import WebKit

struct LyricsView: UIViewRepresentable {
    let song: Song
    let position: Double
    let playing: Bool
    var showTranslation = true
    var showPronunciation = true
    var onCapabilities: (Bool, Bool) -> Void = { _, _ in }
    var onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "lyrics")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false; web.backgroundColor = .clear; web.scrollView.backgroundColor = .clear
        context.coordinator.web = web
        web.navigationDelegate = context.coordinator
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist") { web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onError = onError
        context.coordinator.song = song
        context.coordinator.position = position
        context.coordinator.playing = playing
        context.coordinator.showTranslation = showTranslation
        context.coordinator.showPronunciation = showPronunciation
        context.coordinator.onCapabilities = onCapabilities
        context.coordinator.sync()
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "lyrics")
        web.stopLoading(); web.loadHTMLString("", baseURL: nil)
    }
    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var web: WKWebView?
        var ready = false
        var song: Song?
        var loaded: Song?
        var position: Double = 0
        var playing = false
        var showTranslation = true
        var showPronunciation = true
        var onCapabilities: ((Bool, Bool) -> Void)?
        var failed = false
        var onError: ((String)->Void)?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String:Any] else { return }
            if body["event"] as? String == "ready" { ready = true; sync() }
            if body["event"] as? String == "error" { onError?(body["message"] as? String ?? "歌词读取失败") }
            if body["event"] as? String == "loaded" { onCapabilities?(body["translation"] as? Bool ?? false, body["pronunciation"] as? Bool ?? false) }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onError?("歌词页面加载失败：\(error.localizedDescription)") }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onError?("歌词资源加载失败：\(error.localizedDescription)") }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { ready = false; loaded = nil; webView.reload() }
        private func completed(_ result: Result<Any, Error>) {
            if case .failure(let error) = result, !failed { failed = true; onError?("歌词同步失败：\(error.localizedDescription)") }
        }
        func sync() {
            guard ready, let song, let web else { return }
            if loaded != song {
                loaded = song
                // Structured arguments keep lyric text out of executable JS source.
                failed = false
                web.callAsyncJavaScript("window.setLyrics(text, kind)", arguments: ["text":song.lyrics ?? "", "kind":song.lyricKind ?? "lrc"], in: nil, in: .page, completionHandler: completed)
            }
            web.callAsyncJavaScript("window.setLyricOptions(translation, pronunciation); window.setPlayback(time, playing)", arguments: ["translation":showTranslation, "pronunciation":showPronunciation, "time":position*1000, "playing":playing], in: nil, in: .page, completionHandler: completed)
        }
    }
}
