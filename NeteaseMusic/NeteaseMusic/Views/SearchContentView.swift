import SwiftUI

// MARK: - 搜索历史管理器
class SearchHistoryManager: ObservableObject {
    static let shared = SearchHistoryManager()
    
    @Published var history: [SearchHistoryEntry] = []
    
    private let userDefaultsKey = "SearchHistory"
    private let maxHistoryCount = 20
    
    init() {
        loadHistory()
    }
    
    func addSearch(keyword: String, type: SearchHistoryEntry.SearchType = .keyword) {
        // 移除重复项
        history.removeAll { $0.keyword == keyword }
        
        // 添加到开头
        let entry = SearchHistoryEntry(keyword: keyword, type: type, timestamp: Date())
        history.insert(entry, at: 0)
        
        // 限制数量
        if history.count > maxHistoryCount {
            history = Array(history.prefix(maxHistoryCount))
        }
        
        saveHistory()
    }
    
    func removeSearch(keyword: String) {
        history.removeAll { $0.keyword == keyword }
        saveHistory()
    }
    
    func clearHistory() {
        history.removeAll()
        saveHistory()
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data) {
            history = decoded
        }
    }
}

// MARK: - 搜索历史条目
struct SearchHistoryEntry: Codable, Identifiable {
    var id: String { keyword }
    let keyword: String
    let type: SearchType
    let timestamp: Date
    
    enum SearchType: String, Codable {
        case keyword
        case song
        case album
        case artist
    }
}

// MARK: - 搜索分类
enum SearchCategory: String, CaseIterable {
    case best = "最佳结果"
    case artist = "艺人"
    case album = "专辑"
    case song = "歌曲"
    
    var icon: String {
        switch self {
        case .best: return "star.fill"
        case .artist: return "person.fill"
        case .album: return "square.stack.fill"
        case .song: return "music.note"
        }
    }
}

// MARK: - 全屏搜索界面
struct FullScreenSearchView: View {
    @Binding var isSearchMode: Bool
    let previousTabIcon: String
    
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    // 搜索状态
    @StateObject private var historyManager = SearchHistoryManager.shared
    @State private var hotSearches: [HotSearch] = []
    @State private var selectedCategory: SearchCategory = .best
    
    // 搜索结果
    @State private var songResults: [SearchSong] = []
    @State private var artistResults: [SearchArtistResult] = []
    @State private var albumResults: [SearchAlbumResult] = []
    
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 上方搜索内容区域
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if hasSearched {
                            // 分类标签栏
                            categoryTabBar
                            
                            // 搜索结果
                            searchResultsView
                        } else {
                            // 搜索历史和热搜
                            searchHistoryView
                            hotSearchView
                        }
                    }
                    .padding(.bottom, 100)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                
                Spacer(minLength: 0)
                
                // 底部搜索栏
                searchBarView
            }
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
        }
        .onAppear {
            loadHotSearches()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                hasSearched = false
                songResults = []
                artistResults = []
                albumResults = []
            }
        }
    }
    
    // MARK: - 分类标签栏
    private var categoryTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SearchCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedCategory = category
                        }
                    } label: {
                        Text(category.rawValue)
                            .font(.system(size: 15, weight: selectedCategory == category ? .semibold : .regular))
                            .foregroundColor(selectedCategory == category ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedCategory == category ? Color.red : Color(.systemGray5))
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - 搜索历史视图
    @ViewBuilder
    private var searchHistoryView: some View {
        if !historyManager.history.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("最近搜索")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button("清除") {
                        withAnimation {
                            historyManager.clearHistory()
                        }
                    }
                    .font(.system(size: 15))
                    .foregroundColor(.red)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                // 搜索历史列表
                ForEach(historyManager.history) { entry in
                    SearchHistoryRowView(
                        entry: entry,
                        onTap: {
                            searchText = entry.keyword
                            performSearch()
                        },
                        onDelete: {
                            withAnimation {
                                historyManager.removeSearch(keyword: entry.keyword)
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - 热搜视图
    @ViewBuilder
    private var hotSearchView: some View {
        if !hotSearches.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("热门搜索")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                
                // 热搜列表
                ForEach(Array(hotSearches.enumerated()), id: \.element.id) { index, item in
                    HotSearchRow(index: index + 1, item: item) {
                        searchText = item.searchWord
                        performSearch()
                    }
                }
            }
        }
    }
    
    // MARK: - 搜索结果视图
    @ViewBuilder
    private var searchResultsView: some View {
        if isSearching {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("搜索中...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else if let error = errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else {
            switch selectedCategory {
            case .best:
                bestResultsView
            case .artist:
                artistResultsView
            case .album:
                albumResultsView
            case .song:
                songResultsView
            }
        }
    }
    
    // MARK: - 最佳结果视图
    @ViewBuilder
    private var bestResultsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 艺人结果（显示第一个匹配的艺人）
            if let firstArtist = artistResults.first {
                BestMatchArtistRow(artist: firstArtist)
            }
            
            // 歌曲结果
            ForEach(songResults) { song in
                SearchResultRow(song: song, coverUrl: getCoverUrl(for: song)) {
                    playSong(song)
                }
            }
            
            if songResults.isEmpty && artistResults.isEmpty {
                emptyResultView
            }
        }
    }
    
    // MARK: - 艺人结果视图
    @ViewBuilder
    private var artistResultsView: some View {
        if artistResults.isEmpty {
            emptyResultView
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(artistResults) { artist in
                    ArtistResultRow(artist: artist)
                }
            }
        }
    }
    
    // MARK: - 专辑结果视图
    @ViewBuilder
    private var albumResultsView: some View {
        if albumResults.isEmpty {
            emptyResultView
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(albumResults) { album in
                    AlbumResultRow(album: album)
                }
            }
        }
    }
    
    // MARK: - 歌曲结果视图
    @ViewBuilder
    private var songResultsView: some View {
        if songResults.isEmpty {
            emptyResultView
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(songResults) { song in
                    SearchResultRow(song: song, coverUrl: getCoverUrl(for: song)) {
                        playSong(song)
                    }
                }
            }
        }
    }
    
    // MARK: - 空结果视图
    private var emptyResultView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("未找到\"\(searchText)\"的相关结果")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - 底部搜索栏
    @StateObject private var audioPlayer = AudioPlayer.shared
    @State private var showPlayer = false
    
    private var showMiniPlayer: Bool {
        audioPlayer.currentTrack != nil
    }
    
    private var searchBarView: some View {
        VStack(spacing: 0) {
            // 迷你播放器
            if showMiniPlayer {
                SearchMiniPlayerBar(showPlayer: $showPlayer)
            }
            
            // 搜索栏
            HStack(spacing: 10) {
                // 左边返回按钮（显示之前 Tab 的图标）
                Button {
                    HapticFeedback.light()
                    isSearchFocused = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isSearchMode = false
                    }
                } label: {
                    Image(systemName: previousTabIcon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 48, height: 48)
                }
                .liquidGlassCircle()
                
                // 搜索框
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("艺人、歌曲、歌词以及更多内容", text: $searchText)
                        .font(.system(size: 16))
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            performSearch()
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            hasSearched = false
                            songResults = []
                            artistResults = []
                            albumResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 16))
                
                // 关闭按钮
                Button {
                    HapticFeedback.light()
                    isSearchFocused = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isSearchMode = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 48, height: 48)
                }
                .liquidGlassCircle()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(
            Rectangle()
                .fill(Color(.systemBackground).opacity(0.8))
                .background(.ultraThinMaterial)
        )
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
        }
    }
    
    // MARK: - 加载热搜
    private func loadHotSearches() {
        Task {
            do {
                let results = try await MusicService.shared.getHotSearch()
                await MainActor.run {
                    hotSearches = Array(results.prefix(10))
                }
            } catch {
                print("加载热搜失败: \(error)")
            }
        }
    }
    
    // 歌曲详情缓存（包含封面）
    @State private var songDetailsCache: [Int: Track] = [:]
    
    // MARK: - 执行搜索
    private func performSearch() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        
        // 添加到搜索历史
        historyManager.addSearch(keyword: keyword)
        
        isSearching = true
        hasSearched = true
        errorMessage = nil
        selectedCategory = .best
        
        Task {
            do {
                // 并行搜索歌曲、艺人、专辑
                async let songs = MusicService.shared.search(keyword: keyword, limit: 30)
                async let artists = MusicService.shared.searchArtists(keyword: keyword, limit: 10)
                async let albums = MusicService.shared.searchAlbums(keyword: keyword, limit: 10)
                
                let (songRes, artistRes, albumRes) = try await (songs, artists, albums)
                
                await MainActor.run {
                    songResults = songRes
                    artistResults = artistRes
                    albumResults = albumRes
                    isSearching = false
                }
                
                // 异步获取歌曲详情（包含封面）
                if !songRes.isEmpty {
                    let ids = songRes.map { $0.id }
                    if let details = try? await MusicService.shared.getSongDetail(ids: ids) {
                        var cache: [Int: Track] = [:]
                        for track in details {
                            cache[track.id] = track
                        }
                        await MainActor.run {
                            songDetailsCache = cache
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "搜索失败，请重试"
                    isSearching = false
                }
            }
        }
    }
    
    // 获取歌曲封面（优先使用详情缓存）
    private func getCoverUrl(for song: SearchSong) -> String? {
        if let cached = songDetailsCache[song.id], let cover = cached.coverUrl {
            return cover
        }
        return song.coverUrl
    }
    
    // MARK: - 播放歌曲
    private func playSong(_ song: SearchSong) {
        let tracks = songResults.map { $0.toTrack() }
        if let index = songResults.firstIndex(where: { $0.id == song.id }) {
            AudioPlayer.shared.setPlaylist(tracks, startAt: index)
        }
        HapticFeedback.light()
    }
}

// MARK: - 搜索界面迷你播放器
struct SearchMiniPlayerBar: View {
    @Binding var showPlayer: Bool
    @StateObject private var audioPlayer = AudioPlayer.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // 封面
            if let coverUrl = audioPlayer.currentTrack?.coverUrl,
               let url = URL(string: coverUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 44, height: 44)
            }
            
            // 歌曲信息
            VStack(alignment: .leading, spacing: 2) {
                Text(audioPlayer.currentTrack?.name ?? "未播放")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(audioPlayer.currentTrack?.artistName ?? "")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 播放/暂停按钮
            Button {
                HapticFeedback.light()
                audioPlayer.togglePlayPause()
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
            }
            
            // 下一首按钮
            Button {
                HapticFeedback.light()
                audioPlayer.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            showPlayer = true
        }
    }
}

// MARK: - 最佳匹配艺人行
struct BestMatchArtistRow: View {
    let artist: SearchArtistResult
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationLink(destination: ArtistDetailView(artistId: artist.id, artistName: artist.name)) {
            HStack(spacing: 14) {
                // 艺人头像（圆形）
                if let avatarUrl = artist.avatarUrl, let url = URL(string: avatarUrl) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color(.systemGray5))
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                        )
                }
                
                // 艺人信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(artist.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("艺人")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 艺人结果行
struct ArtistResultRow: View {
    let artist: SearchArtistResult
    
    var body: some View {
        NavigationLink(destination: ArtistDetailView(artistId: artist.id, artistName: artist.name)) {
            HStack(spacing: 12) {
                // 头像
                if let avatarUrl = artist.avatarUrl, let url = URL(string: avatarUrl) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color(.systemGray5))
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.secondary)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(artist.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text("艺人")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        
                        if let albumSize = artist.albumSize, albumSize > 0 {
                            Text("\(albumSize)张专辑")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 专辑结果行
struct AlbumResultRow: View {
    let album: SearchAlbumResult
    
    var body: some View {
        NavigationLink(destination: AlbumDetailView(albumId: album.id, albumName: album.name)) {
            HStack(spacing: 12) {
                // 封面
                if let picUrl = album.picUrl, let url = URL(string: picUrl) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color(.systemGray5))
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "square.stack")
                                .foregroundColor(.secondary)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("专辑 · \(album.artistName)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 搜索历史行视图
struct SearchHistoryRowView: View {
    let entry: SearchHistoryEntry
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            Text(entry.keyword)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - 热搜行视图
struct HotSearchRow: View {
    let index: Int
    let item: HotSearch
    let onTap: () -> Void
    
    private var indexColor: Color {
        switch index {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        default: return .secondary
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 16, weight: index <= 3 ? .bold : .medium))
                .foregroundColor(indexColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.searchWord)
                        .font(.system(size: 16, weight: index <= 3 ? .semibold : .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    // 热搜标签
                    if let iconType = item.iconType {
                        hotSearchTag(iconType: iconType)
                    }
                }
                
                if let content = item.content, !content.isEmpty {
                    Text(content)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if let score = item.score {
                Text(formatScore(score))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticFeedback.light()
            onTap()
        }
    }
    
    @ViewBuilder
    private func hotSearchTag(iconType: Int) -> some View {
        let (text, color): (String, Color) = {
            switch iconType {
            case 1: return ("热", .red)
            case 2: return ("新", .blue)
            case 3: return ("飙", .orange)
            case 5: return ("荐", .purple)
            default: return ("", .clear)
            }
        }()
        
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(color)
                .cornerRadius(4)
        }
    }
    
    private func formatScore(_ score: Int) -> String {
        if score >= 10000 {
            return String(format: "%.1f万", Double(score) / 10000)
        }
        return "\(score)"
    }
}

// MARK: - 搜索结果行视图
struct SearchResultRow: View {
    let song: SearchSong
    var coverUrl: String?  // 可选的封面 URL（优先使用）
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    // 导航状态
    @State private var navigateToAlbum = false
    @State private var navigateToArtist = false
    
    private var displayCoverUrl: String? {
        coverUrl ?? song.coverUrl
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 封面
            if let coverUrl = displayCoverUrl, let url = URL(string: coverUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.secondary)
                    )
            }
            
            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                Text(song.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(song.artistName) - \(song.albumName)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 更多按钮
            Menu {
                Button {
                    AudioPlayer.shared.playNext(track: song.toTrack())
                    HapticFeedback.light()
                } label: {
                    Label("播放下一首", systemImage: "text.insert")
                }
                
                Button {
                    AudioPlayer.shared.addToQueue(track: song.toTrack())
                    HapticFeedback.light()
                } label: {
                    Label("添加到播放列表", systemImage: "text.append")
                }
                
                Divider()
                
                if song.albumId != nil {
                    Button {
                        navigateToAlbum = true
                    } label: {
                        Label("查看专辑", systemImage: "square.stack")
                    }
                }
                
                if song.artistId != nil {
                    Button {
                        navigateToArtist = true
                    } label: {
                        Label("查看艺人", systemImage: "person")
                    }
                }
                
                Divider()
                
                Button {
                    let shareText = "\(song.name) - \(song.artistName)"
                    let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootVC = window.rootViewController {
                        rootVC.present(activityVC, animated: true)
                    }
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .background(
            Group {
                if let albumId = song.albumId {
                    NavigationLink(destination: AlbumDetailView(albumId: albumId, albumName: song.albumName), isActive: $navigateToAlbum) {
                        EmptyView()
                    }
                    .hidden()
                }
                if let artistId = song.artistId {
                    NavigationLink(destination: ArtistDetailView(artistId: artistId, artistName: song.artistName), isActive: $navigateToArtist) {
                        EmptyView()
                    }
                    .hidden()
                }
            }
        )
    }
}

// MARK: - 搜索模式下的内容视图（分类浏览）
struct SearchContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    // 歌单分类数据（Apple Music 风格）
    private let playlistCategories: [SearchCategoryItem] = [
        SearchCategoryItem(title: "C-Pop", apiTag: "华语", gradientColors: [Color(red: 0.9, green: 0.5, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.7)]),
        SearchCategoryItem(title: "空间音频", apiTag: "流行", gradientColors: [Color(red: 0.8, green: 0.3, blue: 0.35), Color(red: 0.85, green: 0.35, blue: 0.4)]),
        SearchCategoryItem(title: "国语流行", apiTag: "国语", gradientColors: [Color(red: 0.9, green: 0.5, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.7)]),
        SearchCategoryItem(title: "DJ 混音精选", apiTag: "电子", gradientColors: [Color(red: 0.8, green: 0.3, blue: 0.35), Color(red: 0.85, green: 0.35, blue: 0.4)]),
        SearchCategoryItem(title: "月度音乐回忆", apiTag: "流行", gradientColors: [Color(red: 0.5, green: 0.75, blue: 0.9), Color(red: 0.6, green: 0.8, blue: 0.95)]),
        SearchCategoryItem(title: "排行榜", apiTag: "流行", gradientColors: [Color(red: 0.6, green: 0.65, blue: 0.4), Color(red: 0.65, green: 0.7, blue: 0.45)]),
        SearchCategoryItem(title: "爵士乐", apiTag: "爵士", gradientColors: [Color(red: 0.35, green: 0.55, blue: 0.65), Color(red: 0.45, green: 0.65, blue: 0.75)]),
        SearchCategoryItem(title: "创作与制作", apiTag: "流行", gradientColors: [Color(red: 0.6, green: 0.65, blue: 0.4), Color(red: 0.65, green: 0.7, blue: 0.45)]),
        SearchCategoryItem(title: "国际流行", apiTag: "欧美", gradientColors: [Color(red: 0.9, green: 0.5, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.7)]),
        SearchCategoryItem(title: "粤语流行", apiTag: "粤语", gradientColors: [Color(red: 0.9, green: 0.5, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.7)]),
        SearchCategoryItem(title: "嘻哈 / 说唱", apiTag: "说唱", gradientColors: [Color(red: 0.4, green: 0.5, blue: 0.75), Color(red: 0.5, green: 0.6, blue: 0.85)]),
        SearchCategoryItem(title: "古典音乐", apiTag: "古典", gradientColors: [Color(red: 0.6, green: 0.4, blue: 0.7), Color(red: 0.7, green: 0.5, blue: 0.8)])
    ]
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(playlistCategories) { category in
                    NavigationLink {
                        CategoryPlaylistListView(category: category.apiTag, title: category.title)
                    } label: {
                        SearchCategoryCard(category: category)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarHidden(true)
    }
}

// MARK: - 分类模型
struct SearchCategoryItem: Identifiable {
    let id = UUID()
    let title: String
    let apiTag: String
    let gradientColors: [Color]
}

// MARK: - 分类卡片
struct SearchCategoryCard: View {
    let category: SearchCategoryItem
    
    private var cardHeight: CGFloat {
        (UIScreen.main.bounds.width - 44) / 2 * 0.6
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: category.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Text(category.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(12)
        }
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    FullScreenSearchView(isSearchMode: .constant(true), previousTabIcon: "house.fill")
}
