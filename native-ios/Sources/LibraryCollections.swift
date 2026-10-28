import SwiftUI

struct PlaylistCover: View {
    let playlist: Playlist
    let artwork: Data?
    private var palette: [Color] {
        let choices: [[Color]] = [[.pink, .red, .orange], [.indigo, .purple, .pink], [.blue, .cyan, .mint], [.orange, .pink, .purple]]
        let number = playlist.id.uuidString.utf8.reduce(0) { ($0 + Int($1)) % choices.count }
        return choices[number]
    }
    var body: some View {
        GeometryReader { geometry in
            if let artwork, let image = UIImage(data: artwork) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(.white.opacity(0.14)).frame(width: geometry.size.width * 1.2).offset(x: geometry.size.width * 0.3, y: -geometry.size.height * 0.25)
                    LinearGradient(colors: [.clear, .black.opacity(0.2)], startPoint: .center, endPoint: .bottom)
                    Text(playlist.name).font(.system(size: max(16, geometry.size.width * 0.15), weight: .bold, design: .rounded))
                        .foregroundStyle(.white).lineLimit(3).minimumScaleFactor(0.55)
                        .padding(max(9, geometry.size.width * 0.09))
                }
            }
        }.clipped().clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ArtistPortrait: View {
    let data: Data?
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Circle().fill(Color(uiColor: .secondarySystemFill))
                        .overlay { Image(systemName: "person.fill").font(.system(size: geometry.size.width * 0.45)).foregroundStyle(.secondary) }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipShape(Circle())
        }
    }
}

struct ArtistDirectoryView: View {
    @Environment(MusicLibrary.self) private var library
    private var artists: [String] {
        Array(Set(library.librarySongs.flatMap { [$0.artist, $0.albumArtist ?? $0.artist] })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var body: some View {
        if artists.isEmpty { ContentUnavailableView("暂无歌手", systemImage: "person.crop.circle") }
        else {
            List(artists, id: \.self) { artist in
                let tracks = library.librarySongs.filter { $0.artist == artist || $0.albumArtist == artist }
                NavigationLink { ArtistDetailView(artist: artist) } label: {
                    HStack(spacing: 14) {
                        ArtistPortrait(data: library.artistArtwork[artist]).frame(width: 60, height: 60)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(artist).font(.title3).foregroundStyle(.primary).lineLimit(1)
                            Text("\(Set(tracks.map(\.albumKey)).count) 张专辑").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("\(tracks.count) 首歌曲").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }.padding(.vertical, 7)
                }.listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
            }.listStyle(.plain)
        }
    }
}

struct PlaylistDetailView: View {
    @Environment(MusicLibrary.self) private var library
    let playlistID: UUID
    let onImport: (Bool) -> Void
    @State private var chooseCover = false
    @State private var savingCover = false
    private var playlist: Playlist? { library.playlists.first { $0.id == playlistID } }
    private var songs: [Song] { playlist?.songIDs.compactMap { id in library.songs.first { $0.id == id } } ?? [] }
    var body: some View {
        ScrollView {
            if let playlist {
                VStack(spacing: 18) {
                    PlaylistCover(playlist: playlist, artwork: library.playlistArtwork[playlistID]).aspectRatio(1, contentMode: .fit).frame(maxWidth: 280)
                    Text(playlist.name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text("\(songs.count) 首歌曲").foregroundStyle(.secondary).font(.subheadline)
                    Menu {
                        Button("选择封面", systemImage: "photo") { chooseCover = true }
                        Button(playlist.pinned == true ? "取消置顶" : "置顶到资料库", systemImage: playlist.pinned == true ? "pin.slash" : "pin") { library.togglePlaylistPin(playlistID) }
                        if playlist.artworkFilename != nil {
                            Button("使用默认封面", systemImage: "arrow.counterclockwise") { Task { await library.setPlaylistArtwork(nil, playlistID: playlistID) } }
                        }
                    } label: { Label("编辑封面", systemImage: "photo").padding(.horizontal, 20).frame(height: 48).glassEffect(.clear.interactive(), in: .capsule) }
                        .buttonStyle(.plain).disabled(savingCover)
                    if savingCover { ProgressView() }
                    if let first = songs.first {
                        Button("播放", systemImage: "play.fill") { library.play(first, queue: songs) }.buttonStyle(ClearGlassButtonStyle())
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(songs) { song in
                            Button { library.play(song, queue: songs) } label: {
                                HStack(spacing: 12) {
                                    Cover(song: song).frame(width: 48, height: 48)
                                    VStack(alignment: .leading, spacing: 4) { Text(song.title).foregroundStyle(.primary); Text(song.artist).font(.subheadline).foregroundStyle(.secondary) }.lineLimit(1)
                                    Spacer()
                                    if song.id == library.currentID { Image(systemName: "waveform").foregroundStyle(.pink) }
                                }.padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }.padding(24)
            }
        }.navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("选择音乐文件") { onImport(false) }
                    Button("导入文件夹") { onImport(true) }
                } label: { Image(systemName: "plus").frame(width: 48, height: 48).glassEffect(.clear.interactive(), in: .circle) }.buttonStyle(.plain).disabled(library.importing)
            }.sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $chooseCover) {
            DocumentImportPicker(types: [.image]) { urls in
                chooseCover = false
                if let url = urls.first {
                    savingCover = true
                    Task { await library.setPlaylistArtwork(url, playlistID: playlistID); savingCover = false }
                }
            }
        }
    }
}
