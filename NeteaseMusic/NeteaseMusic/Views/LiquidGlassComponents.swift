import SwiftUI

// MARK: - iOS 26 液态玻璃设计系统 (Apple Music 风格) - 增强版

// MARK: - 液态玻璃主题配置（预计算颜色，避免运行时计算）
struct LiquidGlassTheme {
    // 深色模式
    static let darkBackground = Color(white: 0.12).opacity(0.88)
    static let darkBackgroundSecondary = Color(white: 0.18).opacity(0.85)
    static let darkHighlightTop = Color.white.opacity(0.25)
    static let darkHighlightBottom = Color.white.opacity(0.05)
    static let darkBorder = Color.white.opacity(0.18)
    static let darkInnerGlow = Color.white.opacity(0.08)
    static let darkShadowPrimary = Color.black.opacity(0.4)
    static let darkShadowSecondary = Color.black.opacity(0.2)

    // 浅色模式
    static let lightBackground = Color(white: 0.98).opacity(0.92)
    static let lightBackgroundSecondary = Color(white: 0.96).opacity(0.9)
    static let lightHighlightTop = Color.white.opacity(0.9)
    static let lightHighlightBottom = Color.white.opacity(0.3)
    static let lightBorder = Color.black.opacity(0.08)
    static let lightInnerGlow = Color.white.opacity(0.5)
    static let lightShadowPrimary = Color.black.opacity(0.12)
    static let lightShadowSecondary = Color.black.opacity(0.06)
}

// MARK: - 液态玻璃卡片（增强版）
struct LiquidGlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16
    @Environment(\.colorScheme) var colorScheme

    init(cornerRadius: CGFloat = 20, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // 层1: 主背景
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(colorScheme == .dark ? LiquidGlassTheme.darkBackground : LiquidGlassTheme.lightBackground)

                    // 层2: 顶部高光渐变（模拟玻璃反射）
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [LiquidGlassTheme.darkHighlightTop, .clear, .clear]
                                    : [LiquidGlassTheme.lightHighlightTop, .clear, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .mask(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                        )

                    // 层3: 边缘高光描边
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [LiquidGlassTheme.darkHighlightTop, LiquidGlassTheme.darkHighlightBottom]
                                    : [LiquidGlassTheme.lightHighlightTop, LiquidGlassTheme.lightHighlightBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )

                    // 层4: 内边框（增加玻璃边缘感）
                    RoundedRectangle(cornerRadius: cornerRadius - 1)
                        .stroke(colorScheme == .dark ? LiquidGlassTheme.darkBorder : LiquidGlassTheme.lightBorder, lineWidth: 0.5)
                        .padding(1)
                }
                .compositingGroup()
            )
            // 分层阴影
            .shadow(color: colorScheme == .dark ? LiquidGlassTheme.darkShadowPrimary : LiquidGlassTheme.lightShadowPrimary, radius: 20, x: 0, y: 10)
            .shadow(color: colorScheme == .dark ? LiquidGlassTheme.darkShadowSecondary : LiquidGlassTheme.lightShadowSecondary, radius: 8, x: 0, y: 4)
    }
}

// MARK: - 液态玻璃分组容器（增强版）
struct LiquidGlassSection<Content: View>: View {
    let title: String?
    let content: Content
    @Environment(\.colorScheme) var colorScheme

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
            }

            content
                .background(
                    ZStack {
                        // 主背景
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colorScheme == .dark ? LiquidGlassTheme.darkBackground : LiquidGlassTheme.lightBackground)

                        // 顶部光泽
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.6),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )

                        // 边缘高光
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color.white.opacity(0.2), Color.white.opacity(0.05)]
                                        : [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .compositingGroup()
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: colorScheme == .dark ? LiquidGlassTheme.darkShadowPrimary : LiquidGlassTheme.lightShadowPrimary, radius: 16, x: 0, y: 8)
                .shadow(color: colorScheme == .dark ? LiquidGlassTheme.darkShadowSecondary : LiquidGlassTheme.lightShadowSecondary, radius: 6, x: 0, y: 3)
                .padding(.horizontal, 16)
        }
    }
}

// MARK: - 液态玻璃列表行
struct LiquidGlassRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    let leading: Leading
    let trailing: Trailing
    @Environment(\.colorScheme) var colorScheme
    
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = trailing()
    }
    
    var body: some View {
        HStack(spacing: 14) {
            leading
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - 液态玻璃图标按钮（增强版）
struct LiquidGlassIconButton: View {
    let icon: String
    let color: Color
    var size: CGFloat = 44
    var iconSize: CGFloat = 20
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    // 缓存触觉反馈生成器
    private static let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        Button(action: {
            Self.impactGenerator.impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(color)
                .frame(width: size, height: size)
                .background(
                    ZStack {
                        // 主背景
                        Circle()
                            .fill(colorScheme == .dark ? LiquidGlassTheme.darkBackgroundSecondary : LiquidGlassTheme.lightBackgroundSecondary)

                        // 颜色叠加
                        Circle()
                            .fill(color.opacity(colorScheme == .dark ? 0.18 : 0.12))

                        // 顶部高光
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        colorScheme == .dark ? Color.white.opacity(0.2) : Color.white.opacity(0.7),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )

                        // 边缘高光
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color.white.opacity(0.25), Color.white.opacity(0.05)]
                                        : [Color.white.opacity(0.9), Color.white.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .compositingGroup()
                )
        }
        .buttonStyle(LiquidGlassButtonStyle())
        .shadow(color: color.opacity(0.25), radius: 8, x: 0, y: 4)
        .shadow(color: colorScheme == .dark ? LiquidGlassTheme.darkShadowSecondary : LiquidGlassTheme.lightShadowSecondary, radius: 4, x: 0, y: 2)
    }
}

// MARK: - 液态玻璃胶囊按钮（增强版）
struct LiquidGlassPillButton: View {
    let title: String
    var icon: String? = nil
    var gradient: [Color] = [.pink, .purple]
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    private static let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        Button(action: {
            Self.impactGenerator.impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(
                LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // 主背景
                    Capsule()
                        .fill(colorScheme == .dark ? LiquidGlassTheme.darkBackground : LiquidGlassTheme.lightBackground)

                    // 顶部光泽
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color.white.opacity(0.15) : Color.white.opacity(0.6),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )

                    // 边缘高光
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.22), Color.white.opacity(0.05)]
                                    : [Color.white.opacity(0.85), Color.white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .compositingGroup()
            )
        }
        .buttonStyle(LiquidGlassButtonStyle())
        .shadow(color: gradient.first?.opacity(0.2) ?? .clear, radius: 8, x: 0, y: 4)
        .shadow(color: colorScheme == .dark ? LiquidGlassTheme.darkShadowSecondary : LiquidGlassTheme.lightShadowSecondary, radius: 4, x: 0, y: 2)
    }
}

// MARK: - 液态玻璃标签（增强版）
struct LiquidGlassTag: View {
    let text: String
    var color: Color = .primary
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Capsule()
                        .fill(colorScheme == .dark ? LiquidGlassTheme.darkBackgroundSecondary : LiquidGlassTheme.lightBackgroundSecondary)

                    // 顶部微光
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.5),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )

                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.18), Color.white.opacity(0.04)]
                                    : [Color.white.opacity(0.8), Color.white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
                .compositingGroup()
            )
            .shadow(color: colorScheme == .dark ? LiquidGlassTheme.darkShadowSecondary : LiquidGlassTheme.lightShadowSecondary, radius: 6, x: 0, y: 3)
    }
}

// MARK: - 液态玻璃搜索框（增强版）
struct LiquidGlassSearchField: View {
    @Binding var text: String
    var placeholder: String = "搜索"
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isFocused ? .pink : .secondary)

            TextField(placeholder, text: $text)
                .font(.system(size: 16))
                .focused($isFocused)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // 主背景
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? LiquidGlassTheme.darkBackgroundSecondary : LiquidGlassTheme.lightBackgroundSecondary)

                // 顶部光泽
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.5),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                // 边缘高光/焦点状态
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isFocused
                            ? LinearGradient(colors: [.pink.opacity(0.6), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.15), Color.white.opacity(0.05)]
                                    : [Color.white.opacity(0.7), Color.white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            }
            .compositingGroup()
        )
        .shadow(color: isFocused ? Color.pink.opacity(0.2) : (colorScheme == .dark ? LiquidGlassTheme.darkShadowSecondary : LiquidGlassTheme.lightShadowSecondary), radius: isFocused ? 12 : 8, x: 0, y: isFocused ? 6 : 4)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - 液态玻璃按钮样式
struct LiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 液态玻璃页面背景（增强版）
struct LiquidGlassBackground: View {
    var colors: [Color] = [.pink.opacity(0.12), .purple.opacity(0.1), .blue.opacity(0.08)]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // 基础背景
            Color(colorScheme == .dark ? .systemBackground : .systemGroupedBackground)

            // 渐变光晕
            GeometryReader { geo in
                ZStack {
                    // 顶部光晕
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [colors[0], colors[0].opacity(0.3), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.9
                            )
                        )
                        .frame(width: geo.size.width * 1.6, height: geo.size.height * 0.55)
                        .offset(x: -geo.size.width * 0.25, y: -geo.size.height * 0.12)

                    // 右侧光晕
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [colors[1], colors[1].opacity(0.3), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.7
                            )
                        )
                        .frame(width: geo.size.width * 1.1, height: geo.size.height * 0.45)
                        .offset(x: geo.size.width * 0.35, y: geo.size.height * 0.28)

                    // 底部光晕
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [colors[2], colors[2].opacity(0.2), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.6
                            )
                        )
                        .frame(width: geo.size.width * 1.3, height: geo.size.height * 0.35)
                        .offset(x: -geo.size.width * 0.1, y: geo.size.height * 0.58)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 液态玻璃用户头像
struct LiquidGlassAvatar: View {
    let imageUrl: URL?
    var size: CGFloat = 56
    var fallbackIcon: String = "person.fill"
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Group {
            if let url = imageUrl {
                CachedAsyncImage(url: url, targetSize: CGSize(width: size, height: size)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderView
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [.white.opacity(0.4), .white.opacity(0.1), .clear]
                            : [.white.opacity(0.8), .white.opacity(0.3), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 10, x: 0, y: 5)
    }
    
    private var placeholderView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(.systemGray4), Color(.systemGray5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: fallbackIcon)
                .font(.system(size: size * 0.4))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - View 扩展 - 液态玻璃效果
extension View {
    /// 应用液态玻璃卡片效果
    func liquidGlassCard(cornerRadius: CGFloat = 16) -> some View {
        LiquidGlassCardModifier(cornerRadius: cornerRadius, content: self)
    }
}

private struct LiquidGlassCardModifier<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content
    @Environment(\.colorScheme) var colorScheme
    
    private var modifierBackground: Color {
        colorScheme == .dark
            ? Color(white: 0.15).opacity(0.9)
            : Color(white: 0.97).opacity(0.95)
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(modifierBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 15, x: 0, y: 8)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            LiquidGlassCard {
                Text("液态玻璃卡片")
                    .font(.headline)
            }

            LiquidGlassIconButton(icon: "heart.fill", color: .red) {}

            LiquidGlassPillButton(title: "换一批", icon: "arrow.triangle.2.circlepath") {}

            LiquidGlassTag(text: "热门")
        }
        .padding()
    }
    .background(LiquidGlassBackground())
}
