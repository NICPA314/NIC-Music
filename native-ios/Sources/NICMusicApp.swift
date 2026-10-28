import SwiftUI
import UniformTypeIdentifiers

@main struct NICMusicApp: App {
    @State private var library = MusicLibrary()
    var body: some Scene { WindowGroup { LibraryRoot().environment(library).tint(.pink) } }
}

struct LibraryRoot: View {
    @Environment(MusicLibrary.self) private var library
    @State private var showImporter = false
    @State private var presented: Song?
    @State private var query = ""
    var body: some View {
        TabView {
            Tab("资料库", systemImage: "square.stack.fill") {
                NavigationStack {
                    songList(library.songs)
                        .navigationTitle("资料库")
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("导入音乐", systemImage: "plus") { showImporter = true }.disabled(library.importing) } }
                }
            }
            Tab("搜索", systemImage: "magnifyingglass", role: .search) {
                NavigationStack {
                    songList(library.songs.filter { query.isEmpty || ($0.title + $0.artist).localizedCaseInsensitiveContains(query) })
                        .navigationTitle("搜索")
                        .searchable(text: $query, prompt: "歌曲、艺人")
                }
            }
            Tab("设置", systemImage: "gearshape") {
                NavigationStack {
                    Form {
                        Section("音乐") { Button("导入本地音乐", systemImage: "plus.circle") { showImporter = true }; LabeledContent("歌曲", value: "\(library.songs.count)") }
                        Section("关于") { LabeledContent("NIC Music", value: "0.1.0"); Link("AMLL Player 开源项目", destination: URL(string:"https://github.com/amll-dev/amll-player")!); Link("源码与许可证", destination: URL(string:"https://github.com/NICPA314/AMLL-Player-iOS")!) }
                    }.navigationTitle("设置")
                }
            }
        }
        .tabViewBottomAccessory {
            if let song = library.current {
                HStack(spacing: 12) {
                    Button { presented = song } label: {
                        HStack(spacing: 10) { Cover(song: song).frame(width: 40, height: 40); Text(song.title).font(.subheadline.weight(.medium)).lineLimit(1).foregroundStyle(.primary) }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button(library.playing ? "暂停" : "播放", systemImage: library.playing ? "pause.fill" : "play.fill") { library.toggle() }.labelStyle(.iconOnly).foregroundStyle(.primary)
                    Button("下一首", systemImage: "forward.fill") { library.next(1) }.labelStyle(.iconOnly).foregroundStyle(.primary)
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .sheet(item: $presented) { _ in NowPlayingView().environment(library) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): Task { await library.importSongs(urls) }; case .failure(let error): library.error = error.localizedDescription }
        }
        .alert("无法完成操作", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) { Button("好") { library.error = nil } } message: { Text(library.error ?? "") }
    }
    @ViewBuilder private func songList(_ songs: [Song]) -> some View {
        if library.songs.isEmpty {
            ContentUnavailableView {
                Label("音乐，随身而行", systemImage: "music.note")
            } description: { Text("导入喜欢的歌曲，让每一句歌词鲜活起来。") } actions: {
                Button(library.importing ? "正在导入" : "导入音乐", systemImage: "plus") { showImporter = true }.buttonStyle(.glassProminent).disabled(library.importing)
            }
        } else if songs.isEmpty { ContentUnavailableView.search(text: query) }
        else {
            List {
                Section {
                    ForEach(songs) { song in
                        Button { library.play(song) } label: {
                            HStack(spacing: 14) {
                                Cover(song: song).frame(width: 54, height: 54)
                                VStack(alignment: .leading, spacing: 5) { Text(song.title).font(.body.weight(.medium)).lineLimit(1).foregroundStyle(.primary); Text(song.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                                Spacer(minLength: 0)
                                if library.currentID == song.id { Image(systemName: "waveform").foregroundStyle(.pink) }
                            }.padding(.vertical, 4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                } header: { Text("歌曲 · \(songs.count)") }
            }.listStyle(.plain)
        }
    }
}

struct Cover: View {
    let song: Song
    var body: some View {
        Group {
            if let data = song.artwork, let ui = UIImage(data: data) { Image(uiImage: ui).resizable().scaledToFill() }
            else { Rectangle().fill(LinearGradient(colors:[.pink.opacity(0.8),.purple.opacity(0.7)],startPoint:.topLeading,endPoint:.bottomTrailing)).overlay { Image(systemName:"music.note").font(.title).foregroundStyle(.white.opacity(0.85)) } }
        }.clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct NowPlayingView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var lyrics = false
    @State private var importer = false
    @State private var importTarget: UUID?
    @State private var scrub: Double = 0
    @State private var scrubbing = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors:[Color(red:0.34,green:0.12,blue:0.25),Color(red:0.12,green:0.1,blue:0.22),.black],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()
                if let song = library.current {
                    VStack(spacing: 20) {
                        HStack {
                            Button("关闭", systemImage:"chevron.down") { dismiss() }.labelStyle(.iconOnly).buttonStyle(.glass)
                            Spacer()
                            Menu { Button("导入歌词", systemImage:"text.badge.plus") { importTarget = song.id; importer = true } } label: { Image(systemName:"ellipsis").frame(width:28,height:28) }.buttonStyle(.glass)
                        }
                        if lyrics {
                            if song.lyrics != nil { LyricsView(song:song,position:library.position,playing:library.playing,onError:{library.error = $0}).id(song.id).frame(maxHeight:.infinity) }
                            else { ContentUnavailableView { Label("让歌词跟随音乐",systemImage:"quote.bubble") } description: { Text("支持 LRC 与逐字 TTML 歌词") } actions: { Button("导入歌词") { importTarget = song.id; importer = true }.buttonStyle(.glass) }.frame(maxHeight:.infinity) }
                        } else {
                            Spacer(minLength: 0)
                            Cover(song:song).aspectRatio(1,contentMode:.fit).frame(maxWidth:min(geometry.size.width-64,340),maxHeight:geometry.size.height*0.48).shadow(color:.black.opacity(0.3),radius:24,y:14)
                            Spacer(minLength: 0)
                        }
                        VStack(alignment:.leading,spacing:6) { Text(song.title).font(.title2.bold()).lineLimit(2); Text(song.artist).font(.title3).foregroundStyle(.white.opacity(0.65)).lineLimit(1) }.frame(maxWidth:.infinity,alignment:.leading)
                        VStack(spacing:0) {
                            Slider(value:Binding(get:{scrubbing ? scrub : library.position},set:{scrub = $0}),in:0...max(1,library.duration),onEditingChanged:{ active in scrubbing = active; if !active {library.seek(scrub)} }).tint(.white.opacity(0.85))
                            HStack { Text(clock(library.position)); Spacer(); Text("−" + clock(max(0,library.duration-library.position))) }.font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.55))
                        }
                        HStack(spacing: 54) {
                            Button("上一首",systemImage:"backward.fill") { library.next(-1) }
                            Button(library.playing ? "暂停" : "播放",systemImage:library.playing ? "pause.fill" : "play.fill") { library.toggle() }.font(.system(size:40))
                            Button("下一首",systemImage:"forward.fill") { library.next(1) }
                        }.font(.system(size:28)).labelStyle(.iconOnly).buttonStyle(.plain).padding(.vertical,8)
                        GlassEffectContainer {
                            Button { lyrics.toggle() } label: { Label(lyrics ? "专辑封面" : "歌词",systemImage:lyrics ? "square" : "quote.bubble").frame(minWidth:72) }.buttonStyle(.glass)
                        }.padding(.bottom,10)
                    }.padding(.horizontal,28).padding(.top,20)
                }
            }.foregroundStyle(.white).preferredColorScheme(.dark)
        }
        .fileImporter(isPresented:$importer,allowedContentTypes:[UTType(filenameExtension:"lrc") ?? .plainText,UTType(filenameExtension:"ttml") ?? .xml],allowsMultipleSelection:false) { result in
            switch result { case .success(let urls): if let url = urls.first, let id = importTarget {library.addLyrics(url,to:id)}; case .failure(let error): library.error = error.localizedDescription }
        }
    }
    private func clock(_ time:Double)->String { String(format:"%d:%02d",Int(time)/60,Int(time)%60) }
}
