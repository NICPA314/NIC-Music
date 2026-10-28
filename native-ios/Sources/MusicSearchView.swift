import SwiftUI

struct MusicSearchView: View {
    @Environment(MusicLibrary.self) private var library
    @State private var query = ""
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var tracks: [Song] { library.librarySongs.filter { ($0.title + " " + $0.artist + " " + ($0.album ?? "")).localizedCaseInsensitiveContains(term) } }
    private var albums: [AlbumGroup] {
        Dictionary(grouping: library.librarySongs, by: \.albumKey).map { AlbumGroup(id: $0.key, songs: $0.value) }
            .filter { $0.first.albumTitle.localizedCaseInsensitiveContains(term) }.sorted { $0.first.albumTitle < $1.first.albumTitle }
    }
    private var artists: [String] {
        Array(Set(library.librarySongs.flatMap { [$0.artist, $0.albumArtist ?? $0.artist] }))
            .filter { $0.localizedCaseInsensitiveContains(term) }.sorted()
    }
    var body: some View {
        VStack(spacing: 0) {
            searchField
            searchContent
        }
    }
    @ViewBuilder private var searchContent: some View {
        Group {
            if term.isEmpty { categories }
            else if tracks.isEmpty && albums.isEmpty && artists.isEmpty { ContentUnavailableView.search(text: term) }
            else {
                List {
                    if !tracks.isEmpty { Section("歌曲") { ForEach(tracks) { song in SearchTrackRow(song: song, queue: tracks) } } }
                    if !albums.isEmpty {
                        Section("专辑") {
                            ForEach(albums) { album in
                                NavigationLink { AlbumDetailView(albumKey: album.id) } label: {
                                    HStack(spacing: 12) { Cover(song: album.first).frame(width: 52, height: 52); VStack(alignment: .leading, spacing: 4) { Text(album.first.albumTitle); Text(album.first.albumArtist ?? album.first.artist).font(.subheadline).foregroundStyle(.secondary) } }
                                }
                            }
                        }
                    }
                    if !artists.isEmpty {
                        Section("歌手") { ForEach(artists, id: \.self) { artist in NavigationLink { ArtistDetailView(artist: artist) } label: { HStack(spacing: 12) { ArtistPortrait(data: library.artistArtwork[artist]).frame(width: 52, height: 52); Text(artist) } } } }
                    }
                }.listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var searchField: some View {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("歌曲、专辑、歌手", text: $query).submitLabel(.search).accessibilityIdentifier("music-search-field")
                if !query.isEmpty { Button("清除", systemImage: "xmark.circle.fill") { query = "" }.labelStyle(.iconOnly).foregroundStyle(.secondary) }
            }.padding(16).glassEffect(.clear.interactive(), in: .capsule).padding(.horizontal, 20).padding(.bottom, 12)
    }
    private var categories: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(SearchCategory.all) { category in
                    let songs = library.librarySongs.filter(category.contains)
                    NavigationLink {
                        Group {
                            if songs.isEmpty { ContentUnavailableView("暂无歌曲", systemImage: category.icon) }
                            else { List(songs) { song in SearchTrackRow(song: song, queue: songs) }.listStyle(.plain) }
                        }.navigationTitle(category.title)
                    } label: { SearchCategoryCard(category: category, artwork: songs.first?.artwork) }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
    }
}

private struct SearchTrackRow: View {
    @Environment(MusicLibrary.self) private var library
    let song: Song
    let queue: [Song]
    var body: some View {
        Button { library.play(song, queue: queue) } label: {
            HStack(spacing: 12) {
                Cover(song: song).frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 4) { Text(song.title).foregroundStyle(.primary); Text(song.artist).font(.subheadline).foregroundStyle(.secondary) }.lineLimit(1)
                Spacer()
                if song.id == library.currentID { Image(systemName: "waveform").foregroundStyle(.pink) }
            }.padding(.vertical, 5).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct SearchCategory: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let keywords: [String]
    func contains(_ song: Song) -> Bool {
        if id == "all" { return true }
        if id == "favorites" { return song.favorite == true }
        if id == "lossless" { return song.quality?.lossless == true }
        if id == "lyrics" { return song.lyrics != nil }
        return keywords.contains { (song.genre ?? "").localizedCaseInsensitiveContains($0) }
    }
    static let all = [
        SearchCategory(id: "all", title: "全部音乐", icon: "music.note", color: .indigo, keywords: []),
        SearchCategory(id: "favorites", title: "喜爱的歌曲", icon: "star.fill", color: Color(red: 0.9, green: 0.56, blue: 0.05), keywords: []),
        SearchCategory(id: "pop", title: "流行乐", icon: "mic.fill", color: Color(red: 0.88, green: 0.29, blue: 0.49), keywords: ["pop", "流行"]),
        SearchCategory(id: "hiphop", title: "嘻哈／说唱", icon: "waveform", color: Color(red: 0.34, green: 0.43, blue: 0.85), keywords: ["hip", "rap", "说唱", "嘻哈"]),
        SearchCategory(id: "country", title: "乡村音乐", icon: "guitars.fill", color: Color(red: 0.82, green: 0.43, blue: 0.04), keywords: ["country", "乡村"]),
        SearchCategory(id: "dance", title: "舞曲", icon: "sparkles", color: Color(red: 0.12, green: 0.61, blue: 0.43), keywords: ["dance", "electronic", "舞曲", "电子"]),
        SearchCategory(id: "rock", title: "摇滚", icon: "bolt.fill", color: Color(red: 0.88, green: 0.29, blue: 0.15), keywords: ["rock", "摇滚"]),
        SearchCategory(id: "rnb", title: "R&B", icon: "pianokeys", color: Color(red: 0.5, green: 0.33, blue: 0.75), keywords: ["r&b", "soul", "节奏布鲁斯"]),
        SearchCategory(id: "lossless", title: "无损音乐", icon: "waveform.path", color: .teal, keywords: []),
        SearchCategory(id: "lyrics", title: "跟着歌词唱", icon: "quote.bubble.fill", color: .purple, keywords: [])
    ]
}

private struct SearchCategoryCard: View {
    let category: SearchCategory
    let artwork: Data?
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                category.color
                if let artwork, let image = UIImage(data: artwork) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width * 0.72, height: 130)
                        .clipped().rotationEffect(.degrees(12)).offset(x: geometry.size.width * 0.37, y: -8).blendMode(.luminosity).opacity(0.6)
                } else {
                    Image(systemName: category.icon).font(.system(size: 64, weight: .bold)).foregroundStyle(.white.opacity(0.2)).rotationEffect(.degrees(-12)).offset(x: geometry.size.width * 0.45, y: -22)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                Text(category.title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white).lineLimit(2).padding(14)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
        }.frame(height: 112)
    }
}
