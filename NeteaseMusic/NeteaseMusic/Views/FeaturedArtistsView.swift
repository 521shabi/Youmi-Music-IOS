import SwiftUI

// MARK: - 专属推荐数据
struct FeaturedSongItem: Identifiable {
    let id = UUID()
    let track: Track
    let quote: String
    let artistName: String
    let style: FeaturedStyle
}

enum FeaturedStyle {
    case leslie
    case wangJie
    case luoYan
    
    var accentColor: Color {
        switch self {
        case .leslie: return Color(red: 0.95, green: 0.85, blue: 0.55)
        case .wangJie: return Color(red: 0.45, green: 0.65, blue: 1.0)
        case .luoYan: return Color(red: 1.0, green: 0.25, blue: 0.25)
        }
    }
    
    var overlayGradient: [Color] {
        switch self {
        case .leslie:
            return [Color(red: 0.15, green: 0.12, blue: 0.05).opacity(0.3), Color(red: 0.1, green: 0.08, blue: 0.02).opacity(0.95)]
        case .wangJie:
            return [Color(red: 0.02, green: 0.05, blue: 0.15).opacity(0.3), Color(red: 0.02, green: 0.04, blue: 0.12).opacity(0.95)]
        case .luoYan:
            return [Color(red: 0.2, green: 0.02, blue: 0.02).opacity(0.2), Color(red: 0.12, green: 0.01, blue: 0.01).opacity(0.95)]
        }
    }
}

// MARK: - 专属推荐页面
struct FeaturedArtistsView: View {
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @Environment(\.dismiss) var dismiss
    @State private var scrollOffset: CGFloat = 0
    
    private let songs: [FeaturedSongItem] = [
        FeaturedSongItem(
            track: Track(
                id: 187092, name: "至少还有你",
                ar: [Artist(id: 6457, name: "张国荣")],
                al: Album(id: 18978, name: "热·情演唱会", picUrl: "https://p1.music.126.net/mK8lkreh39iShTtk0PUo0Q==/109951172084690178.jpg"),
                dt: 342493
            ),
            quote: "如果命运能选择\n十字路口你与我",
            artistName: "张国荣", style: .leslie
        ),
        FeaturedSongItem(
            track: Track(
                id: 188489, name: "风继续吹",
                ar: [Artist(id: 6457, name: "张国荣")],
                al: Album(id: 19078, name: "张国荣告别乐坛演唱会", picUrl: "https://p1.music.126.net/FXwdpVaGq631wrlVCNYj0Q==/109951170517241124.jpg"),
                dt: 415892
            ),
            quote: "风继续吹\n不忍远离",
            artistName: "张国荣", style: .leslie
        ),
        FeaturedSongItem(
            track: Track(
                id: 156606, name: "我是真的爱上你",
                ar: [Artist(id: 5358, name: "王杰")],
                al: Album(id: 15772, name: "不孤单", picUrl: "https://p1.music.126.net/_3vS8UPzLeJcd8WaK1Ii4g==/109951165914316886.jpg"),
                dt: 301232
            ),
            quote: "我是真的爱上你\n我是真的想你",
            artistName: "王杰", style: .wangJie
        ),
        FeaturedSongItem(
            track: Track(
                id: 158880, name: "忘了你忘了我",
                ar: [Artist(id: 5358, name: "王杰")],
                al: Album(id: 15961, name: "忘了你忘了我", picUrl: "https://p1.music.126.net/rdT_f0d-d18hfkl2VptGjg==/109951168956484157.jpg"),
                dt: 277575
            ),
            quote: "忘了你忘了我\n忘了那些快乐与难过",
            artistName: "王杰", style: .wangJie
        ),
        FeaturedSongItem(
            track: Track(
                id: 1918576268, name: "红",
                ar: [Artist(id: 33863232, name: "罗言")],
                al: Album(id: 140087138, name: "When the world is came，take it！", picUrl: "https://p2.music.126.net/G-inyKjA-jO5MuOuV3g7Pg==/109951167027986653.jpg"),
                dt: 161585
            ),
            quote: "红\n是心跳的颜色",
            artistName: "罗言", style: .luoYan
        ),
    ]
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                headerView
                
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    FeaturedSongCard(song: song, index: index) {
                        let allTracks = songs.map { $0.track }
                        if let idx = allTracks.firstIndex(where: { $0.id == song.track.id }) {
                            audioPlayer.setPlaylist(allTracks, startAt: idx)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            .padding(.bottom, 120)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("专属推荐")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
    
    private var headerView: some View {
        VStack(spacing: 10) {
            Text("专属推荐")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundColor(.white)
            
            Text("那些年，陪伴我们的声音")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.top, 16)
        .padding(.bottom, 28)
    }
}

// MARK: - 歌曲卡片（封面背景 + 交互动画）
struct FeaturedSongCard: View {
    let song: FeaturedSongItem
    let index: Int
    let onPlay: () -> Void
    
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @State private var isPressed = false
    @State private var appeared = false
    @State private var pulseScale: CGFloat = 1.0
    
    private var isPlaying: Bool {
        audioPlayer.currentTrack?.id == song.track.id
    }
    
    private var coverUrl: URL? {
        song.track.coverUrl.flatMap { URL(string: $0) }
    }
    
    var body: some View {
        Button(action: onPlay) {
            ZStack(alignment: .bottomLeading) {
                // 封面背景
                coverBackground
                
                // 渐变遮罩
                LinearGradient(
                    colors: song.style.overlayGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // 播放时的脉冲光晕
                if isPlaying {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(song.style.accentColor.opacity(0.4), lineWidth: 2)
                        .scaleEffect(pulseScale)
                        .opacity(2.0 - Double(pulseScale))
                }
                
                // 内容
                cardContent
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: song.style.accentColor.opacity(isPlaying ? 0.35 : 0.15), radius: isPlaying ? 20 : 12, x: 0, y: 8)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 40)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6).delay(Double(index) * 0.12)) {
                    appeared = true
                }
            }
            .onChangeCompat(of: isPlaying) { _, playing in
                if playing { startPulse() } else { pulseScale = 1.0 }
            }
            .onAppear {
                if isPlaying { startPulse() }
            }
        }
        .buttonStyle(CardPressStyle(isPressed: $isPressed))
    }
    
    // MARK: - 封面背景
    @ViewBuilder
    private var coverBackground: some View {
        if let url = coverUrl {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 220)
                        .scaleEffect(isPressed ? 1.05 : 1.0)
                        .animation(.easeOut(duration: 0.3), value: isPressed)
                case .failure:
                    fallbackCover
                case .empty:
                    fallbackCover
                        .overlay(ProgressView().tint(.white.opacity(0.3)))
                @unknown default:
                    fallbackCover
                }
            }
        } else {
            fallbackCover
        }
    }
    
    private var fallbackCover: some View {
        LinearGradient(
            colors: song.style.overlayGradient.map { $0.opacity(1) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 220)
    }
    
    // MARK: - 卡片内容
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            
            // 歌手标签
            HStack(spacing: 6) {
                Circle()
                    .fill(song.style.accentColor)
                    .frame(width: 6, height: 6)
                
                Text(song.artistName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(song.style.accentColor)
                    .tracking(2)
            }
            
            // 歌曲名
            Text(song.track.name)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                .padding(.top, 6)
            
            // 歌词
            Text(song.quote)
                .font(.system(size: 13, design: .serif))
                .foregroundColor(.white.opacity(0.55))
                .lineSpacing(4)
                .padding(.top, 6)
            
            // 底部：专辑名 + 播放状态
            HStack {
                Text(song.track.albumName)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
                    .lineLimit(1)
                
                Spacer()
                
                playButton
            }
            .padding(.top, 12)
        }
        .padding(20)
    }
    
    // MARK: - 播放按钮
    private var playButton: some View {
        HStack(spacing: 5) {
            if isPlaying {
                if #available(iOS 17.0, *) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(song.style.accentColor)
                        .symbolEffect(.variableColor.iterative)
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(song.style.accentColor)
                }
                Text("播放中")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(song.style.accentColor)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                Text("播放")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill((isPlaying ? song.style.accentColor : Color.white).opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke((isPlaying ? song.style.accentColor : Color.white).opacity(0.15), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - 脉冲动画
    private func startPulse() {
        pulseScale = 1.0
        withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
            pulseScale = 1.06
        }
    }
}

// MARK: - 按压样式
struct CardPressStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChangeCompat(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}
