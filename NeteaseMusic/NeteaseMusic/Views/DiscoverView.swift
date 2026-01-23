import SwiftUI

// MARK: - Apple Music 液态玻璃风格发现页
struct DiscoverView: View {
    @State private var playlists: [RecommendPlaylist] = []
    @State private var banners: [Banner] = []
    @State private var isLoading = true
    @State private var currentBannerIndex = 0
    @State private var errorMessage: String?
    @State private var selectedPlaylistId: Int?
    @State private var navigateToPlaylist = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showContent = false
    @State private var showQuickMenu = false
    @State private var recentlyPlayed: [Track] = []
    
    private let musicService = MusicService.shared
    private let storageService = LocalStorageService.shared
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            ZStack {
                VStack(spacing: 28) {
                    // Banner 轮播
                    if !banners.isEmpty {
                        liquidGlassBannerView
                            .padding(.top, 12)
                    }
                    
                    // 最近播放
                    recentlyPlayedSection
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                    
                    // 推荐歌单
                    liquidGlassPlaylistSection
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 30)
                }
            }
            .padding(.bottom, 120)
        }
        .background(LiquidGlassBackground())
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                QuickMenuButton(showMenu: $showQuickMenu)
            }
        }
        .overlay {
            if showQuickMenu {
                QuickAccessMenu(isPresented: $showQuickMenu)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .task {
            await loadData()
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
        }
        .refreshable {
            await loadData()
        }
    }
    
    // MARK: - 液态玻璃 Banner 视图
    private var liquidGlassBannerView: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(banners, id: \.targetId) { banner in
                        AppleMusicBannerCard(
                            title: banner.typeTitle ?? "",
                            subtitle: bannerSubtitle(for: banner.typeTitle ?? ""),
                            gradientColors: bannerGradient(for: banner.typeTitle ?? "")
                        ) {
                            handleBannerTap(banner)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .navigationDestination(isPresented: $navigateToPlaylist) {
                if let playlistId = selectedPlaylistId {
                    PlaylistDetailView(
                        playlistId: playlistId,
                        playlistName: "",
                        coverUrl: nil
                    )
                }
            }
        }
    }
    
    private func bannerSubtitle(for title: String) -> String {
        switch title {
        case "热歌榜": return "热门推荐\n最热门的歌曲"
        case "飙升榜": return "热度上升\n最近最火的歌曲"
        case "新歌榜": return "新歌首发\n最新的音乐作品"
        default: return "发现好音乐"
        }
    }
    
    private func bannerGradient(for title: String) -> [Color] {
        switch title {
        case "热歌榜": return [Color(red: 0.8, green: 0.4, blue: 0.2), Color(red: 0.95, green: 0.6, blue: 0.3)]
        case "飙升榜": return [Color(red: 0.4, green: 0.6, blue: 0.3), Color(red: 0.6, green: 0.8, blue: 0.5)]
        case "新歌榜": return [Color(red: 0.3, green: 0.5, blue: 0.7), Color(red: 0.5, green: 0.7, blue: 0.9)]
        default: return [Color.blue, Color.purple]
        }
    }
    
    // MARK: - 处理Banner点击
    private func handleBannerTap(_ banner: Banner) {
        guard let targetId = banner.targetId else { return }
        withAnimation(.spring(response: 0.3)) {
            selectedPlaylistId = targetId
            navigateToPlaylist = true
        }
    }
    
    // MARK: - 最近播放区域
    private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 标题
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("最近播放")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // 最近播放内容
            if recentlyPlayed.isEmpty {
                emptyRecentlyPlayedView
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(recentlyPlayed.prefix(10), id: \.id) { track in
                            Button(action: {
                                HapticFeedback.light()
                                Task {
                                    await AudioPlayer.shared.play(track: track)
                                }
                            }) {
                                RecentlyPlayedCard(
                                    imageUrl: track.coverUrl.flatMap { URL(string: $0) },
                                    title: track.name,
                                    artist: track.artistName
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
    
    // 空状态视图
    private var emptyRecentlyPlayedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("暂无播放历史")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - 液态玻璃推荐歌单区域
    private var liquidGlassPlaylistSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 标题
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("推荐歌单")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                LiquidGlassPillButton(title: "换一批", icon: "arrow.triangle.2.circlepath") {
                    Task {
                        do {
                            let randomOffset = Int.random(in: 0...200)
                            let newPlaylists = try await musicService.getHotPlaylist(cat: "全部", limit: 12, offset: randomOffset)
                            withAnimation(.spring(response: 0.4)) {
                                playlists = newPlaylists
                            }
                        } catch {
                            print("Refresh error: \(error)")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // 歌单内容 - 横向滚动
            if isLoading {
                liquidGlassLoadingView
            } else if let error = errorMessage {
                liquidGlassErrorView(error)
            } else if playlists.isEmpty {
                liquidGlassEmptyView
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                            NavigationLink(destination: PlaylistDetailView(
                                playlistId: playlist.id,
                                playlistName: playlist.name,
                                coverUrl: playlist.coverUrl
                            )) {
                                AppleMusicPlaylistCard(
                                    imageUrl: playlist.coverUrl.flatMap { URL(string: $0) },
                                    title: playlist.name,
                                    subtitle: playlist.playCountText
                                )
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                            .buttonStyle(LiquidGlassButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
    
    // MARK: - 液态玻璃加载视图
    private var liquidGlassLoadingView: some View {
        VStack(spacing: 20) {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(0..<6, id: \.self) { _ in
                    LiquidGlassSkeletonCard()
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - 液态玻璃错误视图
    private func liquidGlassErrorView(_ error: String) -> some View {
        LiquidGlassCard(cornerRadius: 24, padding: 32) {
            VStack(spacing: 20) {
                LiquidGlassIconButton(icon: "wifi.exclamationmark", color: .gray, size: 80, iconSize: 36) {}
                    .disabled(true)
                
                VStack(spacing: 8) {
                    Text("网络出了点问题")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Button(action: {
                    Task { await loadData() }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                        Text("重新加载")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.pink, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .shadow(color: .pink.opacity(0.3), radius: 15, x: 0, y: 8)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 液态玻璃空视图
    private var liquidGlassEmptyView: some View {
        LiquidGlassCard(cornerRadius: 24, padding: 32) {
            VStack(spacing: 16) {
                LiquidGlassIconButton(icon: "music.note.list", color: .gray, size: 80, iconSize: 32) {}
                    .disabled(true)
                
                Text("暂无推荐歌单")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 静态 Banner 数据
    private var staticBanners: [Banner] {
        [
            Banner(
                pic: nil,
                imageUrl: nil,
                targetId: 3778678,
                targetType: 1000,
                titleColor: nil,
                typeTitle: "热歌榜",
                url: nil
            ),
            Banner(
                pic: nil,
                imageUrl: nil,
                targetId: 19723756,
                targetType: 1000,
                titleColor: nil,
                typeTitle: "飙升榜",
                url: nil
            ),
            Banner(
                pic: nil,
                imageUrl: nil,
                targetId: 3779629,
                targetType: 1000,
                titleColor: nil,
                typeTitle: "新歌榜",
                url: nil
            )
        ]
    }
    
    // MARK: - 加载数据
    private func loadData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            playlists = try await musicService.getPersonalized(limit: 12)
            banners = staticBanners
            
            // 加载播放历史
            await MainActor.run {
                recentlyPlayed = storageService.getHistory()
            }
            
            print("Loaded \(playlists.count) playlists, \(banners.count) banners, \(recentlyPlayed.count) history")
        } catch {
            print("Load error: \(error)")
            errorMessage = "\(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// MARK: - 液态玻璃每日推荐按钮
struct LiquidGlassDailyButton: View {
    @State private var showLoginAlert = false
    @Environment(\.colorScheme) var colorScheme
    
    private var dayOfMonth: String {
        let day = Calendar.current.component(.day, from: Date())
        return "\(day)"
    }
    
    var body: some View {
        Button(action: {
            showLoginAlert = true
        }) {
            VStack(spacing: 10) {
                ZStack {
                    // 液态玻璃背景
                    Circle()
                        .fill(.ultraThinMaterial)
                    
                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white.opacity(0.85))
                    
                    // 红色光晕
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.red.opacity(0.25), Color.red.opacity(0.05), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 35
                            )
                        )
                    
                    // 高光边框
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [.white.opacity(0.5), .white.opacity(0.15), .clear]
                                    : [.white.opacity(0.9), .white.opacity(0.3), Color.red.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                    
                    VStack(spacing: 2) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red.opacity(0.8))
                        
                        Text(dayOfMonth)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
                .frame(width: 64, height: 64)
                .shadow(color: Color.red.opacity(0.25), radius: 12, x: 0, y: 6)
                
                Text("每日推荐")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(LiquidGlassButtonStyle())
        .alert("需要登录", isPresented: $showLoginAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("每日推荐功能需要登录账号后使用")
        }
    }
}

// MARK: - 液态玻璃私人FM按钮
struct LiquidGlassFMButton: View {
    @State private var showLoginAlert = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: {
            showLoginAlert = true
        }) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                    
                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white.opacity(0.85))
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.green.opacity(0.25), Color.green.opacity(0.05), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 35
                            )
                        )
                    
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [.white.opacity(0.5), .white.opacity(0.15), .clear]
                                    : [.white.opacity(0.9), .white.opacity(0.3), Color.green.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                    
                    Image(systemName: "radio")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.green)
                }
                .frame(width: 64, height: 64)
                .shadow(color: Color.green.opacity(0.25), radius: 12, x: 0, y: 6)
                
                Text("私人FM")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(LiquidGlassButtonStyle())
        .alert("需要登录", isPresented: $showLoginAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("私人FM功能需要登录账号后使用")
        }
    }
}

// MARK: - 液态玻璃骨架屏卡片
struct LiquidGlassSkeletonCard: View {
    @State private var isAnimating = false
    @Environment(\.colorScheme) var colorScheme
    
    private var imageSize: CGFloat {
        (UIScreen.main.bounds.width - 56) / 2
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 封面骨架
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .frame(width: imageSize, height: imageSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isAnimating ? 0.1 : 0.2),
                                    Color.white.opacity(isAnimating ? 0.2 : 0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [.white.opacity(0.3), .white.opacity(0.1), .clear]
                                    : [.white.opacity(0.6), .white.opacity(0.2), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            
            // 标题骨架
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(isAnimating ? 0.15 : 0.25))
                    .frame(height: 14)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(isAnimating ? 0.1 : 0.2))
                    .frame(width: imageSize * 0.6, height: 14)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Apple Music 风格 Banner 卡片
struct AppleMusicBannerCard: View {
    let title: String
    let subtitle: String
    let gradientColors: [Color]
    let action: () -> Void
    
    private var cardWidth: CGFloat {
        UIScreen.main.bounds.width * 0.75
    }
    
    private var cardHeight: CGFloat {
        cardWidth * 0.6
    }
    
    var body: some View {
        Button(action: {
            HapticFeedback.light()
            action()
        }) {
            ZStack(alignment: .topTrailing) {
                // 渐变背景
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Youmi Music 标志
                HStack(spacing: 4) {
                    Image(systemName: "cat.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Youmi Music")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.top, 12)
                .padding(.trailing, 16)
                
                // 标题和副标题
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(width: cardWidth, height: cardHeight)
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 最近播放卡片
struct RecentlyPlayedCard: View {
    let imageUrl: URL?
    let title: String
    let artist: String
    @Environment(\.colorScheme) var colorScheme
    
    private var cardWidth: CGFloat {
        UIScreen.main.bounds.width * 0.38
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
                // 封面
                if let url = imageUrl {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        coverPlaceholder
                            .overlay {
                                ProgressView()
                                    .tint(.secondary)
                            }
                    }
                    .frame(width: cardWidth, height: cardWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    coverPlaceholder
                        .frame(width: cardWidth, height: cardWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // 歌曲名
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                    .frame(width: cardWidth, alignment: .leading)
                
            // 艺术家
            Text(artist)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: cardWidth, alignment: .leading)
        }
    }
    
    private var coverPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
            
            Image(systemName: "music.note")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
}

// MARK: - Apple Music 风格歌单卡片
struct AppleMusicPlaylistCard: View {
    let imageUrl: URL?
    let title: String
    let subtitle: String
    @Environment(\.colorScheme) var colorScheme
    
    private var cardWidth: CGFloat {
        UIScreen.main.bounds.width * 0.38
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面
            if let url = imageUrl {
                CachedAsyncImage(url: url, targetSize: CGSize(width: cardWidth, height: cardWidth)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    coverPlaceholder
                        .overlay {
                            ProgressView()
                                .tint(.secondary)
                        }
                }
                .frame(width: cardWidth, height: cardWidth)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                coverPlaceholder
                    .frame(width: cardWidth, height: cardWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // 标题
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(width: cardWidth, alignment: .leading)
            
            // 副标题
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                    .frame(width: cardWidth, alignment: .leading)
            }
        }
    }
    
    private var coverPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
            
            Image(systemName: "music.note")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
}

// MARK: - 快捷菜单按钮
struct QuickMenuButton: View {
    @Binding var showMenu: Bool
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {}) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.primary)
                .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    HapticFeedback.medium()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showMenu = true
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - 快捷菜单弹窗
struct QuickAccessMenu: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isPresented = false
                    }
                }
            
            // 菜单卡片
            VStack(spacing: 0) {
                // 标题
                HStack {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("快捷入口")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
                
                Divider()
                
                // 快捷选项
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    QuickMenuItem(
                        icon: "calendar",
                        title: "每日推荐",
                        color: .red,
                        action: {
                            isPresented = false
                            // TODO: Navigate to daily recommendations
                        }
                    )
                    
                    NavigationLink(destination: ToplistView()) {
                        QuickMenuItemLabel(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "排行榜",
                            color: .purple
                        )
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        isPresented = false
                    })
                    
                    QuickMenuItem(
                        icon: "radio",
                        title: "私人FM",
                        color: .green,
                        action: {
                            isPresented = false
                            // TODO: Navigate to personal FM
                        }
                    )
                }
                .padding(20)
            }
            .frame(width: UIScreen.main.bounds.width * 0.85)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(colorScheme == .dark ? Color(.systemGray6) : .white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(.systemGray5).opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
    }
}

// MARK: - 快捷菜单项
struct QuickMenuItem: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: {
            HapticFeedback.light()
            action()
        }) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(colorScheme == .dark ? 0.2 : 0.15))
                    
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(color)
                }
                .frame(width: 64, height: 64)
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 快捷菜单项标签（用于 NavigationLink）
struct QuickMenuItemLabel: View {
    let icon: String
    let title: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(colorScheme == .dark ? 0.2 : 0.15))
                
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(color)
            }
            .frame(width: 64, height: 64)
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    NavigationView {
        DiscoverView()
    }
}
