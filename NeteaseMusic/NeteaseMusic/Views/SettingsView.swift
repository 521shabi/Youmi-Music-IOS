import SwiftUI

// MARK: - Apple Music 液态玻璃风格设置页
struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // 外观设置
                liquidGlassAppearanceSection

                // 关于信息
                liquidGlassAboutSection
                
                // 赞助支持
                liquidGlassSponsorSection
            }
            .padding(.bottom, 120)
        }
        .background(LiquidGlassBackground(colors: [.purple.opacity(0.08), .blue.opacity(0.06), .cyan.opacity(0.04)]))
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - 液态玻璃外观设置
    private var liquidGlassAppearanceSection: some View {
        LiquidGlassSection(title: "外观") {
            VStack(alignment: .leading, spacing: 16) {
                Text("外观模式")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                HStack(spacing: 12) {
                    ForEach(AppearanceMode.allCases) { mode in
                        LiquidGlassAppearanceButton(
                            mode: mode,
                            isSelected: themeManager.appearanceMode == mode
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                themeManager.appearanceMode = mode
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - 液态玻璃关于信息
    private var liquidGlassAboutSection: some View {
        LiquidGlassSection(title: "关于") {
            VStack(spacing: 0) {
                LiquidGlassSettingsRow(title: "版本", value: "1.0.0")
                
                LiquidGlassDivider()
                
                LiquidGlassSettingsRow(title: "开发者", value: "Youmi Music")
            }
        }
    }
    
    // MARK: - 赞助支持
    private var liquidGlassSponsorSection: some View {
        LiquidGlassSection(title: "赞助支持") {
            VStack(spacing: 16) {
                // 说明文字
                VStack(spacing: 8) {
                    Text("不强求，自愿支持 ❤️")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("如果 Youmi 对你有帮助，可以请开发者喝一杯咖啡")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)
                
                // 赞赏码图片
                Image("SponsorQRCode")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                
                // 提示文字
                Text("微信扫码赞赏")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 液态玻璃外观模式按钮
struct LiquidGlassAppearanceButton: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    private var buttonBackground: Color {
        if isSelected {
            return colorScheme == .dark
                ? Color(white: 0.25).opacity(0.95)
                : Color.white.opacity(0.95)
        } else {
            return colorScheme == .dark
                ? Color(white: 0.18).opacity(0.9)
                : Color(white: 0.96).opacity(0.9)
        }
    }
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            VStack(spacing: 10) {
                ZStack {
                    // 背景
                    RoundedRectangle(cornerRadius: 14)
                        .fill(buttonBackground)
                    
                    // 选中状态彩色光晕
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                RadialGradient(
                                    colors: [Color.accentColor.opacity(0.2), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 40
                                )
                            )
                    }
                    
                    // 边框
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isSelected
                                ? Color.accentColor.opacity(0.5)
                                : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)),
                            lineWidth: isSelected ? 2 : 1
                        )
                    
                    Image(systemName: mode.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .frame(width: 72, height: 52)
                .shadow(color: isSelected ? Color.accentColor.opacity(0.2) : .black.opacity(colorScheme == .dark ? 0.15 : 0.05), radius: 10, x: 0, y: 5)

                Text(mode.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
        }
        .buttonStyle(LiquidGlassButtonStyle())
    }
}

// MARK: - 液态玻璃设置行
struct LiquidGlassSettingsRow: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    NavigationView {
        SettingsView()
            .environmentObject(ThemeManager.shared)
    }
}
