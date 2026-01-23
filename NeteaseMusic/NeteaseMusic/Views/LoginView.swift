import SwiftUI

// MARK: - 触觉反馈工具类
enum HapticFeedback {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)

    static func light() {
        lightGenerator.impactOccurred()
    }

    static func medium() {
        mediumGenerator.impactOccurred()
    }
}

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var loginMethod: LoginMethod = .captcha
    @State private var showMainView = false
    
    enum LoginMethod {
        case password
        case captcha
        case qrcode
        case cookie
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Logo
                Image(systemName: "music.note.list")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                    .padding(.top, 40)
                
                Text("Youmi")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // 登录方式选择
                Picker("登录方式", selection: $loginMethod) {
                    Text("验证码").tag(LoginMethod.captcha)
                    Text("密码").tag(LoginMethod.password)
                    Text("Cookie").tag(LoginMethod.cookie)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)
                
                switch loginMethod {
                case .password:
                    passwordLoginView
                case .captcha:
                    captchaLoginView
                case .qrcode:
                    qrCodeLoginView
                case .cookie:
                    cookieLoginView
                }
                
                Spacer()
                
                // 跳过登录
                Button(action: {
                    showMainView = true
                }) {
                    Text("跳过登录，直接进入")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 30)
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: Binding(
                get: { authViewModel.isLoggedIn || showMainView },
                set: { _ in }
            )) {
                MainTabView()
                    .environmentObject(authViewModel)
            }
        }
    }
    
    // MARK: - 密码登录视图
    private var passwordLoginView: some View {
        LoginForm(viewModel: authViewModel)
    }
    
    // MARK: - 验证码登录视图
    private var captchaLoginView: some View {
        CaptchaLoginForm(viewModel: authViewModel)
    }
    
    // MARK: - Cookie 登录视图
    private var cookieLoginView: some View {
        CookieLoginForm(viewModel: authViewModel)
    }

    // MARK: - 二维码登录视图
    private var qrCodeLoginView: some View {
        VStack(spacing: 16) {
            if let qrImage = authViewModel.qrImage {
                QRCodeImageView(qrImage: qrImage)
                qrStatusView
            } else {
                generateQRButton
            }

            if let error = authViewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Text("请使用网易云音乐 App 扫码登录")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .onDisappear {
            authViewModel.stopQRStatusCheck()
        }
    }

    private var generateQRButton: some View {
        Button(action: {
            Task { await authViewModel.startQRLogin() }
        }) {
            if authViewModel.isLoading {
                ProgressView()
            } else {
                VStack {
                    Image(systemName: "qrcode")
                        .font(.system(size: 80))
                    Text("点击生成二维码")
                        .padding(.top, 10)
                }
            }
        }
        .foregroundColor(.gray)
        .frame(width: 200, height: 200)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - 二维码状态视图
    @ViewBuilder
    private var qrStatusView: some View {
        switch authViewModel.qrStatus {
        case .waiting:
            HStack {
                ProgressView().scaleEffect(0.8)
                Text("等待扫码...")
            }
            .foregroundColor(.gray)
        case .scanned:
            HStack {
                Image(systemName: "checkmark.circle").foregroundColor(.green)
                Text("已扫码，请在手机上确认")
            }
            .foregroundColor(.green)
        case .confirmed:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("登录成功！")
            }
            .foregroundColor(.green)
        case .expired:
            VStack {
                Text("二维码已过期").foregroundColor(.red)
                Button("重新生成") {
                    Task { await authViewModel.startQRLogin() }
                }
                .foregroundColor(.blue)
            }
        }
    }
}

// MARK: - 二维码图片视图
struct QRCodeImageView: View {
    let qrImage: String

    var body: some View {
        Group {
            if qrImage.hasPrefix("data:image"),
               let uiImage = decodeBase64Image(qrImage) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                AsyncImage(url: URL(string: qrImage)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
            }
        }
        .frame(width: 200, height: 200)
    }

    private func decodeBase64Image(_ base64String: String) -> UIImage? {
        let base64Data = base64String.replacingOccurrences(of: "data:image/png;base64,", with: "")
        guard let data = Data(base64Encoded: base64Data) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - 动画输入框
struct AnimatedInputField: View {
    let placeholder: String
    let icon: String
    @Binding var text: String
    var isSecure: Bool = false
    
    @FocusState private var isFocused: Bool
    
    private var shouldFloat: Bool {
        isFocused || !text.isEmpty
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color.red : Color.clear, lineWidth: 2)
                )
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(isFocused ? .red : .gray)
                    .frame(width: 20)
                
                ZStack(alignment: .leading) {
                    Text(placeholder)
                        .foregroundColor(shouldFloat ? .red : .gray)
                        .font(shouldFloat ? .caption : .body)
                        .offset(y: shouldFloat ? -12 : 0)
                    
                    if isSecure {
                        SecureField("", text: $text)
                            .focused($isFocused)
                            .offset(y: shouldFloat ? 6 : 0)
                    } else {
                        TextField("", text: $text)
                            .keyboardType(.phonePad)
                            .focused($isFocused)
                            .offset(y: shouldFloat ? 6 : 0)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 56)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .onTapGesture {
            isFocused = true
        }
    }
}

// MARK: - 按照截图设计的底部导航栏
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @Binding var isSearchMode: Bool
    var animation: Namespace.ID
    @StateObject private var audioPlayer = AudioPlayer.shared
    @State private var showPlayer = false

    // Tab 配置数据
    private static let tabItems: [(icon: String, title: String)] = [
        ("house.fill", "主页"),
        ("square.grid.2x2", "新发现"),
        ("person.fill", "我的"),
        ("gearshape.fill", "设置")
    ]

    private var showMiniPlayer: Bool {
        audioPlayer.currentTrack != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if showMiniPlayer {
                MiniPlayerBar(showPlayer: $showPlayer)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 底部 Tab 栏
            tabBarContent
        }
        .background(.clear)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
        }
    }
    
    // MARK: - Tab 栏内容
    private var tabBarContent: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(Self.tabItems.enumerated()), id: \.offset) { index, item in
                    AppleMusicTabButton(
                        icon: item.icon,
                        title: item.title,
                        isSelected: selectedTab == index
                    ) {
                        selectTab(index)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 16)
            .padding(.vertical, 8)
            .background(
                EnhancedLiquidGlassBackground(cornerRadius: 32)
            )

            // 搜索按钮
            Button(action: {
                HapticFeedback.light()
                isSearchMode = true
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 56, height: 56)
            }
            .background(
                EnhancedLiquidGlassCircleBackground()
            )
            .buttonStyle(LiquidButtonStyle())
            .padding(.leading, 12)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, -20)
    }

    private func selectTab(_ index: Int) {
        HapticFeedback.light()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            selectedTab = index
        }
    }
}

// MARK: - Apple Music 风格 Tab 按钮
struct AppleMusicTabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? .red : .primary)
                
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .red : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(LiquidButtonStyle())
    }
}

// MARK: - 增强版液态玻璃背景（圆角矩形）
struct EnhancedLiquidGlassBackground: View {
    var cornerRadius: CGFloat = 32
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // 层 1: 模糊材质
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
            
            // 层 2: 半透明背景
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    colorScheme == .dark
                        ? Color(white: 0.1).opacity(0.7)
                        : Color(white: 0.98).opacity(0.75)
                )
            
            // 层 3: 顶部高光渐变
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.18), Color.white.opacity(0.03), .clear]
                            : [Color.white.opacity(0.9), Color.white.opacity(0.4), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                )
            
            // 层 4: 边缘高光描边
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.4), Color.white.opacity(0.12), Color.white.opacity(0.05)]
                            : [Color.white.opacity(1.0), Color.white.opacity(0.6), Color.white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            
            // 层 5: 内边框发光
            RoundedRectangle(cornerRadius: cornerRadius - 1.5)
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.06)
                        : Color.white.opacity(0.35),
                    lineWidth: 0.5
                )
                .padding(1.5)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 25, x: 0, y: 12)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 10, x: 0, y: 5)
    }
}

// MARK: - 增强版液态玻璃背景（圆形）
struct EnhancedLiquidGlassCircleBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // 模糊材质
            Circle()
                .fill(.ultraThinMaterial)
            
            // 半透明背景
            Circle()
                .fill(
                    colorScheme == .dark
                        ? Color(white: 0.1).opacity(0.7)
                        : Color(white: 0.98).opacity(0.75)
                )
            
            // 顶部高光
            Circle()
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.25), .clear]
                            : [Color.white.opacity(0.9), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            
            // 边缘高光
            Circle()
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.4), Color.white.opacity(0.1)]
                            : [Color.white.opacity(1.0), Color.white.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            
            // 内发光
            Circle()
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.06)
                        : Color.white.opacity(0.3),
                    lineWidth: 0.5
                )
                .padding(1.5)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 15, x: 0, y: 8)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 5, x: 0, y: 3)
    }
}

// MARK: - 迷你播放器条
struct MiniPlayerBar: View {
    @Binding var showPlayer: Bool
    @StateObject private var audioPlayer = AudioPlayer.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            HapticFeedback.light()
            showPlayer = true
        }) {
            HStack(spacing: 10) {
                // 封面
                if let coverUrl = audioPlayer.currentTrack?.coverUrl,
                   let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color(.systemGray5))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.3), lineWidth: 0.5)
                    )
                }
                
                // 歌曲信息
                VStack(alignment: .leading, spacing: 1) {
                    Text(audioPlayer.currentTrack?.name ?? "未播放")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(audioPlayer.currentTrack?.artistName ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                // 播放按钮
                Button(action: {
                    HapticFeedback.light()
                    audioPlayer.togglePlayPause()
                }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(LiquidButtonStyle())
                
                // 下一首按钮
                Button(action: {
                    HapticFeedback.light()
                    audioPlayer.playNext()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(LiquidButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.3))
                    )
            )
            .padding(.horizontal, 12)
            .padding(.top, -60)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 首页按钮（支持长按弹出搜索）
struct LiquidGlassHomeButtonWithSearch: View {
    let isSelected: Bool
    @Binding var showSearchPopup: Bool
    let action: () -> Void
    let onSearchTap: () -> Void
    
    var body: some View {
        ZStack(alignment: .top) {
            // 搜索弹窗
            if showSearchPopup {
                SearchPopupButton(onTap: onSearchTap)
                    .offset(y: -60)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5, anchor: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.5, anchor: .bottom).combined(with: .opacity)
                    ))
            }
            
            // 首页按钮
            Button(action: {
                HapticFeedback.light()
                action()
            }) {
                Image(systemName: isSelected ? "house.fill" : "house")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 52, height: 52)
                    .liquidGlassCircle()
            }
            .buttonStyle(LiquidButtonStyle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in
                        HapticFeedback.medium()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showSearchPopup.toggle()
                        }
                    }
            )
        }
    }
}

// MARK: - 搜索弹窗按钮
struct SearchPopupButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticFeedback.light()
            onTap()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                Text("搜索")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .liquidGlassCapsule()
        }
        .buttonStyle(LiquidButtonStyle())
    }
}

// MARK: - 紧凑版搜索框
struct LiquidGlassSearchBarCompact: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticFeedback.light()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("搜索")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .liquidGlassCapsule()
        }
        .buttonStyle(LiquidButtonStyle())
    }
}

// MARK: - 导航按钮
struct LiquidGlassNavButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticFeedback.light()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isSelected ? .pink : .primary)
                .frame(width: 46, height: 46)
                .liquidGlassCircle()
        }
        .buttonStyle(LiquidButtonStyle())
    }
}

// MARK: - 液体玻璃按钮样式
struct LiquidButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 缩放按钮样式
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 共享登录表单组件
struct LoginForm: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var phone = ""
    @State private var password = ""
    var onSuccess: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            // 手机号输入
            AnimatedInputField(
                placeholder: "手机号",
                icon: "phone",
                text: $phone
            )
            .padding(.horizontal, 30)
            
            // 密码输入
            AnimatedInputField(
                placeholder: "密码",
                icon: "lock",
                text: $password,
                isSecure: true
            )
            .padding(.horizontal, 30)
            
            // 错误信息
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 30)
            }
            
            // 登录按钮
            Button(action: {
                Task {
                    await viewModel.loginWithPhone(phone: phone, password: password)
                    if viewModel.isLoggedIn {
                        onSuccess?()
                    }
                }
            }) {
                ZStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("登录")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [Color.red, Color.red.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(27)
                .shadow(color: Color.red.opacity(0.3), radius: 10, y: 5)
            }
            .padding(.horizontal, 30)
            .padding(.top, 10)
            .disabled(phone.isEmpty || password.isEmpty || viewModel.isLoading)
            .opacity(phone.isEmpty || password.isEmpty ? 0.6 : 1)
            .scaleEffect(viewModel.isLoading ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.isLoading)
            
            // 提示
            Text("请确保已部署 API 服务")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top, 5)
        }
    }
}

// MARK: - 验证码登录表单组件
struct CaptchaLoginForm: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var phone = ""
    @State private var captcha = ""
    var onSuccess: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            // 手机号输入
            AnimatedInputField(
                placeholder: "手机号",
                icon: "phone",
                text: $phone
            )
            .padding(.horizontal, 30)
            
            // 验证码输入和发送按钮
            HStack(spacing: 12) {
                AnimatedInputField(
                    placeholder: "验证码",
                    icon: "number",
                    text: $captcha
                )
                
                // 发送验证码按钮
                Button(action: {
                    Task {
                        await viewModel.sendCaptcha(phone: phone)
                    }
                }) {
                    Text(viewModel.captchaCountdown > 0 ? "\(viewModel.captchaCountdown)s" : "获取验证码")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(canSendCaptcha ? .white : .gray)
                        .frame(width: 100, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(canSendCaptcha ? Color.red : Color(.systemGray5))
                        )
                }
                .disabled(!canSendCaptcha || viewModel.isLoading)
            }
            .padding(.horizontal, 30)
            
            // 错误信息
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 30)
            }
            
            // 登录按钮
            Button(action: {
                Task {
                    await viewModel.loginWithCaptcha(phone: phone, captcha: captcha)
                    if viewModel.isLoggedIn {
                        onSuccess?()
                    }
                }
            }) {
                ZStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("登录")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [Color.red, Color.red.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(27)
                .shadow(color: Color.red.opacity(0.3), radius: 10, y: 5)
            }
            .padding(.horizontal, 30)
            .padding(.top, 10)
            .disabled(phone.isEmpty || captcha.isEmpty || viewModel.isLoading)
            .opacity(phone.isEmpty || captcha.isEmpty ? 0.6 : 1)
            .scaleEffect(viewModel.isLoading ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.isLoading)
            
            // 提示
            Text("验证码将发送到您的手机")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top, 5)
        }
    }
    
    private var canSendCaptcha: Bool {
        !phone.isEmpty && viewModel.captchaCountdown == 0
    }
}

// MARK: - Cookie 登录表单组件
struct CookieLoginForm: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var cookie = ""
    @State private var showHelp = false
    var onSuccess: (() -> Void)? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Cookie 输入
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Cookie")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button(action: { showHelp.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "questionmark.circle")
                                Text("如何获取")
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 30)
                    
                    TextEditor(text: $cookie)
                        .frame(height: 100)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal, 30)
                }
                
                // 帮助说明
                if showHelp {
                    cookieHelpView
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // 错误信息
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal, 30)
                }
                
                // 登录按钮
                Button(action: {
                    Task {
                        await viewModel.loginWithCookie(cookie: cookie.trimmingCharacters(in: .whitespacesAndNewlines))
                        if viewModel.isLoggedIn {
                            onSuccess?()
                        }
                    }
                }) {
                    ZStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("登录")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(27)
                    .shadow(color: Color.red.opacity(0.3), radius: 10, y: 5)
                }
                .padding(.horizontal, 30)
                .disabled(cookie.isEmpty || viewModel.isLoading)
                .opacity(cookie.isEmpty ? 0.6 : 1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showHelp)
    }
    
    // MARK: - Cookie 获取帮助视图
    private var cookieHelpView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(" Cookie 获取步骤")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 10) {
                helpStepView(
                    step: 1,
                    title: "打开网易云音乐网页版",
                    detail: "在电脑浏览器访问 music.163.com 并登录账号"
                )
                
                helpStepView(
                    step: 2,
                    title: "打开开发者工具",
                    detail: "按 F12 或右键选择“检查”"
                )
                
                helpStepView(
                    step: 3,
                    title: "找到 Cookies",
                    detail: "点击 Application(应用) → Cookies → music.163.com"
                )
                
                helpStepView(
                    step: 4,
                    title: "复制 MUSIC_U",
                    detail: "找到名为 MUSIC_U 的条目，复制其值"
                )
            }
            
            // 提示
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("只需复制 MUSIC_U 的值即可，无需全部 Cookie")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal, 30)
    }
    
    private func helpStepView(step: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(step)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.red))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 登录弹窗
struct LoginSheetView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var loginMethod: LoginView.LoginMethod = .captcha
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Logo
                Image(systemName: "music.note.list")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                    .padding(.top, 40)
                
                Text("Youmi")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // 登录方式选择
                Picker("登录方式", selection: $loginMethod) {
                    Text("验证码").tag(LoginView.LoginMethod.captcha)
                    Text("密码").tag(LoginView.LoginMethod.password)
                    Text("Cookie").tag(LoginView.LoginMethod.cookie)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)
                
                switch loginMethod {
                case .captcha:
                    // 验证码登录
                    CaptchaLoginForm(viewModel: authViewModel) {
                        dismiss()
                    }
                    .padding(.top, 10)
                case .password:
                    // 密码登录表单
                    LoginForm(viewModel: authViewModel) {
                        dismiss()
                    }
                    .padding(.top, 10)
                case .qrcode:
                    // 二维码登录
                    qrCodeLoginView
                        .padding(.top, 10)
                case .cookie:
                    // Cookie 登录
                    CookieLoginForm(viewModel: authViewModel) {
                        dismiss()
                    }
                    .padding(.top, 10)
                }
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onChange(of: authViewModel.isLoggedIn) { _, newValue in
                if newValue {
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - 二维码登录视图
    private var qrCodeLoginView: some View {
        VStack(spacing: 16) {
            if let qrImage = authViewModel.qrImage {
                QRCodeImageView(qrImage: qrImage)
                qrStatusView
            } else {
                generateQRButton
            }

            if let error = authViewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Text("请使用网易云音乐 App 扫码登录")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .onDisappear {
            authViewModel.stopQRStatusCheck()
        }
    }

    private var generateQRButton: some View {
        Button(action: {
            Task { await authViewModel.startQRLogin() }
        }) {
            if authViewModel.isLoading {
                ProgressView()
            } else {
                VStack {
                    Image(systemName: "qrcode")
                        .font(.system(size: 80))
                    Text("点击生成二维码")
                        .padding(.top, 10)
                }
            }
        }
        .foregroundColor(.gray)
        .frame(width: 200, height: 200)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - 二维码状态视图
    @ViewBuilder
    private var qrStatusView: some View {
        switch authViewModel.qrStatus {
        case .waiting:
            HStack {
                ProgressView().scaleEffect(0.8)
                Text("等待扫码...")
            }
            .foregroundColor(.gray)
        case .scanned:
            HStack {
                Image(systemName: "checkmark.circle").foregroundColor(.green)
                Text("已扫码，请在手机上确认")
            }
            .foregroundColor(.green)
        case .confirmed:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("登录成功！")
            }
            .foregroundColor(.green)
        case .expired:
            VStack {
                Text("二维码已过期").foregroundColor(.red)
                Button("重新生成") {
                    Task { await authViewModel.startQRLogin() }
                }
                .foregroundColor(.blue)
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
