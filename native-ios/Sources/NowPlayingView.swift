import SwiftUI
import UniformTypeIdentifiers
import AVKit
import MediaPlayer

struct NowPlayingView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode = 0
    @State private var showQuality = false
    @State private var attachment: AttachmentImport?
    @State private var scrub = 0.0
    @State private var scrubbing = false
    @AppStorage("showTranslation") private var translation = true
    @AppStorage("showPronunciation") private var pronunciation = true
    @State private var hasTranslation = false
    @State private var hasPronunciation = false
    private struct AttachmentImport: Identifiable {
        var id = UUID()
        let songID: UUID
        let kind: Int // lyrics, image, video
        var types: [UTType] {
            if kind == 1 { return [.image] }
            if kind == 2 { return [.movie] }
            return [UTType(filenameExtension: "lrc") ?? .plainText, UTType(filenameExtension: "ttml") ?? .xml, .plainText, .xml]
        }
    }
    var body: some View {
        GeometryReader { geometry in
            if let song = library.current {
                ZStack {
                    background(song)
                    VStack(spacing: 14) {
                        Button { dismiss() } label: { Capsule().fill(.white.opacity(0.4)).frame(width: 44, height: 5).frame(height: 20) }.accessibilityLabel("关闭播放页")
                        if mode != 0 { songHeader(song, compact: true) }
                        if mode == 1 {
                            lyricsContent(song)
                        } else if mode == 2 {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 16) {
                                    Menu {
                                        ForEach(MusicLibrary.PlaybackMode.allCases, id: \.self) { value in
                                            Button(value.rawValue, systemImage: value == .random ? "shuffle" : value == .repeatOne ? "repeat.1" : value == .repeatAll ? "repeat" : "list.bullet") { library.changePlaybackMode(value) }
                                        }
                                    } label: { Label(library.playbackMode.rawValue, systemImage: "arrow.triangle.2.circlepath").font(.headline) }
                                    Text("继续播放").font(.title2.bold())
                                    ForEach(library.queue) { item in
                                        Button { library.play(item) } label: {
                                            HStack(spacing: 12) { Cover(song: item).frame(width: 44, height: 44); VStack(alignment: .leading) { Text(item.title); Text(item.artist).font(.subheadline).opacity(0.6) }; Spacer(); if item.id == song.id { Image(systemName: "waveform") } }
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }.frame(maxHeight: .infinity)
                        } else {
                            Spacer(minLength: 0)
                            if song.videoFilename == nil {
                                Cover(song: song).aspectRatio(1, contentMode: .fit)
                                    .frame(maxWidth: max(1, min(geometry.size.width - 88, 340)), maxHeight: max(1, geometry.size.height * 0.43))
                                    .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                            }
                            Spacer(minLength: 0)
                            songHeader(song, compact: false)
                        }
                        if library.importingAttachment { ProgressView("正在导入…").tint(.white) }
                        progress
                        HStack(spacing: 58) {
                            Button("上一首", systemImage: "backward.fill") { library.next(-1) }
                            Button(library.playing ? "暂停" : "播放", systemImage: library.playing ? "pause.fill" : "play.fill") { library.toggle() }.font(.system(size: 42)).accessibilityIdentifier("playback-toggle")
                            Button("下一首", systemImage: "forward.fill") { library.next(1) }
                        }.font(.system(size: 28)).labelStyle(.iconOnly).buttonStyle(.plain).padding(.vertical, geometry.size.height > 700 ? 24 : 8)
                        SystemVolume().frame(height: 30).padding(.top, 8)
                        HStack {
                            Button { mode = mode == 1 ? 0 : 1 } label: { Image(systemName: "quote.bubble").frame(width: 44, height: 44).background(mode == 1 ? .white.opacity(0.22) : .clear, in: Circle()) }.accessibilityLabel("歌词")
                            Spacer()
                            AudioRoute().frame(width: 44, height: 44)
                            Spacer()
                            Button { mode = mode == 2 ? 0 : 2 } label: { Image(systemName: "list.bullet").frame(width: 44, height: 44).background(mode == 2 ? .white.opacity(0.22) : .clear, in: Circle()) }.accessibilityLabel("待播歌曲")
                        }.font(.system(size: 24, weight: .semibold)).buttonStyle(.plain).padding(.horizontal, 36).padding(.bottom, 12)
                    }.padding(.horizontal, 28).padding(.top, 6)
                }.foregroundStyle(.white).preferredColorScheme(.dark)
            }
        }
        .sheet(item: $attachment) { request in
            DocumentImportPicker(types: request.types) { urls in
                attachment = nil
                guard let url = urls.first else { return }
                Task {
                    if request.kind == 0 { await library.addLyrics(url, to: request.songID) }
                    else { await library.addCover(url, video: request.kind == 2, to: request.songID) }
                }
            }
        }
        .alert("无法完成操作", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) { Button("好") { library.error = nil } } message: { Text(library.error ?? "") }
        .alert("音频格式", isPresented: $showQuality) { Button("好", role: .cancel) {} } message: { Text(library.current?.quality?.description ?? "") }
        .onChange(of: library.currentID) { hasTranslation = false; hasPronunciation = false }
    }
    private func background(_ song: Song) -> some View {
        GeometryReader { canvas in
            let size = canvas.size
            ZStack(alignment: .top) {
            Cover(song: song).frame(width: size.width, height: size.height).blur(radius: 65).scaleEffect(1.25)
            LyricsView(song: song, position: 0, playing: library.playing && scenePhase == .active,
                       backgroundOnly: true, audioEnergy: library.audioEnergy, reduceMotion: reduceMotion,
                       onError: { _ in ImportDiagnostics.record("AMLL background unavailable; showing static artwork") })
                .id(song.id.uuidString + (song.artworkFilename ?? ""))
                .allowsHitTesting(false)
            Color.black.opacity(0.45)
            if mode == 0, let filename = song.videoFilename {
                LoopingCover(url: library.folder.appendingPathComponent(filename), active: library.playing && scenePhase == .active && !reduceMotion)
                    .frame(width: size.width, height: size.height * 0.72)
                    .clipped()
                    .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.62), .init(color: .white.opacity(0.65), location: 0.8), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                LinearGradient(stops: [.init(color: .clear, location: 0.36), .init(color: .black.opacity(0.12), location: 0.64), .init(color: .black.opacity(0.45), location: 1)], startPoint: .top, endPoint: .bottom)
            }
            }.frame(width: size.width, height: size.height).clipped()
        }.ignoresSafeArea()
    }
    private func songHeader(_ song: Song, compact: Bool) -> some View {
        HStack(spacing: 12) {
            if compact { Cover(song: song).frame(width: 58, height: 58) }
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title).font(compact ? .headline : .title2.bold()).lineLimit(1)
                Text(song.artist).font(compact ? .subheadline : .title3).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { library.toggleFavorite() } label: { Image(systemName: song.favorite == true ? "star.fill" : "star").font(.system(size: 24, weight: .semibold)).frame(width: 44, height: 44) }.accessibilityLabel(song.favorite == true ? "取消喜爱" : "喜爱")
            Menu {
                Button("导入歌词", systemImage: "text.badge.plus") { attachment = AttachmentImport(songID: song.id, kind: 0) }
                Button("选择静态封面", systemImage: "photo") { attachment = AttachmentImport(songID: song.id, kind: 1) }
                Button("选择视频封面", systemImage: "video") { attachment = AttachmentImport(songID: song.id, kind: 2) }
            } label: { Image(systemName: "ellipsis").font(.system(size: 24, weight: .bold)).frame(width: 44, height: 44) }.disabled(library.importingAttachment).accessibilityLabel("歌曲选项")
        }.buttonStyle(.plain)
    }
    @ViewBuilder private func lyricsContent(_ song: Song) -> some View {
        if song.lyrics != nil {
            LyricsView(song: song, position: library.position, playing: library.playing, showTranslation: translation, showPronunciation: pronunciation,
                       onSeek: { library.seek($0) }, onCapabilities: { hasTranslation = $0; hasPronunciation = $1 }, onError: { library.error = $0 })
                .id(song.id).frame(maxHeight: .infinity)
            HStack {
                Menu {
                    Toggle(isOn: $pronunciation) { Label("显示发音", systemImage: "text.bubble") }.disabled(!hasPronunciation)
                    Toggle(isOn: $translation) { Label("显示翻译", systemImage: "character.bubble") }.disabled(!hasTranslation)
                } label: { Image(systemName: "translate").frame(width: 48, height: 48).glassEffect(.clear.interactive(), in: .circle) }.buttonStyle(.plain).accessibilityLabel("歌词显示选项")
                Spacer()
            }
        } else {
            ContentUnavailableView { Label("让歌词跟随音乐", systemImage: "quote.bubble") } actions: {
                Button("导入歌词") { attachment = AttachmentImport(songID: song.id, kind: 0) }.buttonStyle(ClearGlassButtonStyle())
            }.frame(maxHeight: .infinity)
        }
    }
    private var progress: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { scrubbing ? scrub : library.position }, set: { scrub = $0 }), in: 0...max(1, library.duration), onEditingChanged: { active in scrubbing = active; if !active { library.seek(scrub) } }).tint(.white.opacity(0.8)).accessibilityLabel("播放进度")
            HStack {
                Text(clock(scrubbing ? scrub : library.position)); Spacer()
                if let quality = library.current?.quality, quality.lossless { Button { showQuality = true } label: { Label("无损", systemImage: "waveform").font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 6) }.buttonStyle(.plain).foregroundStyle(.white).glassEffect(.clear, in: .capsule) }
                Spacer(); Text("−" + clock(max(0, library.duration - library.position)))
            }.font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.55))
        }
    }
    private func clock(_ time: Double) -> String { String(format: "%d:%02d", Int(time) / 60, Int(time) % 60) }
}

private struct SystemVolume: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView { let view = MPVolumeView(); view.showsRouteButton = false; view.tintColor = .white; return view }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
private struct AudioRoute: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.tintColor = .white; return view }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

private struct LoopingCover: UIViewRepresentable {
    let url: URL
    let active: Bool
    func makeUIView(context: Context) -> VideoSurface { VideoSurface() }
    func updateUIView(_ view: VideoSurface, context: Context) { view.update(url, active: active) }
    static func dismantleUIView(_ view: VideoSurface, coordinator: ()) { view.stop() }
    final class VideoSurface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var queue: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var url: URL?
        func update(_ url: URL, active: Bool) {
            if self.url != url {
                stop(); self.url = url
                let queue = AVQueuePlayer(); queue.isMuted = true
                self.queue = queue
                looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
                let surface = layer as! AVPlayerLayer; surface.player = queue; surface.videoGravity = .resizeAspectFill
            }
            if active { queue?.play() } else { queue?.pause() }
        }
        func stop() { queue?.pause(); looper?.disableLooping(); queue?.removeAllItems(); (layer as? AVPlayerLayer)?.player = nil; looper = nil; queue = nil; url = nil }
    }
}
