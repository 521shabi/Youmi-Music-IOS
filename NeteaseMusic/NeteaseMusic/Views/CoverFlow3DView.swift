import SwiftUI

// MARK: - 3D Cover Flow 专辑/歌单浏览视图
struct CoverFlow3DView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @State private var selectedTab = 0  // 0=专辑, 1=歌单
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    
    @State private var albums: [NewAlbum] = []
    @State private var playlists: [RecommendPlaylist] = []
    @State private var isLoading = true
    
    private let musicService = MusicService.shared
    
    // MARK: - 主题相关属性
    private var isStrangerTheme: Bool { themeManager.themeStyle == .strangerThings }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .white }
    
    var body: some View {
        ZStack(alignment: .top) {
            // 背景
            GeometryReader { geometry in
                let screenWidth = geometry.size.width
                let screenHeight = geometry.size.height
                
                ZStack {
                    backgroundView
                    
                    VStack(spacing: 0) {
                        // 顶部占位
                        Color.clear.frame(height: 120)
                        
                        // 3D Cover Flow
                        if isLoading {
                            Spacer()
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Spacer()
                        } else {
                            Spacer()
                            coverFlowSection(screenWidth: screenWidth)
                            Spacer()
                        }
                        
                        Color.clear.frame(height: 140)
                    }
                }
                .frame(width: screenWidth, height: screenHeight)
            }
            .ignoresSafeArea()
            
            // 顶部导航栏 - 放在最上层
            headerView
        }
        .navigationBarHidden(true)
        .task {
            await loadData()
        }
    }
    
    // MARK: - 背景
    private var backgroundView: some View {
        ZStack {
            if isStrangerTheme {
                Color(red: 0.05, green: 0.02, blue: 0.08)
            } else {
                Color.black
            }
            
            if let url = currentCoverURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    if isStrangerTheme {
                        Color(red: 0.05, green: 0.02, blue: 0.08)
                    } else {
                        Color.black
                    }
                }
                .blur(radius: 60)
                .scaleEffect(1.2)
            }
            
            LinearGradient(
                colors: isStrangerTheme 
                    ? [Color(red: 0.05, green: 0.02, blue: 0.08).opacity(0.3), Color(red: 0.05, green: 0.02, blue: 0.08).opacity(0.5), Color(red: 0.05, green: 0.02, blue: 0.08).opacity(0.7)]
                    : [.black.opacity(0.3), .black.opacity(0.5), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var currentCoverURL: URL? {
        if selectedTab == 0, currentIndex < albums.count {
            return albums[currentIndex].picUrl.flatMap { URL(string: $0) }
        } else if selectedTab == 1, currentIndex < playlists.count {
            return playlists[currentIndex].coverUrl.flatMap { URL(string: $0) }
        }
        return nil
    }
    
    // MARK: - 顶部导航
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                
                Spacer()
                
                // 标签选择器
                HStack(spacing: 4) {
                    tabButton(title: "专辑", tab: 0)
                    tabButton(title: "歌单", tab: 1)
                }
                .padding(4)
                .background(Capsule().fill(.ultraThinMaterial))
                
                Spacer()
                
                // 占位，保持布局对称
                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 60)
    }
    
    private func tabButton(title: String, tab: Int) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3)) {
                selectedTab = tab
                let count = tab == 0 ? albums.count : playlists.count
                currentIndex = min(currentIndex, max(0, count - 1))
            }
        }) {
            Text(title)
                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium))
                .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(selectedTab == tab ? (isStrangerTheme ? accentColor.opacity(0.4) : Color.white.opacity(0.25)) : Color.clear)
                )
        }
    }
    
    // MARK: - Cover Flow 区域
    @ViewBuilder
    private func coverFlowSection(screenWidth: CGFloat) -> some View {
        let items = selectedTab == 0 ? albums.count : playlists.count
        
        if items == 0 {
            Text("暂无内容")
                .foregroundColor(.white.opacity(0.6))
        } else {
            VStack(spacing: 24) {
                // 3D 展示区
                GeometryReader { geo in
                    let centerX = geo.size.width / 2
                    let centerY = geo.size.height / 2
                    
                    ZStack {
                        ForEach(0..<items, id: \.self) { index in
                            albumCard(index: index, screenWidth: screenWidth)
                                .position(x: centerX + cardOffsetX(for: index, screenWidth: screenWidth),
                                         y: centerY)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(height: 320)
                .clipped()
                
                // 信息区
                infoView
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(itemCount: items))
        }
    }
    
    // MARK: - 计算卡片X偏移
    private func cardOffsetX(for index: Int, screenWidth: CGFloat) -> CGFloat {
        let indexOffset = CGFloat(index - currentIndex)
        let adjustedOffset = indexOffset + dragOffset / 180
        let spacing: CGFloat = screenWidth < 500 ? 70 : 85
        return adjustedOffset * spacing
    }
    
    // MARK: - 单张专辑卡片
    private func albumCard(index: Int, screenWidth: CGFloat) -> some View {
        let indexOffset = CGFloat(index - currentIndex)
        let adjustedOffset = indexOffset + dragOffset / 180
        
        // 尺寸
        let isPortrait = screenWidth < 500
        let cardWidth: CGFloat = isPortrait ? 140 : 170
        let cardHeight: CGFloat = cardWidth * 1.35
        let spineWidth: CGFloat = isPortrait ? 14 : 18
        
        // 3D 效果 - 减小旋转角度，让未选中的卡片更清晰
        let rotation = adjustedOffset * 40
        let scale: CGFloat = index == currentIndex ? 1.0 : 0.85
        let zIndex = Double(100 - abs(Int(indexOffset)))
        let cardOpacity = max(0.6, 1.0 - abs(adjustedOffset) * 0.15)
        
        let shouldShow = abs(indexOffset) <= 4
        
        return Group {
            if shouldShow {
                NavigationLink(destination: destinationView(for: index)) {
                    HStack(spacing: 0) {
                        // 书脊
                        spineView(index: index, width: spineWidth, height: cardHeight)
                        
                        // 封面
                        coverImage(index: index, width: cardWidth, height: cardHeight)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.5), radius: 12, x: 5, y: 10)
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(scale)
                .rotation3DEffect(
                    .degrees(rotation),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.4
                )
                .zIndex(zIndex)
                .opacity(cardOpacity)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: currentIndex)
                .animation(.interactiveSpring(), value: dragOffset)
            }
        }
    }
    
    // MARK: - 书脊
    private func spineView(index: Int, width: CGFloat, height: CGFloat) -> some View {
        let colors: [Color] = [.red, .orange, .green, .blue, .purple, .pink, .cyan, .mint, .indigo, .yellow]
        let color = colors[index % colors.count]
        
        return Rectangle()
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .overlay(
                Text(itemName(for: index))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(-90))
                    .frame(width: height * 0.9)
                    .lineLimit(1)
            )
    }
    
    // MARK: - 封面图片
    private func coverImage(index: Int, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let url = imageURL(for: index) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(_):
                        placeholderView
                    case .empty:
                        ProgressView().tint(.white)
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
    
    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.4))
            )
    }
    
    // MARK: - 信息区
    private var infoView: some View {
        VStack(spacing: 6) {
            Text(itemName(for: currentIndex))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text(itemSubtitle(for: currentIndex))
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }
    
    // MARK: - 拖动手势
    private func dragGesture(itemCount: Int) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let threshold: CGFloat = 30  // 降低阈值，更容易触发
                let velocity = value.predictedEndTranslation.width - value.translation.width
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    if value.translation.width < -threshold || velocity < -80 {
                        currentIndex = min(currentIndex + 1, itemCount - 1)
                    } else if value.translation.width > threshold || velocity > 80 {
                        currentIndex = max(currentIndex - 1, 0)
                    }
                    dragOffset = 0
                }
                HapticFeedback.light()
            }
    }
    
    // MARK: - 数据获取
    private func imageURL(for index: Int) -> URL? {
        if selectedTab == 0, index < albums.count {
            return albums[index].picUrl.flatMap { URL(string: $0) }
        } else if selectedTab == 1, index < playlists.count {
            return playlists[index].coverUrl.flatMap { URL(string: $0) }
        }
        return nil
    }
    
    private func itemName(for index: Int) -> String {
        if selectedTab == 0, index < albums.count {
            return albums[index].name
        } else if selectedTab == 1, index < playlists.count {
            return playlists[index].name
        }
        return ""
    }
    
    private func itemSubtitle(for index: Int) -> String {
        if selectedTab == 0, index < albums.count {
            return albums[index].artistName
        } else if selectedTab == 1, index < playlists.count {
            let count = playlists[index].playCountText
            return count.isEmpty ? "" : "播放 \(count)"
        }
        return ""
    }
    
    @ViewBuilder
    private func destinationView(for index: Int) -> some View {
        if selectedTab == 0, index < albums.count {
            AlbumDetailView(albumId: albums[index].id, albumName: albums[index].name)
        } else if selectedTab == 1, index < playlists.count {
            PlaylistDetailView(
                playlistId: playlists[index].id,
                playlistName: playlists[index].name,
                coverUrl: playlists[index].coverUrl
            )
        } else {
            EmptyView()
        }
    }
    
    // MARK: - 加载数据
    private func loadData() async {
        isLoading = true
        
        do {
            async let albumsTask = musicService.getNewAlbums(area: "ALL", limit: 20)
            async let playlistsTask = musicService.getPersonalized(limit: 20)
            
            albums = try await albumsTask
            playlists = try await playlistsTask
            currentIndex = 0
        } catch {
            #if DEBUG
            print("加载数据失败: \(error)")
            #endif
        }
        
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        CoverFlow3DView()
    }
}
