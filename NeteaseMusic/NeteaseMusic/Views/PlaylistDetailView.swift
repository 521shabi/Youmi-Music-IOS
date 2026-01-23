import SwiftUI

struct PlaylistDetailView: View {
    let playlistId: Int
    let playlistName: String
    let coverUrl: String?
    
    @State private var playlist: PlaylistDetail?
    @State private var isLoading = true
    @StateObject private var audioPlayer = AudioPlayer.shared
    
    // 导航状态提升到父视图
    @State private var selectedArtist: Artist?
    @State private var selectedAlbum: Album?
    @State private var showArtistDetail = false
    @State private var showAlbumDetail = false
    
    private let musicService = MusicService.shared
    
    // 性能优化：缓存触觉反馈生成器
    private static let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        ScrollView {
            // 性能优化：使用更高效的LazyVStack配置
            LazyVStack(spacing: 0, pinnedViews: []) {
                // 头部信息
                headerView

                // 播放全部按钮
                playAllButton

                // 歌曲列表
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 50)
                } else if let tracks = playlist?.tracks, !tracks.isEmpty {
                    // 性能优化：提前计算常用值
                    let currentTrackId = audioPlayer.currentTrack?.id
                    let isPlaying = audioPlayer.isPlaying

                    // 性能优化：使用track.id作为ForEach的唯一标识符
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        OptimizedTrackRow(
                            track: track,
                            index: index + 1,
                            isCurrentTrack: track.id == currentTrackId,
                            isPlaying: isPlaying
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Self.impactGenerator.impactOccurred()
                            audioPlayer.setPlaylist(tracks, startAt: index)
                        }
                        .contextMenu {
                            if let artist = track.ar?.first {
                                Button {
                                    selectedArtist = artist
                                    showArtistDetail = true
                                } label: {
                                    Label("查看歌手: \(artist.name)", systemImage: "person")
                                }
                            }
                            if let album = track.al {
                                Button {
                                    selectedAlbum = album
                                    showAlbumDetail = true
                                } label: {
                                    Label("查看专辑: \(album.name)", systemImage: "square.stack")
                                }
                            }
                        }

                        if index < tracks.count - 1 {
                            Divider()
                                .padding(.leading, 70)
                        }
                    }
                } else {
                    HStack {
                        Spacer()
                        Text("暂无歌曲")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.top, 50)
                }
            }
            .padding(.bottom, 120)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPlaylist()
        }
        .navigationDestination(isPresented: $showArtistDetail) {
            if let artist = selectedArtist {
                ArtistDetailView(artistId: artist.id, artistName: artist.name)
            }
        }
        .navigationDestination(isPresented: $showAlbumDetail) {
            if let album = selectedAlbum {
                AlbumDetailView(albumId: album.id, albumName: album.name)
            }
        }
    }
    
    // MARK: - 头部视图
    private var headerView: some View {
        HStack(alignment: .top, spacing: 16) {
            // 封面
            if let url = coverUrl, let imageUrl = URL(string: url) {
                CachedAsyncImage(url: imageUrl, targetSize: CGSize(width: 120, height: 120)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color(.systemGray5))
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(playlistName)
                    .font(.headline)
                    .lineLimit(2)
                
                if let creator = playlist?.creator {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.gray)
                        Text(creator.nickname)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                if let desc = playlist?.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                
                if let count = playlist?.trackCount {
                    Text("\(count) 首歌曲")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - 播放全部按钮
    private var playAllButton: some View {
        Button(action: {
            if let tracks = playlist?.tracks, !tracks.isEmpty {
                audioPlayer.setPlaylist(tracks, startAt: 0)
            }
        }) {
            HStack {
                Image(systemName: "play.fill")
                Text("播放全部")
                    .fontWeight(.medium)
                if let count = playlist?.trackCount {
                    Text("(\(count))")
                        .foregroundColor(.gray)
                }
                Spacer()
            }
            .padding()
        }
        .foregroundColor(.primary)
    }
    
    // MARK: - 加载歌单
    private func loadPlaylist() async {
        isLoading = true
        do {
            playlist = try await musicService.getPlaylistDetail(id: playlistId)
        } catch {
            print("Load playlist error: \(error)")
        }
        isLoading = false
    }
}

// MARK: - 歌曲行（支持歌手/专辑导航）
struct TrackRow: View {
    let track: Track
    let index: Int
    let isCurrentTrack: Bool
    let isPlaying: Bool
    var onArtistTap: ((Artist) -> Void)? = nil
    var onAlbumTap: ((Album) -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            // 序号或播放指示
            ZStack {
                if isCurrentTrack && isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.red)
                } else {
                    Text("\(index)")
                        .foregroundColor(isCurrentTrack ? .red : .gray)
                }
            }
            .frame(width: 30)
            
            // 封面
            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 45, height: 45)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color(.systemGray5))
                }
                .frame(width: 45, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            
            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.subheadline)
                    .foregroundColor(isCurrentTrack ? .red : .primary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(track.artistName)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                    
                    Text("·")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text(track.albumName)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 更多菜单
            Menu {
                if let artist = track.ar?.first {
                    Button {
                        onArtistTap?(artist)
                    } label: {
                        Label("查看歌手: \(artist.name)", systemImage: "person")
                    }
                }
                
                if let album = track.al {
                    Button {
                        onAlbumTap?(album)
                    } label: {
                        Label("查看专辑: \(album.name)", systemImage: "square.stack")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - 优化的歌曲行（性能优化版 - 使用Equatable避免不必要重绘）
struct OptimizedTrackRow: View, Equatable {
    let track: Track
    let index: Int
    let isCurrentTrack: Bool
    let isPlaying: Bool
    
    // Equatable实现：只比较影响视图的属性
    static func == (lhs: OptimizedTrackRow, rhs: OptimizedTrackRow) -> Bool {
        lhs.track.id == rhs.track.id &&
        lhs.index == rhs.index &&
        lhs.isCurrentTrack == rhs.isCurrentTrack &&
        lhs.isPlaying == rhs.isPlaying
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 序号或播放指示
            indexView
                .frame(width: 30)
            
            // 封面
            coverView
            
            // 歌曲信息
            infoView
            
            Spacer()
            
            // 更多按钮
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var indexView: some View {
        if isCurrentTrack && isPlaying {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundColor(.red)
        } else {
            Text("\(index)")
                .font(.system(size: 14))
                .foregroundColor(isCurrentTrack ? .red : .gray)
        }
    }
    
    @ViewBuilder
    private var coverView: some View {
        if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
            CachedAsyncImage(url: url, targetSize: CGSize(width: 45, height: 45)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color(.systemGray5))
            }
            .frame(width: 45, height: 45)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(width: 45, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
    
    private var infoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.name)
                .font(.subheadline)
                .foregroundColor(isCurrentTrack ? .red : .primary)
                .lineLimit(1)
            
            Text("\(track.artistName) · \(track.albumName)")
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
        }
    }
}

#Preview {
    NavigationView {
        PlaylistDetailView(
            playlistId: 3778678,
            playlistName: "测试歌单",
            coverUrl: nil
        )
    }
}
