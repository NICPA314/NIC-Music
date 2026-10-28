import SwiftUI
import UniformTypeIdentifiers

@main struct NICMusicApp: App {
    @State private var library = MusicLibrary()
    var body: some Scene { WindowGroup { LibraryRoot().environment(library).tint(.pink) } }
}

struct LibraryRoot: View {
    @Environment(MusicLibrary.self) private var library
    @State private var showImporter = false
    @State private var importFolder = false
    @State private var importPlaylistID: UUID?
    @State private var newPlaylist = false
    @State private var playlistName = ""
    @State private var presented: Song?
    @State private var query = ""
    var body: some View {
        TabView {
            Tab("资料库", systemImage: "square.stack.fill") {
                NavigationStack {
                    libraryContent
                        .navigationTitle("资料库")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) { NavigationLink { playlistList.navigationTitle("播放列表") } label: { Image(systemName: "music.note.list") }.accessibilityLabel("播放列表") }
                            ToolbarItem(placement: .topBarTrailing) { importMenu }
                        }
                }
            }
            Tab("搜索", systemImage: "magnifyingglass", role: .search) {
                NavigationStack {
                    songList(library.librarySongs.filter { query.isEmpty || ($0.title + $0.artist + ($0.album ?? "")).localizedCaseInsensitiveContains(query) })
                        .navigationTitle("搜索")
                        .searchable(text: $query, prompt: "歌曲、艺人")
                }
            }
            Tab("设置", systemImage: "gearshape") {
                NavigationStack {
                    Form {
                        Section("音乐") { importMenu; LabeledContent("歌曲", value: "\(library.librarySongs.count)"); Text("导入文件夹可同时读取专辑封面和同名 TTML／LRC 歌词。").font(.footnote).foregroundStyle(.secondary) }
                        Section("关于") { LabeledContent("NIC Music", value: "0.2.0"); Link("AMLL Player 开源项目", destination: URL(string:"https://github.com/amll-dev/amll-player")!); Link("源码与许可证", destination: URL(string:"https://github.com/NICPA314/NIC-Music")!) }
                    }.navigationTitle("设置")
                }
            }
        }
        .musicAccessory(enabled: library.current != nil) {
            if let song = library.current {
                HStack(spacing: 12) {
                    Button { presented = song } label: {
                        HStack(spacing: 10) { Cover(song: song).frame(width: 40, height: 40); Text(song.title).font(.subheadline.weight(.medium)).lineLimit(1).foregroundStyle(.primary) }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("mini-player")
                    Button(library.playing ? "暂停" : "播放", systemImage: library.playing ? "pause.fill" : "play.fill") { library.toggle() }.labelStyle(.iconOnly).foregroundStyle(.primary)
                    Button("下一首", systemImage: "forward.fill") { library.next(1) }.labelStyle(.iconOnly).foregroundStyle(.primary)
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .sheet(item: $presented) { _ in NowPlayingView().environment(library) }
        .sheet(isPresented: $showImporter) {
            DocumentImportPicker(types: importFolder ? [.folder] : [.audio], multiple: !importFolder) { urls in
                showImporter = false
                importSelection(urls, folder: importFolder, playlistID: importPlaylistID)
            }
        }
        .safeAreaInset(edge: .top) { if library.importing { HStack { ProgressView(); Text(library.importProgress).font(.footnote).lineLimit(2) }.padding(12).frame(maxWidth: .infinity).background(.regularMaterial).accessibilityIdentifier("import-progress") } }
        .alert("导入结果", isPresented: Binding(get: { library.importSummary != nil }, set: { if !$0 { library.importSummary = nil } })) { Button("好") { library.importSummary = nil } } message: { Text(library.importSummary ?? "") }
        .alert("无法完成操作", isPresented: Binding(get: { library.error != nil && presented == nil }, set: { if !$0 { library.error = nil } })) { Button("好") { library.error = nil } } message: { Text(library.error ?? "") }
        .alert("新建播放列表", isPresented: $newPlaylist) { TextField("名称", text: $playlistName); Button("创建") { library.createPlaylist(playlistName); playlistName = "" }; Button("取消", role: .cancel) {} }
    }
    private var importMenu: some View {
        Menu {
            Button("选择音乐文件", systemImage: "music.note") { startImport(folder: false) }
            Button("导入文件夹", systemImage: "folder") { startImport(folder: true) }
        } label: { Label("导入音乐", systemImage: "plus") }.disabled(library.importing).accessibilityIdentifier("import-music")
    }
    private func startImport(folder: Bool, playlistID: UUID? = nil) { importFolder = folder; importPlaylistID = playlistID; showImporter = true }
    private func importSelection(_ urls: [URL], folder: Bool, playlistID: UUID?) {
        ImportDiagnostics.record("selection received \(urls.count), folder=\(folder)")
        // The document picker can dismiss itself before its delegate delivers URLs.
        // Start from that delegate event, never from SwiftUI's sheet onDismiss.
        guard !urls.isEmpty else { return }
        Task {
            if folder, let url = urls.first { await library.importDirectory(url, playlistID: playlistID) }
            else { await library.importSongs(urls, playlistID: playlistID) }
        }
    }
    private var albums: [AlbumGroup] {
        Dictionary(grouping: library.librarySongs, by: \.albumKey).map { AlbumGroup(id: $0.key, songs: $0.value) }.sorted { $0.first.albumTitle < $1.first.albumTitle }
    }
    private var recentAlbums: [AlbumGroup] {
        var seen = Set<String>()
        return library.librarySongs.reversed().compactMap { song in
            guard seen.insert(song.albumKey).inserted else { return nil }
            return albums.first { $0.id == song.albumKey }
        }
    }
    @ViewBuilder private var libraryContent: some View {
        if library.librarySongs.isEmpty { songList([], libraryEmpty: true) }
        else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 0) {
                        NavigationLink { playlistList.navigationTitle("播放列表") } label: { libraryRow("播放列表", icon: "music.note.list") }
                        Divider()
                        NavigationLink { songList(library.librarySongs).navigationTitle("歌曲") } label: { libraryRow("歌曲", icon: "music.note") }
                        Divider()
                        NavigationLink { albumGrid.navigationTitle("专辑") } label: { libraryRow("专辑", icon: "square.stack") }
                        Divider()
                        NavigationLink {
                            List(Array(Set(library.librarySongs.map(\.artist))).sorted(), id: \.self) { artist in
                                NavigationLink(artist) { ArtistDetailView(artist: artist) }
                            }.navigationTitle("艺人")
                        } label: { libraryRow("艺人", icon: "mic") }
                    }
                    Text("最近添加").font(.title2.bold())
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 22) {
                        ForEach(recentAlbums) { album in
                            NavigationLink { AlbumDetailView(albumKey: album.id) } label: { tile(album.first, title: album.first.albumTitle, subtitle: album.first.albumArtist ?? album.first.artist) }.buttonStyle(.plain)
                        }
                    }
                }.padding(20)
            }.background(Color(uiColor: .systemBackground))
        }
    }
    private var albumGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 22) {
                ForEach(albums) { album in
                    NavigationLink { AlbumDetailView(albumKey: album.id) } label: {
                        tile(album.first, title: album.first.albumTitle, subtitle: album.first.albumArtist ?? album.first.artist)
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }
    }
    private var playlistList: some View {
        List {
            Button("新建播放列表", systemImage: "plus") { newPlaylist = true }
            ForEach(library.playlists) { playlist in
                NavigationLink {
                    songList(playlist.songIDs.compactMap { id in library.songs.first { $0.id == id } })
                        .navigationTitle(playlist.name)
                        .toolbar {
                            Menu("导入", systemImage: "plus") {
                                Button("选择音乐文件") { startImport(folder: false, playlistID: playlist.id) }
                                Button("导入文件夹") { startImport(folder: true, playlistID: playlist.id) }
                            }.disabled(library.importing)
                        }
                } label: { Label(playlist.name, systemImage: "music.note.list") }
            }
        }
    }
    private func libraryRow(_ title: String, icon: String) -> some View {
        HStack { Image(systemName: icon).foregroundStyle(.pink).frame(width: 30); Text(title).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary) }.font(.title3).padding(.vertical, 16)
    }
    private func tile(_ song: Song, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Cover(song: song).aspectRatio(1, contentMode: .fit)
            Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.foregroundStyle(.primary)
    }
    @ViewBuilder private func songList(_ songs: [Song], libraryEmpty: Bool = false) -> some View {
        if libraryEmpty || (songs.isEmpty && library.songs.isEmpty) {
            ContentUnavailableView {
                Label("音乐", systemImage: "music.note")
            } description: { Text("导入喜欢的歌曲。") } actions: {
                importMenu.buttonStyle(.glassProminent)
            }
        } else if songs.isEmpty { ContentUnavailableView("暂无歌曲", systemImage: "music.note", description: Text("从右上角导入音乐。")) }
        else {
            List {
                Section {
                    ForEach(songs) { song in
                        Button { library.play(song, queue: songs) } label: {
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

private extension View {
    @ViewBuilder func musicAccessory<Accessory: View>(enabled: Bool, @ViewBuilder content: () -> Accessory) -> some View {
        if enabled { self.tabViewBottomAccessory(content: content) }
        else { self }
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
