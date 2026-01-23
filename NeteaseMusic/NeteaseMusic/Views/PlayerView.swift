import SwiftUI
import AVKit
import AVFoundation
import WebKit
import MediaPlayer

// MARK: - MPVolumeView 扩展（设置系统音量）
extension MPVolumeView {
    static func setVolume(_ volume: Float) {
        let volumeView = MPVolumeView()
        let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            slider?.value = volume
        }
    }
}

// MARK: - HLS 变体数据结构
struct HLSVariant {
    let bandwidth: Int
    let width: Int
    let height: Int
    let url: String

    var pixelCount: Int { width * height }
    var megabitsPerSecond: Int { bandwidth / 1_000_000 }

    var description: String {
        "\(width)x\(height)@\(megabitsPerSecond)Mbps"
    }
}


// MARK: - HLS 变体缓存管理器（门面模式：委托给 DynamicCoverCache）
class HLSVariantCache {
    static let shared = HLSVariantCache()

    private init() {}

    // MARK: - Public API（保持原有接口不变）

    func getVariant(for masterUrl: String) -> String? {
        return DynamicCoverCache.shared.getVariantUrl(for: masterUrl)
    }

    func setVariant(_ variantUrl: String, for masterUrl: String) {
        DynamicCoverCache.shared.cacheVariantUrl(variantUrl, for: masterUrl)
    }

    /// 预加载：获取并解析m3u8，缓存最佳变体URL
    func preload(masterUrl: String) {
        DynamicCoverCache.shared.preloadVariant(masterUrl: masterUrl)
    }

    func clear() {
        // 注意：这只会清除变体缓存，不影响其他缓存
        // DynamicCoverCache 没有单独清除变体的方法，这里保持兼容性
        #if DEBUG
        print(" HLSVariantCache.clear() 调用（委托给 DynamicCoverCache）")
        #endif
    }
}

struct PlayerView: View {
    // 支持两种关闭方式：外部传入的回调 或 Environment dismiss
    var dismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var environmentDismiss
    @StateObject private var audioPlayer = AudioPlayer.shared
    @State private var lyrics: [LyricLineWithTranslation] = []
    @State private var currentLyricIndex: Int = 0
    @State private var showLyrics = false
    @State private var isLoadingLyrics = false
    @State private var showTranslation = true  // 是否显示翻译
    @State private var hasTranslation = false  // 是否有翻译歌词

    // 逐字歌词
    @State private var yrcLines: [YrcLine] = []
    @State private var hasYrcLyric = false     // 是否有逐字歌词
    @State private var currentTime: Double = 0 // 当前播放时间（用于驱动逐字动画）

    // 歌词滚动防抖优化
    @State private var lastLyricUpdateTime: Double = 0
    @State private var lastLyricIndex: Int = -1  // 记录上次歌词索引，避免重复设置

    // 动画状态
    @State private var isPlayButtonPressed = false
    @State private var isDraggingProgress = false
    @State private var dragProgress: Double = 0
    @State private var imageOffset: CGSize = .zero
    @State private var backgroundScale: CGFloat = 1.1

    // UI状态
    @State private var showShareSheet = false
    @State private var showPlaylistSheet = false
    @State private var showCommentSheet = false  // 评论弹窗
    @State private var showLikeSheet = false     // 喜欢选项弹窗
    @State private var currentVolume: Float = AVAudioSession.sharedInstance().outputVolume

    // 动态封面 - 使用 @State 触发视图更新
    @State private var dynamicCoverPlayer: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?
    @State private var isDynamicCoverReady = false
    @State private var lastLoadedTrackId: Int? = nil
    @State private var dynamicCoverURL: URL? = nil  // 改为 @State，触发视图更新

    private let musicService = MusicService.shared
    
    // 当前歌词文本
    private var currentLyricText: String {
        guard !lyrics.isEmpty, currentLyricIndex < lyrics.count else {
            return isLoadingLyrics ? "歌词加载中..." : ""
        }
        return lyrics[currentLyricIndex].text
    }
    
    // 当前歌词翻译
    private var currentLyricTranslation: String? {
        guard showTranslation, !lyrics.isEmpty, currentLyricIndex < lyrics.count else {
            return nil
        }
        return lyrics[currentLyricIndex].translation
    }
    
    // 当前逐字歌词行
    private var currentYrcLine: YrcLine? {
        guard !yrcLines.isEmpty, currentLyricIndex < yrcLines.count else {
            return nil
        }
        return yrcLines[currentLyricIndex]
    }
    
    // 统一的关闭方法
    private func dismissPlayer() {
        if let dismiss = dismiss {
            dismiss()
        } else {
            environmentDismiss()
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 层级 1: 全屏封面（从顶部开始铺满）
                fullScreenArtwork(size: geo.size)
                    .blur(radius: showLyrics ? 30 : 0)
                    .animation(.easeInOut(duration: 0.3), value: showLyrics)

                // 歌词模式下的暗色蒙版
                if showLyrics {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                // 层级 2: 底部渐变遮罩（只在下半部分）
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.4), location: 0.2),
                            .init(color: .black.opacity(0.85), location: 0.6),
                            .init(color: .black.opacity(0.95), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.55)
                }
                .ignoresSafeArea()

                // 层级 3: 内容
                VStack(spacing: 0) {
                    // 顶部栏
                    topBar

                    Spacer()

                    // 歌词视图（覆盖在封面上）
                    if showLyrics {
                        lyricsView
                        Spacer()
                    }

                    // 底部控制区（带模糊背景）
                    bottomControlsWithBlur(size: geo.size)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            loadLyrics()
            loadDynamicCover()
            startBackgroundAnimation()
            audioPlayer.onTimeUpdate = { [self] time in
                if showLyrics || hasYrcLyric {
                    currentTime = time
                }
                updateCurrentLyricIndex(time: time)
            }
        }
        .onChange(of: audioPlayer.currentTrack?.id) { _, _ in
            loadLyrics()
            loadDynamicCover()
        }
        .onDisappear {
            // 不清理动态封面，让它保持播放
            audioPlayer.onTimeUpdate = nil
            // 注意：不在 onDisappear 中停止 Live Activity
            // 因为用户可能只是关闭了播放器界面，但音乐仍在后台播放
            // Live Activity 会在歌曲停止播放时由 AudioPlayer 管理
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 || value.translation.width > 0 {
                        imageOffset = value.translation
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 || value.translation.width > 80 {
                        dismissPlayer()
                    } else {
                        withAnimation(.spring(response: 0.3)) {
                            imageOffset = .zero
                        }
                    }
                }
        )
    }
    
    // MARK: - 全屏封面（上部清晰 + 底部模糊无缝衔接）
    private func fullScreenArtwork(size: CGSize) -> some View {
        GeometryReader { geo in
            let screenWidth = geo.size.width
            let screenHeight = geo.size.height
            let isLocal = audioPlayer.isPlayingLocal
            let localTrack = audioPlayer.currentLocalTrack

            ZStack(alignment: .top) {
                // 背景色
                Color.black

                // 本地歌曲封面
                if isLocal, let track = localTrack {
                    if let artworkImage = track.artworkImage {
                        localArtworkWithBlur(image: artworkImage, screenWidth: screenWidth, screenHeight: screenHeight)
                    } else {
                        gradientBackground
                    }
                }
                // 网络歌曲封面
                else if let coverUrl = audioPlayer.currentTrack?.coverUrl,
                   let url = URL(string: coverUrl) {
                    staticCoverWithBlur(url: url, screenWidth: screenWidth, screenHeight: screenHeight)
                } else {
                    gradientBackground
                }

                // 动态封面叠加在静态封面上（无缝过渡）- 仅网络歌曲
                if !isLocal, let coverUrl = dynamicCoverURL {
                    dynamicCoverWithBlur(url: coverUrl, screenWidth: screenWidth, screenHeight: screenHeight)
                        .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - 本地歌曲封面（使用 UIImage）
    private func localArtworkWithBlur(image: UIImage, screenWidth: CGFloat, screenHeight: CGFloat) -> some View {
        let imageHeight = screenHeight * 0.70
        
        return ZStack(alignment: .top) {
            // 层级 1: 全屏模糊背景
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: screenWidth, height: screenHeight)
                .blur(radius: 50)
                .clipped()
            
            // 层级 2: 暗色渐变蒙版
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.3), location: 0.5),
                    .init(color: .black.opacity(0.7), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // 层级 3: 清晰封面
            VStack(spacing: 0) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: screenWidth, height: imageHeight)
                    .clipped()
                Spacer(minLength: 0)
            }
            .frame(height: screenHeight)
            .mask(
                VStack(spacing: 0) {
                    // 封面区域完全不透明
                    Rectangle()
                        .fill(Color.white)
                        .frame(height: imageHeight * 0.95)
                    // 底部渐变透明
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: imageHeight * 0.05)
                    Spacer(minLength: 0)
                }
            )
        }
    }
    
    // MARK: - 静态封面（清晰+模糊无缝衔接）
    private func staticCoverWithBlur(url: URL, screenWidth: CGFloat, screenHeight: CGFloat) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                // 覆盖约 70% 屏幕高度（匹配 Apple Music）
                let imageHeight = screenHeight * 0.70
                
                ZStack(alignment: .top) {
                    // 层级 1: 全屏模糊背景
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: screenWidth, height: screenHeight)
                        .blur(radius: 50)
                        .clipped()
                    
                    // 层级 2: 暗色渐变蒙版
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.3), location: 0.5),
                            .init(color: .black.opacity(0.7), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    // 层级 3: 清晰封面
                    VStack(spacing: 0) {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: screenWidth, height: imageHeight)
                            .clipped()
                        Spacer(minLength: 0)
                    }
                    .frame(height: screenHeight)
                    .mask(
                        VStack(spacing: 0) {
                            // 封面区域完全不透明
                            Rectangle()
                                .fill(Color.white)
                                .frame(height: imageHeight * 0.95)
                            // 底部渐变透明
                            LinearGradient(
                                colors: [.white, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: imageHeight * 0.05)
                            Spacer(minLength: 0)
                        }
                    )
                }
            default:
                gradientBackground
            }
        }
    }
    
    // MARK: - 动态封面（性能优化：模糊背景用静态图片，只保留一个WebView）
    private func dynamicCoverWithBlur(url: URL, screenWidth: CGFloat, screenHeight: CGFloat) -> some View {
        // 覆盖约 70% 屏幕高度（匹配 Apple Music）
        let videoHeight = screenHeight * 0.70
        
        return ZStack(alignment: .top) {
            // 性能优化：模糊背景使用静态封面图片，避免创建第二个WebView
            if let coverUrl = audioPlayer.currentTrack?.coverUrl,
               let staticUrl = URL(string: coverUrl) {
                AsyncImage(url: staticUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: screenWidth, height: screenHeight)
                            .blur(radius: 50)
                            .scaleEffect(1.2)
                            .clipped()
                    default:
                        Color.black
                    }
                }
            } else {
                Color.black
            }
            
            // 层级 2: 暗色渐变蒙版
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.3), location: 0.5),
                    .init(color: .black.opacity(0.7), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // 层级 3: 清晰动态封面（唯一的WebView）
            VStack(spacing: 0) {
                DynamicCoverVideoView(url: url)
                    .id(url)  // 切歌时强制重新创建 WebView
                    .frame(width: screenWidth, height: videoHeight)
                    .clipped()
                Spacer(minLength: 0)
            }
            .frame(height: screenHeight)
            .mask(
                VStack(spacing: 0) {
                    // 封面区域完全不透明
                    Rectangle()
                        .fill(Color.white)
                        .frame(height: videoHeight * 0.95)
                    // 底部渐变透明
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: videoHeight * 0.05)
                    Spacer(minLength: 0)
                }
            )
        }
    }
    
    // MARK: - 底部控制区（带模糊背景）
    private func bottomControlsWithBlur(size: CGSize) -> some View {
        VStack(spacing: 16) {
            // 当前歌词预览（非歌词模式时显示）
            if !showLyrics {
                if hasYrcLyric, let currentLine = currentYrcLine {
                    // 逐字变色预览
                    KaraokePreviewView(line: currentLine, currentTime: currentTime)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: currentLyricIndex)
                } else if !currentLyricText.isEmpty {
                    // 普通歌词预览
                    Text(currentLyricText)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                        .padding(.horizontal, 40)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: currentLyricIndex)
                }
            }
            
            // 歌曲信息
            PlayerSongInfoView(
                track: audioPlayer.currentTrack,
                onShowLike: { showLikeSheet = true },
                onShowShare: { showShareSheet = true }
            )
            
            // 进度条
            PlayerProgressView(
                currentTime: audioPlayer.currentTime,
                duration: audioPlayer.duration,
                isDragging: $isDraggingProgress,
                dragProgress: $dragProgress,
                onSeek: { time in audioPlayer.seek(to: time) }
            )
            
            // 控制按钮
            PlayerControlsView(
                isPlaying: audioPlayer.isPlaying,
                isLoading: audioPlayer.isLoading,
                isPlayButtonPressed: $isPlayButtonPressed,
                onPrevious: { audioPlayer.playPrevious() },
                onPlayPause: { audioPlayer.togglePlayPause() },
                onNext: { audioPlayer.playNext() }
            )
            
            // 音量条
            PlayerVolumeView(currentVolume: $currentVolume)
            
            // 底部操作栏
            PlayerBottomBarView(
                showLyrics: showLyrics,
                playModeIcon: audioPlayer.playMode.icon,
                sourceConfig: MusicSourceConfig.shared,
                audioPlayer: audioPlayer,
                onToggleLyrics: {
                    withAnimation(.spring(response: 0.4)) {
                        showLyrics.toggle()
                    }
                },
                onShowComments: { showCommentSheet = true },
                onShowPlaylist: { showPlaylistSheet = true },
                onTogglePlayMode: { audioPlayer.togglePlayMode() }
            )
        }
        .padding(.bottom, 50)
        .offset(y: imageOffset.height * 0.2)
        .sheet(isPresented: $showPlaylistSheet) {
            PlaylistSheetView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShareSheet) {
            if let track = audioPlayer.currentTrack {
                ShareSheetView(track: track)
            }
        }
        .sheet(isPresented: $showCommentSheet) {
            if let track = audioPlayer.currentTrack {
                CommentView(trackId: track.id, trackName: track.name)
            }
        }
        .sheet(isPresented: $showLikeSheet) {
            if let track = audioPlayer.currentTrack {
                LikeOptionsSheet(track: track)
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
            }
        }
    }
    
    private var gradientBackground: some View {
        LinearGradient(
            colors: [Color.indigo, Color.purple, Color.black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - 背景动画
    private func startBackgroundAnimation() {
        withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) {
            backgroundScale = 1.2
        }
    }
    
    // MARK: - 顶部栏
    private var topBar: some View {
        HStack {
            Button(action: { dismissPlayer() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 54)
        .offset(y: imageOffset.height * 0.3)
    }
    
    // MARK: - 歌词视图
    @ViewBuilder
    private var lyricsView: some View {
        if hasYrcLyric {
            // 逐字变色歌词视图
            KaraokeLyricsView(
                lines: yrcLines,
                currentTime: currentTime,
                showTranslation: showTranslation,
                hasTranslation: hasTranslation,
                onToggleTranslation: {
                    withAnimation(.spring(response: 0.3)) {
                        showTranslation.toggle()
                    }
                },
                onSeek: { time in
                    audioPlayer.seek(to: time)
                }
            )
            .offset(y: imageOffset.height * 0.3)
        } else {
            // 普通歌词视图
            normalLyricsView
        }
    }
    
    // MARK: - 普通歌词视图
    private var normalLyricsView: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // 翻译开关（只在有翻译时显示）
                if hasTranslation {
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showTranslation.toggle()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "globe")
                                    .font(.system(size: 12))
                                Text(showTranslation ? "翻译" : "原文")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(showTranslation ? .white : .white.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(showTranslation ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                            )
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 60)
                    }
                }
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 24) {
                        ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
                            let isCurrent = index == currentLyricIndex
                            let distance = abs(index - currentLyricIndex)
                            
                            VStack(spacing: 8) {
                                // 原文歌词
                                Text(line.text)
                                    .font(.system(size: isCurrent ? 26 : 20, weight: isCurrent ? .bold : .medium))
                                    .foregroundColor(isCurrent ? .white : .white.opacity(distance <= 1 ? 0.5 : 0.3))
                                    .multilineTextAlignment(.center)
                                    .shadow(color: isCurrent ? .black.opacity(0.3) : .clear, radius: 8, x: 0, y: 2)
                                    .blur(radius: distance > 4 ? 1.5 : 0)
                                
                                // 翻译歌词
                                if showTranslation, let translation = line.translation {
                                    Text(translation)
                                        .font(.system(size: isCurrent ? 16 : 14, weight: .regular))
                                        .foregroundColor(isCurrent ? .white.opacity(0.8) : .white.opacity(distance <= 1 ? 0.4 : 0.2))
                                        .multilineTextAlignment(.center)
                                        .blur(radius: distance > 4 ? 1.5 : 0)
                                }
                            }
                            .scaleEffect(isCurrent ? 1.03 : 1.0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentLyricIndex)
                            .id(index)
                            .padding(.horizontal, 8)
                            .onTapGesture {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                audioPlayer.seek(to: line.time)
                            }
                        }
                    }
                    .padding(.vertical, hasTranslation ? 120 : 180)
                    .padding(.horizontal, 24)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.12),
                            .init(color: .white, location: 0.88),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChange(of: currentLyricIndex) { oldIndex, newIndex in
                    // 性能优化：只有索引真正改变时才滚动
                    guard oldIndex != newIndex else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .offset(y: imageOffset.height * 0.3)
    }
    
    // MARK: - 加载歌词（优先加载逐字歌词）
    private func loadLyrics() {
        guard let _ = audioPlayer.currentTrack?.id else { return }
        
        lyrics = []
        yrcLines = []
        isLoadingLyrics = true
        hasTranslation = false
        hasYrcLyric = false
        
        // 检查是否是本地歌曲
        let isLocal = audioPlayer.isPlayingLocal
        let localTrack = audioPlayer.currentLocalTrack
        
        if isLocal, let track = localTrack {
            // 使用本地内嵌歌词
            loadLocalLyrics(from: track)
            return
        }
        
        // 网络歌曲：从 API 获取歌词
        guard let trackId = audioPlayer.currentTrack?.id else {
            isLoadingLyrics = false
            return
        }
        
        Task {
            do {
                // 优先尝试获取逐字歌词
                let result = try await musicService.getYrcLyric(id: trackId)
                
                await MainActor.run {
                    // 如果有逐字歌词，解析YRC格式
                    if let yrcString = result.yrc, !yrcString.isEmpty {
                        yrcLines = YrcLine.parse(yrcString: yrcString, translation: result.translation)
                        hasYrcLyric = !yrcLines.isEmpty
                        hasTranslation = yrcLines.contains { $0.translation != nil }
                        print(" 加载逐字歌词成功: \(yrcLines.count) 行")
                    }
                    
                    // 同时解析普通歌词作为fallback
                    if !result.lyric.isEmpty {
                        lyrics = LyricLineWithTranslation.parse(lyric: result.lyric, translation: result.translation)
                        if !hasYrcLyric {
                            hasTranslation = lyrics.contains { $0.translation != nil }
                        }
                    }
                    
                    currentLyricIndex = 0
                    isLoadingLyrics = false
                }
            } catch {
                print("Load lyric error: \(error)")
                await MainActor.run {
                    isLoadingLyrics = false
                }
            }
        }
    }
    
    /// 加载本地歌曲的内嵌歌词
    private func loadLocalLyrics(from localTrack: LocalTrack) {
        guard let embeddedLyrics = localTrack.embeddedLyrics, !embeddedLyrics.isEmpty else {
            // 没有内嵌歌词
            lyrics = []
            isLoadingLyrics = false
            #if DEBUG
            print(" 本地歌曲无内嵌歌词: \(localTrack.displayTitle)")
            #endif
            return
        }
        
        // 解析本地歌词（支持 LRC 格式）
        let parsedLines = LyricLine.parse(embeddedLyrics)
        
        if parsedLines.isEmpty {
            // 无时间戳歌词，将整段文本作为单行歌词显示
            lyrics = [LyricLineWithTranslation(time: 0, text: embeddedLyrics, translation: nil)]
        } else {
            // 转换为 LyricLineWithTranslation
            lyrics = parsedLines.map { line in
                LyricLineWithTranslation(time: line.time, text: line.text, translation: nil)
            }
        }
        
        hasTranslation = false
        hasYrcLyric = false
        currentLyricIndex = 0
        isLoadingLyrics = false
        
        #if DEBUG
        print("✅ 加载本地歌词成功: \(lyrics.count) 行")
        #endif
    }
    
    // MARK: - 加载动态封面（优先使用预加载缓存，避免重复加载）
    private func loadDynamicCover() {
        guard let track = audioPlayer.currentTrack else { return }

        // 如果 AudioPlayer 已有该歌曲的动态封面缓存，直接标记为已加载并返回
        // dynamicCoverURL 计算属性会自动从缓存获取 URL，无需再次设置
        // 检查 AudioPlayer 缓存
        if let cachedUrlString = audioPlayer.getDynamicCoverURL(for: track.id),
           let cachedUrl = URL(string: cachedUrlString) {
            if lastLoadedTrackId != track.id {
                lastLoadedTrackId = track.id
                dynamicCoverURL = cachedUrl  // 设置 URL 触发视图更新
                #if DEBUG
                print(" 使用已缓存的动态封面: \(track.name)")
                #endif
            }
            return
        }

        // 清理旧的播放器
        dynamicCoverPlayer?.pause()
        dynamicCoverPlayer = nil
        playerLooper = nil
        isDynamicCoverReady = false
        dynamicCoverURL = nil  // 清除旧的 URL

        // 没有缓存则异步加载
        let trackId = track.id
        let trackName = track.name
        let artistName = track.artistName

        Task {
            await searchAppleMusicAnimatedArtwork(
                trackId: trackId,
                songName: trackName,
                artistName: artistName
            )
        }
    }

    // MARK: - 搜索 Apple Music 动态封面
    private func searchAppleMusicAnimatedArtwork(trackId: Int, songName: String, artistName: String) async {
        do {
            // 调用 Apple Music API 获取动态封面
            if let videoUrlString = try await musicService.getAppleMusicAnimatedCover(
                songName: songName,
                artistName: artistName
            ),
               let videoUrl = URL(string: videoUrlString) {
                // 缓存到 AudioPlayer
                audioPlayer.cacheDynamicCoverURL(videoUrlString, for: trackId)

                await MainActor.run {
                    lastLoadedTrackId = trackId
                    dynamicCoverURL = videoUrl  // 设置 URL 触发视图更新
                    setupDynamicCoverPlayer(url: videoUrl)
                }
                #if DEBUG
                print("Found animated cover: \(videoUrlString)")
                #endif
            } else {
                #if DEBUG
                print("No animated cover found for: \(songName) - \(artistName)")
                #endif
                await MainActor.run {
                    lastLoadedTrackId = trackId
                }
            }
        } catch {
            #if DEBUG
            print("Apple Music animated cover error: \(error)")
            #endif
        }
    }
    
    // MARK: - 设置动态封面播放器（直接使用 WKWebView，避免 AVPlayer 在 SwiftUI 中的 XPC 问题）
    private func setupDynamicCoverPlayer(url: URL) {
        print(" Setting up dynamic cover with WKWebView: \(url)")

        // 立即开始预加载（后台解析m3u8并缓存变体URL）
        HLSVariantCache.shared.preload(masterUrl: url.absoluteString)

        // 缓存到 AudioPlayer（如果还没缓存）
        if let trackId = audioPlayer.currentTrack?.id {
            audioPlayer.cacheDynamicCoverURL(url.absoluteString, for: trackId)
        }

        // 直接使用 WKWebView（跳过 AVPlayer，避免 FigPlayerError_ParamErr）
        self.dynamicCoverPlayer = nil
        self.playerLooper = nil
    }
    
    // MARK: - 更新当前歌词索引（性能优化版）
    private func updateCurrentLyricIndex(time: Double) {
        // 性能优化：根据歌词类型使用不同的防抖策略
        if hasYrcLyric {
            // 逐字歌词需要高频更新，但依然添加轻微防抖
            guard abs(time - lastLyricUpdateTime) > 0.05 else { return }
            lastLyricUpdateTime = time
            
            // 优化：先检查当前索引是否仍然有效，避免不必要的遍历
            if currentLyricIndex < yrcLines.count - 1 {
                let currentLine = yrcLines[currentLyricIndex]
                let nextLine = yrcLines[currentLyricIndex + 1]
                if time >= currentLine.startTime && time < nextLine.startTime {
                    return  // 当前索引仍然有效
                }
            }
            
            // 逐字歌词索引更新
            for (index, line) in yrcLines.enumerated().reversed() {
                if time >= line.startTime {
                    if currentLyricIndex != index {
                        currentLyricIndex = index
                    }
                    break
                }
            }
        } else {
            // 普通歌词模式下大幅降低更新频率（0.3秒）
            guard abs(time - lastLyricUpdateTime) > 0.3 else { return }
            lastLyricUpdateTime = time
            
            // 优化：先检查当前索引是否仍然有效
            if currentLyricIndex < lyrics.count - 1 {
                let currentLine = lyrics[currentLyricIndex]
                let nextLine = lyrics[currentLyricIndex + 1]
                if time >= currentLine.time && time < nextLine.time {
                    return  // 当前索引仍然有效
                }
            }
            
            // 普通歌词索引更新
            for (index, line) in lyrics.enumerated().reversed() {
                if time >= line.time {
                    if currentLyricIndex != index {
                        currentLyricIndex = index
                    }
                    break
                }
            }
        }
    }
    
    // MARK: - 格式化时间
    private func formatTime(_ time: Double) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - WKWebView 缓存池（性能优化：按 URL 缓存正在播放的 WebView）
final class WebViewPool {
    static let shared = WebViewPool()

    // 预热专用 WebView（永久持有，防止 WebContent 进程退出）
    private var keepAliveWebView: WKWebView?
    // 预热的空闲 WebView
    private var idlePool: [WKWebView] = []
    // 按 URL 缓存正在使用的 WebView（避免重复加载）
    private var activeWebViews: [String: WKWebView] = [:]
    private let maxIdlePoolSize = 1
    private let queue = DispatchQueue(label: "webViewPool")
    private var isWarmedUp = false

    private init() {
        // 监听内存警告
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    /// 预热 WebView（同步创建，确保 WebContent 进程尽早启动）
    func warmUp() {
        guard !isWarmedUp else { return }
        isWarmedUp = true

        // 必须在主线程创建 WKWebView
        if Thread.isMainThread {
            createWarmupWebView()
        } else {
            DispatchQueue.main.sync {
                createWarmupWebView()
            }
        }
    }

    private func createWarmupWebView() {
        let config = createWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: -1, y: -1, width: 1, height: 1), configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false

        // 加载一个简单的视频页面来预热 GPU 进程
        let html = """
        <html>
        <head><style>body{margin:0;background:black;}</style></head>
        <body>
        <video id="v" muted playsinline style="width:1px;height:1px;"></video>
        <script>
        // 创建一个小的 canvas 来预热 GPU
        var c = document.createElement('canvas');
        c.width = c.height = 1;
        var ctx = c.getContext('2d');
        ctx.fillRect(0,0,1,1);
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)

        // 永久持有这个 WebView，防止进程退出
        self.keepAliveWebView = webView

        // 同时创建一个空闲的 WebView 放入池中
        let poolWebView = WKWebView(frame: .zero, configuration: createWebViewConfiguration())
        poolWebView.isOpaque = false
        poolWebView.backgroundColor = .clear
        poolWebView.scrollView.isScrollEnabled = false
        poolWebView.scrollView.backgroundColor = .clear
        poolWebView.scrollView.contentInsetAdjustmentBehavior = .never
        poolWebView.scrollView.bounces = false

        self.idlePool.append(poolWebView)

        #if DEBUG
        print(" WebView 已预热（keepAlive + 1个空闲）")
        #endif
    }

    @objc private func handleMemoryWarning() {
        queue.async { [weak self] in
            self?.idlePool.removeAll()
            // 注意：不清理 keepAliveWebView 和 activeWebViews
        }
        print(" WebView 空闲池已清理（内存警告）")
    }

    private func createWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = WKWebsiteDataStore.default()
        return config
    }

    /// 获取指定 URL 的 WebView（优先返回已缓存的正在播放的 WebView）
    func getWebView(for url: String, coordinator: DynamicCoverVideoView.Coordinator) -> (webView: WKWebView, isReused: Bool) {
        // 检查是否有该 URL 的活跃 WebView
        var existingWebView: WKWebView?
        queue.sync {
            existingWebView = activeWebViews[url]
        }

        if let webView = existingWebView {
            #if DEBUG
            print(" 复用已缓存的 WebView，恢复播放")
            #endif
            // 恢复视频播放（WebView 从视图层级移除后视频会暂停）
            // 使用更可靠的方式恢复播放，处理视频可能未加载完成的情况
            webView.evaluateJavaScript("""
                (function() {
                    var v = document.querySelector('video');
                    if (v) {
                        if (v.readyState >= 2) {
                            v.play();
                        } else {
                            v.addEventListener('canplay', function once() {
                                v.play();
                                v.removeEventListener('canplay', once);
                            });
                            v.load();
                        }
                    }
                })()
            """, completionHandler: nil)
            return (webView, true)
        }

        // 从空闲池获取或创建新的
        var webView: WKWebView?
        queue.sync {
            if !idlePool.isEmpty {
                webView = idlePool.removeLast()
                #if DEBUG
                print(" 从空闲池取出 WebView")
                #endif
            }
        }

        if let existingWebView = webView {
            existingWebView.stopLoading()
            existingWebView.navigationDelegate = coordinator
            existingWebView.configuration.userContentController.removeAllScriptMessageHandlers()
            existingWebView.configuration.userContentController.add(coordinator, name: "log")
            existingWebView.configuration.userContentController.add(coordinator, name: "cache")

            // 标记为活跃
            queue.async { [weak self] in
                self?.activeWebViews[url] = existingWebView
            }
            return (existingWebView, false)
        }

        // 创建新 WebView
        #if DEBUG
        print(" 创建新 WebView")
        #endif

        let config = createWebViewConfiguration()
        config.userContentController.add(coordinator, name: "log")
        config.userContentController.add(coordinator, name: "cache")

        let newWebView = WKWebView(frame: .zero, configuration: config)
        newWebView.navigationDelegate = coordinator
        newWebView.isOpaque = false
        newWebView.backgroundColor = .clear
        newWebView.scrollView.isScrollEnabled = false
        newWebView.scrollView.backgroundColor = .clear
        newWebView.scrollView.contentInsetAdjustmentBehavior = .never
        newWebView.scrollView.bounces = false

        // 标记为活跃
        queue.async { [weak self] in
            self?.activeWebViews[url] = newWebView
        }

        return (newWebView, false)
    }

    /// 回收 WebView（从活跃列表移除，放入空闲池）
    func recycleWebView(_ webView: WKWebView, url: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // 从活跃列表移除
            self.activeWebViews.removeValue(forKey: url)

            // 如果空闲池未满，放入空闲池
            if self.idlePool.count < self.maxIdlePoolSize {
                webView.stopLoading()
                webView.loadHTMLString("", baseURL: nil)
                webView.configuration.userContentController.removeAllScriptMessageHandlers()
                self.idlePool.append(webView)
                #if DEBUG
                print(" WebView 已回收到空闲池")
                #endif
            }
        }
    }

    /// 清空缓存池
    func clearPool() {
        queue.async { [weak self] in
            self?.idlePool.removeAll()
            self?.activeWebViews.removeAll()
            // 注意：不清理 keepAliveWebView
        }
    }
}

// MARK: - 动态封面视频视图 (WKWebView 版本 - 按 URL 缓存复用)
struct DynamicCoverVideoView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(masterUrl: url.absoluteString)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let masterUrl: String
        weak var webView: WKWebView?

        init(masterUrl: String) {
            self.masterUrl = masterUrl
            super.init()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "cache", let variantUrl = message.body as? String {
                HLSVariantCache.shared.setVariant(variantUrl, for: masterUrl)
            } else {
                #if DEBUG
                print(" JS: \(message.body)")
                #endif
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            #if DEBUG
            print(" WKWebView didFinish navigation")
            #endif
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            print(" WKWebView navigation failed: \(error)")
            #endif
        }
    }

    // MARK: - Swift 预解析（同步版本，用于 makeUIView）
    /// 尝试使用 Swift 同步解析 HLS master m3u8
    /// 如果失败则返回 nil，让 JavaScript 作为回退
    private static func swiftPreParse(masterUrl: String) -> String? {
        guard let url = URL(string: masterUrl) else { return nil }

        // 使用同步请求（带超时）
        let semaphore = DispatchSemaphore(value: 0)
        var resultVariant: String?

        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            defer { semaphore.signal() }

            guard let data = data,
                  let text = String(data: data, encoding: .utf8) else {
                #if DEBUG
                print(" Swift 预解析失败: \(error?.localizedDescription ?? "无数据")")
                #endif
                return
            }

            // 使用 HLSParser 解析
            if let variantUrl = HLSParser.shared.selectVariant(
                from: text,
                baseUrl: masterUrl,
                strategy: .highestQuality(maxPixels: nil)
            ) {
                resultVariant = variantUrl
                // 缓存结果
                HLSVariantCache.shared.setVariant(variantUrl, for: masterUrl)
                #if DEBUG
                print(" Swift 预解析成功: \(variantUrl.suffix(50))")
                #endif
            }
        }
        task.resume()

        // 等待最多 2 秒
        let timeout = DispatchTime.now() + .seconds(2)
        if semaphore.wait(timeout: timeout) == .timedOut {
            task.cancel()
            #if DEBUG
            print("⏱️ Swift 预解析超时，回退到 JavaScript")
            #endif
            return nil
        }

        return resultVariant
    }

    func makeUIView(context: Context) -> WKWebView {
        let urlString = url.absoluteString

        // 使用新的按 URL 缓存的 WebView 池
        let (webView, isReused) = WebViewPool.shared.getWebView(for: urlString, coordinator: context.coordinator)
        context.coordinator.webView = webView

        // 如果是复用的 WebView，已经在播放了，直接返回
        if isReused {
            #if DEBUG
            print(" 复用已播放的 WebView，跳过重新加载")
            #endif
            return webView
        }

        // 1. 先检查缓存
        let cachedVariant = HLSVariantCache.shared.getVariant(for: urlString)

        // 2. 如果没有缓存，尝试 Swift 预解析（在后台线程，避免阻塞主线程）
        if cachedVariant == nil {
            // 注意：这里我们不能在主线程做同步网络请求
            // 所以启动异步预解析，本次仍然使用 JavaScript 作为回退
            DispatchQueue.global(qos: .userInitiated).async {
                _ = Self.swiftPreParse(masterUrl: urlString)
            }
            #if DEBUG
            print(" 启动 Swift 后台预解析，本次使用 JavaScript 回退")
            #endif
        }

        let videoUrl = cachedVariant ?? urlString
        let hasCached = cachedVariant != nil

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; }
                html, body {
                    width: 100vw;
                    height: 100vh;
                    background: black;
                    overflow: hidden;
                }
                #container {
                    position: fixed;
                    top: 0;
                    left: 0;
                    width: 100vw;
                    height: 100vh;
                    overflow: hidden;
                }
                video {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    object-fit: cover;
                    object-position: center center;
                }
            </style>
        </head>
        <body>
            <div id="container">
                <video id="v" autoplay loop muted playsinline webkit-playsinline></video>
            </div>
            <script>
                const v = document.getElementById('v');
                const masterUrl = '\(url.absoluteString)';
                const cachedUrl = \(hasCached ? "'\(videoUrl)'" : "null");
                const log = msg => webkit.messageHandlers.log.postMessage(msg);
                const cache = url => webkit.messageHandlers.cache.postMessage(url);
                let retryCount = 0;
                const maxRetries = 2;
                let playAttempts = 0;
                let isPlaying = false;

                function tryPlay() {
                    if (isPlaying) return;
                    playAttempts++;
                    log('尝试播放 #' + playAttempts);
                    v.muted = true;

                    const playPromise = v.play();
                    if (playPromise !== undefined) {
                        playPromise.then(() => {
                            isPlaying = true;
                            log('播放成功 ');
                        }).catch(e => {
                            log('播放失败: ' + e.message);
                            if (playAttempts < 5) {
                                setTimeout(tryPlay, 100);
                            }
                        });
                    } else {
                        isPlaying = true;
                        log('播放已调用 (no promise)');
                    }
                }

                v.addEventListener('loadstart', () => log('事件: loadstart'));
                v.addEventListener('loadedmetadata', () => {
                    log('事件: loadedmetadata, 时长=' + v.duration);
                    setTimeout(tryPlay, 50);
                });
                v.addEventListener('canplay', () => {
                    log('事件: canplay');
                    tryPlay();
                });
                v.addEventListener('canplaythrough', () => {
                    log('事件: canplaythrough');
                    tryPlay();
                });
                v.addEventListener('playing', () => {
                    isPlaying = true;
                    log('事件: playing ');
                });
                v.addEventListener('pause', () => {
                    log('事件: pause');
                    if (!v.ended) {
                        setTimeout(tryPlay, 100);
                    }
                });
                v.addEventListener('waiting', () => log('事件: waiting'));
                v.addEventListener('stalled', () => log('事件: stalled'));
                v.addEventListener('timeupdate', function once() {
                    log('事件: timeupdate, 时间=' + v.currentTime.toFixed(2));
                    v.removeEventListener('timeupdate', once);
                });
                v.addEventListener('error', () => {
                    const code = v.error ? v.error.code : 'null';
                    log('错误: ' + code);
                    if (cachedUrl && retryCount < maxRetries) {
                        retryCount++;
                        log(' 缓存失效，重新解析 (尝试 ' + retryCount + ')');
                        loadFromMaster();
                    }
                });

                async function loadFromMaster() {
                    try {
                        log('正在解析变体...');
                        const resp = await fetch(masterUrl);
                        const text = await resp.text();
                        const lines = text.split('\\n');
                        const variants = [];

                        for (let i = 0; i < lines.length; i++) {
                            if (lines[i].startsWith('#EXT-X-STREAM-INF:')) {
                                const bw = lines[i].match(/BANDWIDTH=(\\d+)/);
                                const res = lines[i].match(/RESOLUTION=(\\d+)x(\\d+)/);
                                if (bw && res && lines[i+1]) {
                                    variants.push({ bw: +bw[1], w: +res[1], h: +res[2], url: lines[i+1].trim() });
                                }
                            }
                        }

                        if (variants.length === 0) {
                            log(' 未找到变体，使用主URL');
                            v.src = masterUrl;
                            v.load();
                            tryPlay();
                            return;
                        }

                        log('找到 ' + variants.length + ' 个变体');

                        let best = variants.reduce((a, b) => {
                            const aPixels = a.w * a.h;
                            const bPixels = b.w * b.h;
                            if (aPixels !== bPixels) return aPixels > bPixels ? a : b;
                            return a.bw > b.bw ? a : b;
                        });

                        let url = best.url;
                        if (!url.startsWith('http')) {
                            url = masterUrl.substring(0, masterUrl.lastIndexOf('/') + 1) + url;
                        }

                        log(' ' + best.w + 'x' + best.h + ' @ ' + (best.bw/1000000).toFixed(1) + 'Mbps');

                        cache(url);
                        v.src = url;
                        v.load();
                        tryPlay();

                    } catch (e) {
                        log(' 解析失败: ' + e.message);
                        v.src = masterUrl;
                        v.load();
                        tryPlay();
                    }
                }

                async function loadVideo() {
                    if (cachedUrl) {
                        log(' 使用缓存: ' + cachedUrl.split('/').pop());
                        v.src = cachedUrl;
                        v.load();
                        tryPlay();
                        return;
                    }
                    await loadFromMaster();
                }

                loadVideo();
            </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: URL(string: "https://music.apple.com"))
        #if DEBUG
        print(" WKWebView loading: \(hasCached ? "缓存" : "解析中")")
        #endif
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // 视图移除时不回收，保持播放状态
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // 不再立即回收，让 WebView 保持播放
        // WebViewPool 会通过 URL 缓存它，下次打开时复用
        #if DEBUG
        print(" WebView 保持活跃（不回收）")
        #endif
    }
}

// MARK: - AVPlayer 容器（SwiftUI 包装）
struct AVPlayerContainerView: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> UIView {
        let view = PlayerLayerView()
        view.player = player
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let v = uiView as? PlayerLayerView {
            v.player = player
        }
    }
}

// 使用 layerClass 直接返回 AVPlayerLayer（避免 layer 嵌套问题）
class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    
    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.backgroundColor = UIColor.clear.cgColor
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
}

// MARK: - HLS 资源代理加载器
class HLSResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    static let shared = HLSResourceLoaderDelegate()
    
    var originalURL: URL?
    private let session: URLSession
    
    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        super.init()
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let requestURL = loadingRequest.request.url else {
            return false
        }
        
        // 将代理 URL 转回真实 URL
        var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        
        guard let realURL = components?.url else {
            return false
        }
        
        print(" HLS Proxy loading: \(realURL.lastPathComponent)")
        
        var request = URLRequest(url: realURL)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print(" HLS Proxy error: \(error.localizedDescription)")
                loadingRequest.finishLoading(with: error)
                return
            }
            
            guard let data = data, let response = response as? HTTPURLResponse else {
                loadingRequest.finishLoading(with: NSError(domain: "HLSProxy", code: -1))
                return
            }
            
            // 处理 m3u8 播放列表 - 需要替换其中的 URL
            if realURL.pathExtension == "m3u8",
               var playlist = String(data: data, encoding: .utf8) {
                playlist = self?.rewritePlaylist(playlist, baseURL: realURL) ?? playlist
                if let modifiedData = playlist.data(using: .utf8) {
                    loadingRequest.dataRequest?.respond(with: modifiedData)
                    loadingRequest.finishLoading()
                    print(" HLS Proxy: playlist loaded")
                    return
                }
            }
            
            // 设置响应信息
            if let contentRequest = loadingRequest.contentInformationRequest {
                contentRequest.contentType = response.mimeType
                contentRequest.contentLength = Int64(data.count)
                contentRequest.isByteRangeAccessSupported = true
            }
            
            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()
        }
        task.resume()
        
        return true
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        // 取消请求
    }
    
    // 重写播放列表中的 URL
    private func rewritePlaylist(_ playlist: String, baseURL: URL) -> String {
        var result = playlist
        let lines = playlist.components(separatedBy: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 跳过注释和空行
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // 处理相对 URL
            if !trimmed.hasPrefix("http") {
                if let absoluteURL = URL(string: trimmed, relativeTo: baseURL)?.absoluteString {
                    // 替换为代理 URL
                    let proxyURL = absoluteURL.replacingOccurrences(of: "https://", with: "hlsproxy://")
                    result = result.replacingOccurrences(of: trimmed, with: proxyURL)
                }
            } else {
                // 绝对 URL 也替换为代理
                let proxyURL = trimmed.replacingOccurrences(of: "https://", with: "hlsproxy://")
                result = result.replacingOccurrences(of: trimmed, with: proxyURL)
            }
        }
        
        return result
    }
}

// MARK: - 播放控制按钮
struct PlayerControlButton: View {
    let icon: String
    var size: CGFloat = 24
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.2)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2)) {
                    isPressed = false
                }
                action()
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .scaleEffect(isPressed ? 0.85 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 播放列表弹窗
struct PlaylistSheetView: View {
    @StateObject private var audioPlayer = AudioPlayer.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 播放模式指示
                HStack {
                    Image(systemName: audioPlayer.playMode.icon)
                        .foregroundColor(.secondary)
                    Text(audioPlayer.playMode.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(audioPlayer.playlist.count) 首歌曲")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGroupedBackground))
                
                if audioPlayer.playlist.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("播放列表为空")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(audioPlayer.playlist.enumerated()), id: \.element.id) { index, track in
                            PlaylistTrackRow(
                                track: track,
                                index: index,
                                isPlaying: index == audioPlayer.currentIndex
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // 点击切换到该歌曲
                                audioPlayer.currentIndex = index
                                Task {
                                    await audioPlayer.play(track: track)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            // 从播放列表删除
                            audioPlayer.playlist.remove(atOffsets: indexSet)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("清空") {
                        audioPlayer.playlist.removeAll()
                    }
                    .foregroundColor(.red)
                    .disabled(audioPlayer.playlist.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 播放列表歌曲行
struct PlaylistTrackRow: View {
    let track: Track
    let index: Int
    let isPlaying: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // 序号或播放指示
            ZStack {
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 28)
            
            // 封面
            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            // 歌曲信息
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 15, weight: isPlaying ? .semibold : .regular))
                    .foregroundColor(isPlaying ? .red : .primary)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 分享弹窗
struct ShareSheetView: View {
    let track: Track
    @Environment(\.dismiss) var dismiss
    @State private var showingSystemShare = false
    @State private var coverImage: UIImage?
    
    private var shareText: String {
        "我正在听《\(track.name)》- \(track.artistName) #NeteaseMusic"
    }
    
    private var shareUrl: URL? {
        URL(string: "https://music.163.com/song?id=\(track.id)")
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // 封面预览
                if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .onAppear {
                                    // 保存图片用于分享
                                    let renderer = ImageRenderer(content: image.resizable().aspectRatio(contentMode: .fill).frame(width: 300, height: 300))
                                    coverImage = renderer.uiImage
                                }
                        default:
                            Rectangle().fill(Color.gray.opacity(0.3))
                        }
                    }
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 10)
                }
                
                VStack(spacing: 8) {
                    Text(track.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(track.artistName)
                        .foregroundColor(.secondary)
                }
                
                // 分享按钮
                VStack(spacing: 16) {
                    HStack(spacing: 40) {
                        ShareOptionButton(icon: "square.and.arrow.up", title: "分享", color: .blue) {
                            showingSystemShare = true
                        }
                        ShareOptionButton(icon: "link", title: "复制链接", color: .green) {
                            if let url = shareUrl {
                                UIPasteboard.general.string = url.absoluteString
                                dismiss()
                            }
                        }
                        ShareOptionButton(icon: "doc.on.doc", title: "复制文案", color: .orange) {
                            UIPasteboard.general.string = shareText
                            dismiss()
                        }
                    }
                }
                .padding(.top, 20)
                
                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("分享")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingSystemShare) {
                let items: [Any] = {
                    var result: [Any] = [shareText]
                    if let url = shareUrl {
                        result.append(url)
                    }
                    if let image = coverImage {
                        result.append(image)
                    }
                    return result
                }()
                ActivityViewController(activityItems: items, applicationActivities: nil)
            }
        }
    }
}

struct ShareOptionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 22))
                            .foregroundColor(color)
                    )
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
    }
}

// MARK: - 系统分享弹窗
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - AirPlay 按钮
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let routePickerView = AVRoutePickerView()
        routePickerView.tintColor = UIColor.white.withAlphaComponent(0.6)
        routePickerView.activeTintColor = UIColor.white
        routePickerView.prioritizesVideoDevices = false
        
        // 设置背景透明
        routePickerView.backgroundColor = .clear
        
        return routePickerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - 播放器组件视图

struct PlayerSongInfoView: View {
    let track: Track?
    let onShowLike: () -> Void
    let onShowShare: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(track?.name ?? "")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(track?.artistName ?? "")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 喜欢按钮
            Button(action: onShowLike) {
                Image(systemName: "heart")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(8)
            }
            
            Button(action: onShowShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(8)
            }
        }
        .padding(.horizontal, 40)
    }
}

struct PlayerProgressView: View {
    let currentTime: Double
    let duration: Double
    @Binding var isDragging: Bool
    @Binding var dragProgress: Double
    let onSeek: (Double) -> Void
    
    private var displayTime: Double {
        isDragging ? dragProgress : currentTime
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景
                    Capsule()
                        .fill(.white.opacity(0.3))
                        .frame(height: 4)
                    
                    // 进度
                    Capsule()
                        .fill(.white)
                        .frame(width: geometry.size.width * CGFloat(displayTime / max(duration, 1)), height: 4)
                    
                    // 滑块
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .offset(x: geometry.size.width * CGFloat(displayTime / max(duration, 1)) - 6)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let progress = min(max(0, value.location.x / geometry.size.width), 1)
                            dragProgress = progress * duration
                        }
                        .onEnded { value in
                            isDragging = false
                            let progress = min(max(0, value.location.x / geometry.size.width), 1)
                            onSeek(progress * duration)
                        }
                )
            }
            .frame(height: 12)
            
            // 时间标签
            HStack {
                Text(formatTime(displayTime))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(formatTime(duration))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 40)
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PlayerControlsView: View {
    let isPlaying: Bool
    let isLoading: Bool
    @Binding var isPlayButtonPressed: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    
    var body: some View {
        HStack(spacing: 50) {
            // 上一首
            Button(action: onPrevious) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
            
            // 播放/暂停
            Button(action: onPlayPause) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 72, height: 72)
                    
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }
                }
                .scaleEffect(isPlayButtonPressed ? 0.95 : 1.0)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPlayButtonPressed = true }
                    .onEnded { _ in isPlayButtonPressed = false }
            )
            
            // 下一首
            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
        }
    }
}

struct PlayerVolumeView: View {
    @Binding var currentVolume: Float
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
            
            Slider(value: $currentVolume, in: 0...1)
                .tint(.white)
                .onChange(of: currentVolume) { _, newValue in
                    MPVolumeView.setVolume(newValue)
                }
            
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 40)
    }
}

struct PlayerBottomBarView: View {
    let showLyrics: Bool
    let playModeIcon: String
    @ObservedObject var sourceConfig: MusicSourceConfig
    @ObservedObject var audioPlayer: AudioPlayer
    let onToggleLyrics: () -> Void
    let onShowComments: () -> Void
    let onShowPlaylist: () -> Void
    let onTogglePlayMode: () -> Void
    
    @State private var showQualityPicker = false
    
    // 将API返回的level转为显示名称
    private func qualityDisplayName(_ level: String) -> String {
        switch level {
        case "standard": return "标准"
        case "exhigh": return "HQ"
        case "lossless": return "无损"
        case "hires": return "Hi-Res"
        case "jyeffect": return "环绕"
        case "sky": return "沉浸"
        case "jymaster": return "母带"
        default: return level
        }
    }
    
    // 显示实际音质和请求音质
    private var displayQuality: String {
        let requestedQuality = sourceConfig.quality.shortName
        
        if audioPlayer.actualQuality.isEmpty {
            return requestedQuality
        }
        
        let actualName = qualityDisplayName(audioPlayer.actualQuality)
        
        // 如果实际音质与请求音质相同，只显示一个
        if audioPlayer.actualQuality == sourceConfig.quality.rawValue {
            return actualName
        }
        
        // 不同时显示两者
        return "\(actualName)(\(requestedQuality))"
    }
    
    var body: some View {
        HStack(spacing: 32) {
            // 歌词按钮
            Button(action: onToggleLyrics) {
                Image(systemName: showLyrics ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // 评论按钮
            Button(action: onShowComments) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // 音质按钮 - 显示实际音质
            Button(action: { showQualityPicker = true }) {
                Text(displayQuality)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                    )
            }
            
            Spacer()
            
            // 播放模式
            Button(action: onTogglePlayMode) {
                Image(systemName: playModeIcon)
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // 播放列表
            Button(action: onShowPlaylist) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 40)
        .sheet(isPresented: $showQualityPicker) {
            QualityPickerView(sourceConfig: sourceConfig)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
        }
    }
}

// MARK: - 音质选择视图
struct QualityPickerView: View {
    @ObservedObject var sourceConfig: MusicSourceConfig
    @Environment(\.dismiss) var dismiss
    @State private var selectedQuality: MusicQuality
    
    init(sourceConfig: MusicSourceConfig) {
        self.sourceConfig = sourceConfig
        _selectedQuality = State(initialValue: sourceConfig.quality)
    }
    
    // 音质分组
    private let standardQualities: [MusicQuality] = [.standard, .exhigh]
    private let hdQualities: [MusicQuality] = [.lossless, .hires]
    private let spatialQualities: [MusicQuality] = [.jyeffect, .sky, .jymaster]
    
    var body: some View {
        ZStack {
            // 暗色模糊背景
            Color.black.opacity(0.95)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部拖拽指示器
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)
                
                // 标题
                HStack {
                    Text("音质选择")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // 标准音质组
                        QualityGroup(title: "标准", qualities: standardQualities, selectedQuality: $selectedQuality, onSelect: applyQuality)
                        
                        // 无损音质组
                        QualityGroup(title: "无损", qualities: hdQualities, selectedQuality: $selectedQuality, onSelect: applyQuality)
                        
                        // 空间音频组
                        QualityGroup(title: "空间音频", qualities: spatialQualities, selectedQuality: $selectedQuality, onSelect: applyQuality)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    private func applyQuality(_ quality: MusicQuality) {
        let oldQuality = sourceConfig.quality
        sourceConfig.quality = quality
        AudioPlayer.shared.clearPreloadCache()
        
        if oldQuality != quality, let currentTrack = AudioPlayer.shared.currentTrack {
            let currentTime = AudioPlayer.shared.currentTime
            Task {
                await AudioPlayer.shared.play(track: currentTrack)
                try? await Task.sleep(nanoseconds: 500_000_000)
                AudioPlayer.shared.seek(to: currentTime)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
        }
    }
}

// MARK: - 音质分组
struct QualityGroup: View {
    let title: String
    let qualities: [MusicQuality]
    @Binding var selectedQuality: MusicQuality
    let onSelect: (MusicQuality) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .padding(.leading, 4)
            
            VStack(spacing: 8) {
                ForEach(qualities, id: \.self) { quality in
                    QualityOptionCard(
                        quality: quality,
                        isSelected: selectedQuality == quality,
                        onSelect: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedQuality = quality
                            }
                            onSelect(quality)
                        }
                    )
                }
            }
        }
    }
}

// MARK: - 音质选项卡片
struct QualityOptionCard: View {
    let quality: MusicQuality
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var qualityInfo: (icon: String, gradient: [Color], desc: String, badge: String?) {
        switch quality {
        case .standard:
            return ("speaker.wave.1.fill", [.gray, .gray.opacity(0.7)], "128kbps MP3", nil)
        case .exhigh:
            return ("speaker.wave.2.fill", [.blue, .cyan], "320kbps MP3", "HQ")
        case .lossless:
            return ("hifispeaker.fill", [.green, .mint], "16bit/44.1kHz FLAC", "无损")
        case .hires:
            return ("hifispeaker.2.fill", [.purple, .pink], "24bit/192kHz", "Hi-Res")
        case .jyeffect:
            return ("ear.fill", [.orange, .yellow], "高清环绕声", "环绕")
        case .sky:
            return ("sparkles", [.cyan, .blue], "Dolby Atmos", "沉浸")
        case .jymaster:
            return ("crown.fill", [.yellow, .orange], "超清母带", "臻峰")
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // 渐变图标
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isSelected ? qualityInfo.gradient : [.gray.opacity(0.3), .gray.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: qualityInfo.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isSelected ? .white : .gray)
                }
                
                // 文字
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(quality.displayName)
                            .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(.white)
                        
                        if let badge = qualityInfo.badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    LinearGradient(
                                        colors: qualityInfo.gradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(qualityInfo.desc)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                // 选中指示
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected 
                                ? LinearGradient(colors: qualityInfo.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [.white.opacity(0.2)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 2
                        )
                        .frame(width: 26, height: 26)
                    
                    if isSelected {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: qualityInfo.gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 16, height: 16)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isSelected 
                            ? LinearGradient(colors: qualityInfo.gradient.map { $0.opacity(0.15) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected
                            ? LinearGradient(colors: qualityInfo.gradient.map { $0.opacity(0.5) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - 喜欢选项弹窗
struct LikeOptionsSheet: View {
    let track: Track
    @Environment(\.dismiss) var dismiss
    @StateObject private var localStorage = LocalStorageService.shared
    
    @State private var isLiking = false
    @State private var showLoginAlert = false
    @State private var toastMessage: String?
    @State private var showToast = false
    
    private let userService = UserService.shared
    private let authService = AuthService.shared
    
    // 检查是否已本地收藏
    private var isLocalFavorited: Bool {
        localStorage.isFavorite(track.id)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 歌曲信息
                HStack(spacing: 16) {
                    // 封面
                    if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.name)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artistName)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(.systemGray6))
                
                Divider()
                
                // 选项列表
                VStack(spacing: 0) {
                    // 喜欢到网易云
                    LikeOptionRow(
                        icon: "cloud.fill",
                        iconColor: .red,
                        title: "喜欢到网易云",
                        subtitle: "同步到网易云账号",
                        isLoading: isLiking,
                        action: likeToCloud
                    )
                    
                    Divider().padding(.leading, 60)
                    
                    // 喜欢到本地
                    LikeOptionRow(
                        icon: isLocalFavorited ? "heart.fill" : "heart",
                        iconColor: isLocalFavorited ? .pink : .pink,
                        title: isLocalFavorited ? "已收藏到本地" : "收藏到本地",
                        subtitle: isLocalFavorited ? "点击取消本地收藏" : "保存到本地收藏夹",
                        isLoading: false,
                        action: toggleLocalFavorite
                    )
                }
                
                Spacer()
            }
            .navigationTitle("喜欢歌曲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .alert("需要登录", isPresented: $showLoginAlert) {
                Button("取消", role: .cancel) {}
                Button("去登录") {
                    dismiss()
                    // 跳转到登录页面（通过发通知）
                    NotificationCenter.default.post(name: .showLoginSheet, object: nil)
                }
            } message: {
                Text("请先登录网易云账号后再进行操作")
            }
            .overlay(alignment: .bottom) {
                if showToast, let message = toastMessage {
                    ToastView(message: message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 20)
                }
            }
        }
    }
    
    // MARK: - 喜欢到网易云
    private func likeToCloud() {
        // 检查登录状态
        guard authService.isLoggedIn() else {
            showLoginAlert = true
            return
        }
        
        isLiking = true
        Task {
            do {
                let _ = try await userService.likeSong(id: track.id, like: true)
                await MainActor.run {
                    isLiking = false
                    showToastMessage("已添加到网易云喜欢")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isLiking = false
                    showToastMessage("喜欢失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - 切换本地收藏
    private func toggleLocalFavorite() {
        let wasAdded = localStorage.toggleFavorite(track)
        showToastMessage(wasAdded ? "已添加到本地收藏" : "已从本地收藏移除")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismiss()
        }
    }
    
    // MARK: - 显示 Toast
    private func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.3)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.spring(response: 0.3)) {
                showToast = false
            }
        }
    }
}

// MARK: - 喜欢选项行
struct LikeOptionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // 图标
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundColor(iconColor)
                    }
                }
                
                // 文字
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Toast 视图
struct ToastView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.8))
            )
    }
}

// MARK: - 登录弹窗通知
extension Notification.Name {
    static let showLoginSheet = Notification.Name("showLoginSheet")
}

#Preview {
    PlayerView()
}
