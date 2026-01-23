import SwiftUI

// MARK: - 歌手详情视图
struct ArtistDetailView: View {
    let artistId: Int
    let artistName: String
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var audioPlayer = AudioPlayer.shared
    @State private var artist: ArtistDetail?
    @State private var topSongs: [Track] = []
    @State private var albums: [AlbumDetail] = []
    @State private var isLoading = true
    @State private var showAllSongs = false
    @State private var scrollOffset: CGFloat = 0
    @State private var searchText = ""
    @State private var isSearching = false
    
    private let musicService = MusicService.shared
    
    // 过滤后的歌曲列表
    private var filteredSongs: [Track] {
        if searchText.isEmpty {
            return topSongs
        }
        let query = searchText.lowercased()
        return topSongs.filter {
            $0.name.lowercased().contains(query) ||
            $0.albumName.lowercased().contains(query)
        }
    }
    
    var body: some View {
        ZStack {
            // 背景
            backgroundView
            
            // 内容
            ScrollView(showsIndicators: false) {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("scroll")).minY
                    )
                }
                .frame(height: 0)
                
                VStack(spacing: 0) {
                    // 顶部留白（为背景图留空间）
                    Color.clear.frame(height: 380)
                    
                    // 主内容区
                    VStack(spacing: 24) {
                        // 歌手信息
                        artistInfoSection
                        
                        // 热门歌曲
                        if !topSongs.isEmpty {
                            topSongsSection
                        }
                        
                        // 专辑
                        if !albums.isEmpty {
                            albumsSection
                        }
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color(.systemBackground))
                    )
                }
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                scrollOffset = value
            }
            
            // 顶部导航栏
            VStack {
                navigationBar
                Spacer()
            }
            
            // 加载中
            if isLoading {
                loadingOverlay
            }
        }
        .navigationBarHidden(true)
        .ignoresSafeArea()
        .enableSwipeBack()
        .task {
            await loadData()
        }
    }
    
    // MARK: - 背景视图
    private var backgroundView: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black
                
                // 歌手图片背景
                if let imageUrl = artist?.imageUrl, let url = URL(string: imageUrl) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: 450 + max(0, scrollOffset))
                            .clipped()
                    } placeholder: {
                        LinearGradient(
                            colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: geo.size.width, height: 450)
                    }
                    .offset(y: min(0, scrollOffset))
                    
                    // 渐变遮罩
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.5),
                            .init(color: Color.black.opacity(0.7), location: 0.8),
                            .init(color: Color.black, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: geo.size.width, height: 450)
                }
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - 顶部导航栏
    private var navigationBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            // 标题（滚动后显示）
            if scrollOffset < -150 {
                Text(artist?.name ?? artistName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .transition(.opacity)
            }
            
            Spacer()
            
            // 占位
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 54)
        .background(
            scrollOffset < -150 ?
            Color(.systemBackground).opacity(0.95) :
            Color.clear
        )
        .animation(.easeInOut(duration: 0.2), value: scrollOffset < -150)
    }
    
    // MARK: - 歌手信息区域
    private var artistInfoSection: some View {
        VStack(spacing: 16) {
            // 名字
            Text(artist?.name ?? artistName)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
            
            // 统计信息
            HStack(spacing: 32) {
                if let musicSize = artist?.musicSize {
                    statItem(value: "\(musicSize)", label: "单曲")
                }
                if let albumSize = artist?.albumSize {
                    statItem(value: "\(albumSize)", label: "专辑")
                }
                if let mvSize = artist?.mvSize, mvSize > 0 {
                    statItem(value: "\(mvSize)", label: "MV")
                }
            }
            
            // 简介
            if let desc = artist?.briefDesc, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            // 播放全部按钮
            if !topSongs.isEmpty {
                Button(action: {
                    audioPlayer.setPlaylist(topSongs, startAt: 0)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                        Text("播放热门歌曲")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.pink, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .pink.opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 统计项
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - 热门歌曲区域
    private var topSongsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                    Text("热门歌曲")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // 搜索按钮
                Button(action: { 
                    withAnimation(.spring(response: 0.3)) {
                        isSearching.toggle()
                        if !isSearching {
                            searchText = ""
                        }
                    }
                }) {
                    Image(systemName: isSearching ? "xmark.circle.fill" : "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                
                if topSongs.count > 5 && !isSearching {
                    Button(action: { showAllSongs.toggle() }) {
                        Text(showAllSongs ? "收起" : "全部")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // 搜索框
            if isSearching {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索歌曲", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // 搜索结果为空
            if isSearching && !searchText.isEmpty && filteredSongs.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("未找到 \"\(searchText)\"")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 30)
                    Spacer()
                }
            } else {
                // 歌曲列表
                LazyVStack(spacing: 0) {
                    let songsToShow = isSearching ? filteredSongs : (showAllSongs ? topSongs : Array(topSongs.prefix(5)))
                    ForEach(Array(songsToShow.enumerated()), id: \.element.id) { index, track in
                        let originalIndex = topSongs.firstIndex(where: { $0.id == track.id }) ?? index
                        ArtistTrackRow(
                            track: track,
                            index: originalIndex + 1,
                            isPlaying: audioPlayer.currentTrack?.id == track.id
                        )
                        .onTapGesture {
                            audioPlayer.setPlaylist(topSongs, startAt: originalIndex)
                        }
                        
                        if index < songsToShow.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - 专辑区域
    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 16))
                        .foregroundColor(.purple)
                    Text("专辑")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // 专辑横向滚动
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(albums) { album in
                        NavigationLink(destination: AlbumDetailView(albumId: album.id, albumName: album.name)) {
                            ArtistAlbumCard(album: album)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    // MARK: - 加载中遮罩
    private var loadingOverlay: some View {
        ZStack {
            Color(.systemBackground).opacity(0.8)
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("加载中...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - 加载数据
    private func loadData() async {
        do {
            async let artistTask = musicService.getArtistDetail(id: artistId)
            async let songsTask = musicService.getArtistTopSongs(id: artistId)
            async let albumsTask = musicService.getArtistAlbums(id: artistId, limit: 20)
            
            let (artistResult, songsResult, albumsResult) = try await (artistTask, songsTask, albumsTask)
            
            await MainActor.run {
                artist = artistResult
                topSongs = songsResult
                albums = albumsResult
                isLoading = false
            }
        } catch {
            print("Load artist data error: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - 滚动偏移量 Key
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 歌手歌曲行
struct ArtistTrackRow: View {
    let track: Track
    let index: Int
    let isPlaying: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // 序号
            ZStack {
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                } else {
                    Text("\(index)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(index <= 3 ? .orange : .secondary)
                }
            }
            .frame(width: 28)
            
            // 封面
            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 44, height: 44)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.system(size: 15, weight: isPlaying ? .semibold : .regular))
                    .foregroundColor(isPlaying ? .red : .primary)
                    .lineLimit(1)
                
                Text(track.albumName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 更多
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - 歌手专辑卡片
struct ArtistAlbumCard: View {
    let album: AlbumDetail
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 封面
            if let picUrl = album.picUrl, let url = URL(string: picUrl) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 140, height: 140)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color(.systemGray4), Color(.systemGray5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            }
            
            // 专辑名
            Text(album.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(width: 140, alignment: .leading)
            
            // 发行时间
            Text(album.publishTimeText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    NavigationView {
        ArtistDetailView(artistId: 12138269, artistName: "G.E.M.邓紫棋")
    }
}
