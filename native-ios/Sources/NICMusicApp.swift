import SwiftUI
import UniformTypeIdentifiers

@main struct NICMusicApp: App {
    @State private var library = MusicLibrary()
    var body: some Scene { WindowGroup { LibraryRoot().environment(library).tint(.pink) } }
}

struct LibraryRoot: View {
    @Environment(MusicLibrary.self) private var library
    @State private var importRequest: ImportRequest?
    private struct ImportRequest: Identifiable {
        let id = UUID()
        let folder: Bool
        let playlistID: UUID?
    }
    @State private var newPlaylist = false
    @State private var playlistName = ""
    @State private var presented: Song?
    @State private var selectedTab = 0
    @State private var showSettings = false
    @AppStorage("albumSort") private var albumSort = "name"
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("资料库", systemImage: "square.stack.fill", value: 0) {
                NavigationStack {
                    libraryContent
                        .navigationTitle("资料库")
                        .navigationDestination(isPresented: $showSettings) { settingsContent }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { showSettings = true } label: { Image(systemName: "gearshape").font(.title3).frame(width: 48, height: 48).contentShape(Circle()) }
                                    .buttonStyle(.plain).glassEffect(.clear.interactive(), in: .circle).accessibilityLabel("设置")
                            }.sharedBackgroundVisibility(.hidden)
                            ToolbarItem(placement: .topBarTrailing) { toolbarImportMenu }
                                .sharedBackgroundVisibility(.hidden)
                        }
                }
            }
            Tab("播放列表", systemImage: "music.note.list", value: 3) {
                NavigationStack { playlistList.navigationTitle("播放列表") }
            }
            Tab("专辑", systemImage: "square.stack", value: 4) {
                NavigationStack { albumGrid.navigationTitle("专辑") }
            }
            Tab("歌手", systemImage: "person.crop.circle", value: 5) {
                NavigationStack { ArtistDirectoryView().navigationTitle("歌手") }
            }
            Tab("搜索", systemImage: "magnifyingglass", value: 1, role: .search) {
                NavigationStack { MusicSearchView().navigationTitle("搜索") }
            }
        }

        .modifier(PlayerAccessory(enabled: library.current != nil, accessory: bottomDock))
        .fullScreenCover(item: $presented) { _ in NowPlayingView().environment(library) }
        .background {
            if let request = importRequest { DocumentImportPicker(types: request.folder ? [.folder] : [.audio], multiple: !request.folder) { urls in
                library.pendingSelectionID = nil
                library.importStatus = urls.isEmpty ? "已取消导入" : "已收到 \(urls.count) 个选择结果"
                importRequest = nil
                importSelection(urls, folder: request.folder, playlistID: request.playlistID)
            }.id(request.id).frame(width: 0, height: 0) }
        }
        .safeAreaInset(edge: .top) { if library.importing { HStack { ProgressView(); Text(library.importProgress).font(.footnote).lineLimit(2) }.padding(12).frame(maxWidth: .infinity).background(Color(uiColor: .systemBackground)).accessibilityIdentifier("import-progress") } }
        .alert("导入结果", isPresented: Binding(get: { library.importSummary != nil }, set: { if !$0 { library.importSummary = nil } })) { Button("好") { library.importSummary = nil } } message: { Text(library.importSummary ?? "") }
        .alert("无法完成操作", isPresented: Binding(get: { library.error != nil && presented == nil }, set: { if !$0 { library.error = nil } })) { Button("好") { library.error = nil } } message: { Text(library.error ?? "") }
        .alert("新建播放列表", isPresented: $newPlaylist) { TextField("名称", text: $playlistName); Button("创建") { library.createPlaylist(playlistName); playlistName = "" }; Button("取消", role: .cancel) {} }
    }
    private var settingsContent: some View {
        Form {
            Section("音乐") { LabeledContent("歌曲", value: "\(library.librarySongs.count)") }
            Section("关于") {
                LabeledContent("版本", value: ImportDiagnostics.displayVersion)
                Link("源码与许可证", destination: URL(string:"https://github.com/NICPA314/NIC-Music")!)
            }
        }.navigationTitle("设置")
    }
    private var bottomDock: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 10) {
            if let song = library.current {
                HStack(spacing: 8) {
                    Button { presented = song } label: {
                        HStack(spacing: 8) { Cover(song: song).frame(width: 38, height: 38); VStack(alignment: .leading, spacing: 2) { Text(song.title).font(.subheadline.weight(.medium)); Text(song.artist).font(.caption).foregroundStyle(.secondary) }.lineLimit(1).foregroundStyle(.primary) }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("mini-player")
                    Button(library.playing ? "暂停" : "播放", systemImage: library.playing ? "pause.fill" : "play.fill") { library.toggle() }.labelStyle(.iconOnly).font(.title2).foregroundStyle(.primary).frame(width: 36, height: 44)
                }.buttonStyle(.plain).padding(.horizontal, 10).frame(height: 56).glassEffect(.clear.interactive(), in: .capsule)
            }
            }
        }.padding(.horizontal, 12)
    }
    private var importMenu: some View {
        Menu {
            Button("选择音乐文件", systemImage: "music.note") { startImport(folder: false) }
            Button("导入文件夹", systemImage: "folder") { startImport(folder: true) }
            Button("读取 App 内“待导入”文件夹", systemImage: "tray.and.arrow.down") { Task { await library.importInboxContents() } }
        } label: { Label("导入音乐", systemImage: "plus").labelStyle(.titleAndIcon).font(.headline).padding(.horizontal, 24).frame(minHeight: 56).contentShape(Capsule()) }
            .buttonStyle(.plain).glassEffect(.clear.interactive(), in: .capsule).disabled(library.importing).accessibilityIdentifier("import-music")
    }
    private var toolbarImportMenu: some View {
        Menu {
            Button("选择音乐文件", systemImage: "music.note") { startImport(folder: false) }
            Button("导入文件夹", systemImage: "folder") { startImport(folder: true) }
            Button("读取 App 内“待导入”文件夹", systemImage: "tray.and.arrow.down") { Task { await library.importInboxContents() } }
        } label: { Image(systemName: "plus").font(.title2).frame(width: 44, height: 44) }.glassEffect(.clear.interactive(), in: .circle)
            .buttonStyle(.plain).disabled(library.importing).accessibilityLabel("导入音乐").accessibilityIdentifier("import-music")
    }
    private func startImport(folder: Bool, playlistID: UUID? = nil) {
        let request = ImportRequest(folder: folder, playlistID: playlistID)
        library.error = nil
        library.pendingSelectionID = request.id
        library.importStatus = folder ? "等待选择文件夹" : "等待选择音乐文件"
        ImportDiagnostics.record("open picker, folder=\(folder), playlist=\(playlistID != nil), version=\(ImportDiagnostics.version)")
        importRequest = request
    }
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
        Dictionary(grouping: library.librarySongs, by: \.albumKey).map { AlbumGroup(id: $0.key, songs: $0.value) }.sorted { left, right in
            if albumSort == "date", left.first.releaseDate != right.first.releaseDate { return (left.first.releaseDate ?? "") > (right.first.releaseDate ?? "") }
            if albumSort == "artist" {
                let a = left.first.albumArtist ?? left.first.artist, b = right.first.albumArtist ?? right.first.artist
                if a != b { return a.localizedStandardCompare(b) == .orderedAscending }
            }
            return left.first.albumTitle.localizedStandardCompare(right.first.albumTitle) == .orderedAscending
        }
    }
    private var recentAlbums: [AlbumGroup] {
        var seen = Set<String>()
        return library.librarySongs.reversed().compactMap { song in
            guard seen.insert(song.albumKey).inserted else { return nil }
            return albums.first { $0.id == song.albumKey }
        }
    }
    @ViewBuilder private var libraryContent: some View {
        if library.librarySongs.isEmpty && !library.playlists.contains(where: { $0.pinned == true }) { songList([], libraryEmpty: true) }
        else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if library.playlists.contains(where: { $0.pinned == true }) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 18) {
                            ForEach(library.playlists.filter { $0.pinned == true }) { playlist in playlistTile(playlist) }
                        }
                    }
                    VStack(spacing: 0) {
                        NavigationLink { playlistList.navigationTitle("播放列表") } label: { libraryRow("播放列表", icon: "music.note.list") }
                        Divider()
                        NavigationLink { songList(library.librarySongs).navigationTitle("歌曲") } label: { libraryRow("歌曲", icon: "music.note") }
                        Divider()
                        NavigationLink { albumGrid.navigationTitle("专辑") } label: { libraryRow("专辑", icon: "square.stack") }
                        Divider()
                        NavigationLink { ArtistDirectoryView().navigationTitle("歌手") } label: { libraryRow("歌手", icon: "mic") }
                    }.buttonStyle(.plain)
                    if !recentAlbums.isEmpty { Text("最近添加").font(.title2.bold()) }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 22) {
                        ForEach(recentAlbums) { album in
                            NavigationLink { AlbumDetailView(albumKey: album.id) } label: { tile(album.first, title: album.first.albumTitle, subtitle: album.first.albumArtist ?? album.first.artist) }.buttonStyle(.plain).contextMenu { AlbumContextActions(album: album) }
                        }
                    }
                }.padding(20)
            }.background(Color(uiColor: .systemBackground))
        }
    }
    private var albumGrid: some View {
        Group {
            if albums.isEmpty {
                ContentUnavailableView("暂无专辑", systemImage: "square.stack")
            } else { ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 22) {
                ForEach(albums) { album in
                    NavigationLink { AlbumDetailView(albumKey: album.id) } label: {
                        tile(album.first, title: album.first.albumTitle, subtitle: album.first.albumArtist ?? album.first.artist)
                    }.buttonStyle(.plain).contextMenu { AlbumContextActions(album: album) }
                }
            }.padding(20)
            } }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("排列方式", selection: $albumSort) { Text("名称").tag("name"); Text("时间").tag("date"); Text("歌手").tag("artist") }
                } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 44, height: 44) }.glassEffect(.clear.interactive(), in: .circle).buttonStyle(.plain).accessibilityLabel("专辑排列方式")
            }.sharedBackgroundVisibility(.hidden)
        }
    }
    private var playlistList: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 20) {
                ForEach(library.playlists) { playlist in
                    playlistTile(playlist)
                }
            }.padding(20)
            if library.playlists.isEmpty { ContentUnavailableView("暂无播放列表", systemImage: "music.note.list") }
        }.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newPlaylist = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.glassEffect(.clear.interactive(), in: .circle).buttonStyle(.plain).accessibilityLabel("新建播放列表")
            }.sharedBackgroundVisibility(.hidden)
        }
    }
    private func playlistTile(_ playlist: Playlist) -> some View {
        NavigationLink {
            PlaylistDetailView(playlistID: playlist.id) { folder in startImport(folder: folder, playlistID: playlist.id) }
        } label: {
            VStack(spacing: 6) {
                PlaylistCover(playlist: playlist, artwork: library.playlistArtwork[playlist.id]).aspectRatio(1, contentMode: .fit)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                Text(playlist.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
            }
        }.buttonStyle(.plain)
        .contextMenu { Button(playlist.pinned == true ? "取消置顶" : "置顶到资料库", systemImage: playlist.pinned == true ? "pin.slash" : "pin") { library.togglePlaylistPin(playlist.id) } }
    }
    private func libraryRow(_ title: String, icon: String) -> some View {
        HStack { Image(systemName: icon).foregroundStyle(.pink).frame(width: 30); Text(title).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary) }.font(.title3).padding(.vertical, 16).contentShape(Rectangle())
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
                importMenu
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
                        }.buttonStyle(.plain).contextMenu { SongContextActions(song: song, queue: songs) }
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

private struct PlayerAccessory<Accessory: View>: ViewModifier {
    let enabled: Bool
    let accessory: Accessory
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: enabled) { accessory }
        } else if enabled {
            content.tabViewBottomAccessory { accessory }
        } else { content }
    }
}
