import SwiftUI

struct AlbumDetailView: View {
    @Environment(MusicLibrary.self) private var library
    let albumKey: String
    private var songs: [Song] {
        library.librarySongs.filter { $0.albumKey == albumKey }.sorted {
            if $0.discNumber != $1.discNumber { return ($0.discNumber ?? 1) < ($1.discNumber ?? 1) }
            if $0.trackNumber != $1.trackNumber { return ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
    var body: some View {
        ScrollView {
            if let first = songs.first {
                VStack(spacing: 18) {
                    Cover(song: first).aspectRatio(1, contentMode: .fit).frame(maxWidth: 280).shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                    VStack(spacing: 5) {
                        Text(first.albumTitle).font(.title2.bold()).multilineTextAlignment(.center)
                        NavigationLink(first.albumArtist ?? first.artist) { ArtistDetailView(artist: first.albumArtist ?? first.artist) }.font(.title3)
                        Text([first.genre, first.releaseDate].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("播放", systemImage: "play.fill") { library.play(first) }.buttonStyle(.glassProminent)
                    VStack(spacing: 0) {
                        ForEach(songs) { song in
                            Button { library.play(song) } label: {
                                HStack {
                                    Text(song.trackNumber.map(String.init) ?? "–").foregroundStyle(.secondary).frame(width: 28)
                                    Text(song.title).foregroundStyle(.primary).lineLimit(1)
                                    Spacer()
                                    if library.currentID == song.id { Image(systemName: "waveform") }
                                }.padding(.vertical, 14).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(songs.count) 首歌曲")
                        if let value = first.releaseDate { Text("发行日期：\(value)") }
                        if let value = first.recordLabel { Text("发行公司：\(value)") }
                        ForEach(Array(Set(songs.compactMap { $0.quality?.description })).sorted(), id: \.self) { Text($0) }
                        if let value = first.copyright { Text(value) }
                    }.font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(24)
            }
        }.navigationBarTitleDisplayMode(.inline)
    }
}

struct ArtistDetailView: View {
    @Environment(MusicLibrary.self) private var library
    let artist: String
    @State private var importing = false
    private var albums: [AlbumGroup] {
        Dictionary(grouping: library.librarySongs.filter { $0.artist == artist || $0.albumArtist == artist }, by: \.albumKey)
            .map { AlbumGroup(id: $0.key, songs: $0.value) }.sorted { ($0.first.releaseDate ?? "") > ($1.first.releaseDate ?? "") }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Group {
                    if let data = library.artistArtwork[artist], let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
                    else { Circle().fill(.quaternary).overlay { Image(systemName: "person.fill").font(.system(size: 70)).foregroundStyle(.secondary) } }
                }.frame(width: 180, height: 180).clipShape(Circle())
                Button("设置艺人封面") { importing = true }.font(.subheadline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 22) {
                    ForEach(albums) { album in
                        NavigationLink { AlbumDetailView(albumKey: album.id) } label: {
                            VStack(alignment: .leading) {
                                Cover(song: album.first).aspectRatio(1, contentMode: .fit)
                                Text(album.first.albumTitle).font(.subheadline).lineLimit(2)
                                if let date = album.first.releaseDate { Text(date).font(.caption).foregroundStyle(.secondary) }
                            }.foregroundStyle(.primary)
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(20)
        }.navigationTitle(artist)
        .sheet(isPresented: $importing) {
            DocumentImportPicker(types: [.image]) { urls in
                importing = false
                if let url = urls.first { Task { await library.setArtistArtwork(url, artist: artist) } }
            }
        }
    }
}
