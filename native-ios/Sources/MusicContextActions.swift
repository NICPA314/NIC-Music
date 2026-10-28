import SwiftUI

struct SongContextActions: View {
    @Environment(MusicLibrary.self) private var library
    let song: Song
    let queue: [Song]
    var body: some View {
        Button(song.favorite == true ? "取消喜爱" : "喜爱", systemImage: song.favorite == true ? "star.slash" : "star") { library.toggleFavorite(song.id) }
        Button("播放", systemImage: "play.fill") { library.play(song, queue: queue) }
        ShareLink(item: library.folder.appendingPathComponent(song.filename)) { Label("分享", systemImage: "square.and.arrow.up") }
    }
}
struct AlbumContextActions: View {
    @Environment(MusicLibrary.self) private var library
    let album: AlbumGroup
    var body: some View {
        Button("播放", systemImage: "play.fill") { library.play(album.first, queue: album.songs) }
        Button("喜爱专辑歌曲", systemImage: "star") { for song in album.songs where song.favorite != true { library.toggleFavorite(song.id) } }
        Button("重新读取歌曲信息", systemImage: "arrow.clockwise") { Task { await library.refreshAlbumMetadata(album.id) } }
    }
}
