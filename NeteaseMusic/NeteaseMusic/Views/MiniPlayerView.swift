import SwiftUI

// MARK: - 液体玻璃效果扩展 (模拟 iOS 26 Liquid Glass)
extension View {
    /// 液体玻璃效果 - 圆角矩形
    func liquidGlass<S: Shape>(in shape: S) -> some View {
        LiquidGlassModifier(shape: shape, content: self)
    }
    
    /// 液体玻璃效果 - 圆形
    func liquidGlassCircle() -> some View {
        LiquidGlassCircleModifier(content: self)
    }
    
    /// 液体玻璃效果 - 胶囊形
    func liquidGlassCapsule() -> some View {
        LiquidGlassCapsuleModifier(content: self)
    }
}

// MARK: - 增强版液态玻璃修饰器
private struct LiquidGlassModifier<S: Shape, Content: View>: View {
    let shape: S
    let content: Content
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        content
            .background(
                ZStack {
                    // 层 1: 模糊背景
                    shape
                        .fill(.ultraThinMaterial)
                    
                    // 层 2: 主背景色
                    shape
                        .fill(
                            colorScheme == .dark
                                ? Color(white: 0.12).opacity(0.75)
                                : Color(white: 0.98).opacity(0.8)
                        )
                    
                    // 层 3: 顶部高光渐变（模拟玻璃反射）
                    shape
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.2), Color.white.opacity(0.05), .clear]
                                    : [Color.white.opacity(0.9), Color.white.opacity(0.3), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .mask(
                            shape.fill(
                                LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)
                            )
                        )
                    
                    // 层 4: 边缘高光描边
                    shape
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.35), Color.white.opacity(0.1), Color.white.opacity(0.05)]
                                    : [Color.white.opacity(0.95), Color.white.opacity(0.5), Color.white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                    
                    // 层 5: 内发光效果
                    shape
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.08)
                                : Color.white.opacity(0.4),
                            lineWidth: 0.5
                        )
                        .padding(1.5)
                }
                .compositingGroup()
            )
            // 多层阴影增加深度
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 20, x: 0, y: 10)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 8, x: 0, y: 4)
    }
}

private struct LiquidGlassCircleModifier<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        content
            .background(
                ZStack {
                    // 模糊背景
                    Circle()
                        .fill(.ultraThinMaterial)
                    
                    // 主背景
                    Circle()
                        .fill(
                            colorScheme == .dark
                                ? Color(white: 0.12).opacity(0.75)
                                : Color(white: 0.98).opacity(0.8)
                        )
                    
                    // 顶部高光
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.25), .clear]
                                    : [Color.white.opacity(0.85), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    
                    // 边缘高光
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.35), Color.white.opacity(0.08)]
                                    : [Color.white.opacity(0.95), Color.white.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
                .compositingGroup()
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.12), radius: 12, x: 0, y: 6)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.15 : 0.06), radius: 4, x: 0, y: 2)
    }
}

private struct LiquidGlassCapsuleModifier<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        content
            .background(
                ZStack {
                    // 模糊背景
                    Capsule()
                        .fill(.ultraThinMaterial)
                    
                    // 主背景
                    Capsule()
                        .fill(
                            colorScheme == .dark
                                ? Color(white: 0.12).opacity(0.75)
                                : Color(white: 0.98).opacity(0.8)
                        )
                    
                    // 顶部高光
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.2), .clear]
                                    : [Color.white.opacity(0.8), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    
                    // 边缘高光
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.3), Color.white.opacity(0.06)]
                                    : [Color.white.opacity(0.9), Color.white.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
                .compositingGroup()
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 12, x: 0, y: 5)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - 迷你播放器状态（用于 Equatable 比较）
private struct MiniPlayerState: Equatable {
    let trackId: Int?
    let trackName: String?
    let artistName: String?
    let coverUrl: String?
    let isPlaying: Bool
    let isLoading: Bool
}

// MARK: - 液体玻璃迷你播放器
struct MiniPlayerView: View {
    @StateObject private var audioPlayer = AudioPlayer.shared
    @State private var showPlayer = false
    @State private var isPressed = false

    // 提取状态用于比较，避免不必要的重绘
    private var playerState: MiniPlayerState {
        MiniPlayerState(
            trackId: audioPlayer.currentTrack?.id,
            trackName: audioPlayer.currentTrack?.name,
            artistName: audioPlayer.currentTrack?.artistName,
            coverUrl: audioPlayer.currentTrack?.coverUrl,
            isPlaying: audioPlayer.isPlaying,
            isLoading: audioPlayer.isLoading
        )
    }

    var body: some View {
        MiniPlayerContent(
            state: playerState,
            isPressed: $isPressed,
            showPlayer: $showPlayer,
            onPlayPause: { audioPlayer.togglePlayPause() },
            onNext: { audioPlayer.playNext() }
        )
        // 使用 overlay 而不是 fullScreenCover，让 PlayerView 保持存活
        .overlay {
            if showPlayer {
                PlayerViewContainer(isPresented: $showPlayer)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showPlayer)
    }
}

// MARK: - PlayerView 容器（保持 PlayerView 存活）
struct PlayerViewContainer: View {
    @Binding var isPresented: Bool

    var body: some View {
        PlayerView(dismiss: { isPresented = false })
            .ignoresSafeArea()
    }
}

// MARK: - 迷你播放器内容（Equatable 优化）
private struct MiniPlayerContent: View, Equatable {
    let state: MiniPlayerState
    @Binding var isPressed: Bool
    @Binding var showPlayer: Bool
    let onPlayPause: () -> Void
    let onNext: () -> Void
    
    // 只比较状态，忽略闭包
    static func == (lhs: MiniPlayerContent, rhs: MiniPlayerContent) -> Bool {
        lhs.state == rhs.state && lhs.isPressed == rhs.isPressed
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // 封面
            albumCover
            
            // 歌曲信息
            songInfo
            
            Spacer()
            
            // 控制按钮
            controlButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onTapGesture {
            showPlayer = true
        }
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
    
    // MARK: - 专辑封面
    private var albumCover: some View {
        Group {
            if let coverUrl = state.coverUrl,
               let url = URL(string: coverUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    coverPlaceholder
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemGray4), Color(.systemGray5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    // MARK: - 歌曲信息
    private var songInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(state.trackName ?? "未播放")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Text(state.artistName ?? "")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
    
    // MARK: - 控制按钮
    // 缓存触觉反馈生成器（避免重复创建）
    private static let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    
    private var controlButtons: some View {
        HStack(spacing: 8) {
            // 播放/暂停按钮
            Button(action: {
                Self.impactGenerator.impactOccurred()
                onPlayPause()
            }) {
                ZStack {
                    if state.isLoading {
                        ProgressView()
                            .frame(width: 40, height: 40)
                    } else {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 40)
                    }
                }
            }
            .buttonStyle(MiniPlayerButtonStyle())
            
            // 下一首按钮
            Button(action: {
                Self.impactGenerator.impactOccurred()
                onNext()
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(MiniPlayerButtonStyle())
        }
    }
}

// MARK: - 迷你播放器按钮样式
struct MiniPlayerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    VStack {
        Spacer()
        MiniPlayerView()
    }
    .background(Color.gray.opacity(0.3))
}
