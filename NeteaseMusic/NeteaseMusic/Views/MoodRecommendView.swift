import SwiftUI

// MARK: - 情感推荐视图
struct MoodRecommendView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var viewModel = MoodRecommendViewModel()
    
    @State private var breathe = false
    @State private var quoteIndex = 0
    @State private var expandedSongId: Int? = nil
    @State private var quoteTimer: Timer?
    
    // MARK: - 主题相关属性
    private var isStrangerTheme: Bool { themeManager.themeStyle == .strangerThings }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .purple }
    private var secondaryAccent: Color { isStrangerTheme ? Color(red: 0.2, green: 0.6, blue: 1.0) : .blue }
    
    private let quotes = [
        "有些歌，听着听着就哭了",
        "总有一首歌，让你想起某个人",
        "音乐是时光的容器",
        "在旋律中，找回那些遗失的情绪"
    ]
    
    var body: some View {
        ZStack {
            // 背景
            backgroundView
            
            VStack(spacing: 0) {
                // 顶栏
                topBar
                
                if viewModel.isLoading && viewModel.songs.isEmpty {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                    Text("正在为你寻找扎心旋律...")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 16)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            // 标题区
                            headerSection
                            
                            // 歌曲列表
                            songList
                        }
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                breathe = true
            }
            startQuoteTimer()
            Task {
                await viewModel.loadSongs()
            }
        }
        .onDisappear {
            quoteTimer?.invalidate()
            quoteTimer = nil
        }
    }
    
    // MARK: - 背景
    private var backgroundView: some View {
        ZStack {
            if isStrangerTheme {
                Color(red: 0.05, green: 0.02, blue: 0.08)
                
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 400, height: 400)
                    .blur(radius: 100)
                    .offset(y: -200)
                
                Circle()
                    .fill(secondaryAccent.opacity(0.1))
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: 100, y: 300)
            } else {
                Color(red: 0.06, green: 0.07, blue: 0.12)
                
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 400, height: 400)
                    .blur(radius: 100)
                    .offset(y: -200)
                
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: 100, y: 300)
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - 顶栏
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                    .scaleEffect(breathe ? 1.3 : 0.8)
                
                Text("沉浸模式")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
    
    // MARK: - 标题区
    private var headerSection: some View {
        VStack(spacing: 16) {
            Text("深 夜 电 台")
                .font(.system(size: 13))
                .tracking(3)
                .foregroundColor(.white.opacity(0.5))
            
            Text("那些扎心的旋律")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 100, height: 1)
            
            Text(quotes[quoteIndex])
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .animation(.easeInOut, value: quoteIndex)
            
            Text("陈奕迅")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.15)))
        }
        .padding(.top, 20)
    }
    
    // MARK: - 歌曲列表
    private var songList: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.songs) { song in
                MoodSongRow(
                    song: song,
                    isExpanded: expandedSongId == song.id,
                    onTap: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            expandedSongId = expandedSongId == song.id ? nil : song.id
                        }
                        if expandedSongId == song.id {
                            Task {
                                await viewModel.loadLyric(for: song)
                            }
                        }
                    },
                    onPlay: {
                        viewModel.playSong(song)
                    }
                )
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func startQuoteTimer() {
        quoteTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            quoteIndex = (quoteIndex + 1) % quotes.count
        }
    }
}

// MARK: - 歌曲行视图
struct MoodSongRow: View {
    let song: MoodSongItem
    let isExpanded: Bool
    let onTap: () -> Void
    let onPlay: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 主行
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // 封面
                    AsyncImage(url: URL(string: song.coverUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure(_), .empty:
                            ZStack {
                                LinearGradient(colors: [.purple.opacity(0.6), .blue.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                Image(systemName: "music.note")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        @unknown default:
                            Color.gray.opacity(0.3)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    // 信息
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(song.album)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(song.moodColor)
                                .frame(width: 5, height: 5)
                            Text(song.mood)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    
                    Spacer()
                    
                    // 展开指示器
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                    
                    // 播放按钮
                    Button(action: onPlay) {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                            )
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(isExpanded ? 0.1 : 0.05))
                )
            }
            .buttonStyle(.plain)
            
            // 歌词区域
            if isExpanded {
                lyricSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
// MARK: - 歌词区域
    private var lyricSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 歌曲解读
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.yellow.opacity(0.8))
                    Text("歌曲解读")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Text(getSongMeaning(song.name))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.65))
                    .lineSpacing(5)
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // 经典歌词
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 13))
                        .foregroundColor(.purple.opacity(0.7))
                    Text("经典歌词")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                if song.isLoadingLyric {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.white.opacity(0.5))
                        Spacer()
                    }
                    .padding(.vertical, 16)
                } else if let lyrics = song.lyricPreview, !lyrics.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lyrics, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 14, design: .serif))
                                .foregroundColor(.white.opacity(0.75))
                                .italic()
                        }
                    }
                } else {
                    Text("暂无歌词")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            
            // 歌词含义
            if let lyrics = song.lyricPreview, !lyrics.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.1))
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.pink.opacity(0.7))
                        Text("歌词含义")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Text(getLyricMeaning(song.name))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.65))
                        .lineSpacing(5)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .padding(.horizontal, 14)
        .padding(.top, -6)
        .padding(.bottom, 8)
    }
    
    // MARK: - 歌曲解读
    private func getSongMeaning(_ name: String) -> String {
        switch name {
        case "富士山下":
            return "这首歌是《爱情转移》的粤语版，讲述一段无法开花结果的感情。富士山下的雪，美丽却短暂，就像那段错过的缘分。歌曲表达的是放手后的释怀，明白有些人只能陆续的过客。"
        case "好久不见":
            return "一封写给旧爱的信，希望在最熟悉的街角偶遇。明知道回不去，却忍不住幻想重逢的场景。这种思念不是要复合，而是希望知道你还好。"
        case "十年":
            return "讲述十年的时间足以改变一切，曾经的爱人变成朋友。这首歌的核心是“释怀”，不是遗忘，而是学会用另一种方式去爱一个人。"
        case "淘汰":
            return "为周杰伦电影《不能说的秘密》创作的主题曲。讲述被爱情淘汰的心碎，当一个人不再爱你，你所有的付出都变得毫无意义。"
        case "你的背包":
            return "一个关于遗憾的故事。背包里装着曾经的回忆，即使分开了，还是会在日常物件中想起对方。这种遗憾不是想要恶补，而是对过去的怀念。"
        case "孤勇者":
            return "为动漫《英雄联盟》创作，鼓励每个普通人勇敢做自己。即使没有人在意，也要坚定地走自己的路。每个孤独战斗的人都是英雄。"
        case "我们":
            return "为电影《后来的我们》创作的主题曲。讲述曾经相爱的两个人，在时光中渐行渐远。“我们”曾是最美的词，如今只剩下“你”和“我”。"
        case "K歌之王":
            return "一个在KTV唱情歌却无法表达真实感情的人。表面上是情歌之王，内心却极度孤独。反映现代人的情感困境，能唱却不能说。"
        case "浮夸":
            return "描绘一个渴望被看见的人，用夸张的方式引起注意。内心的孤独和挣扎，化为表面的张扬。每个“浮夸”的人，可能只是想被认可。"
        case "单车":
            return "一首写给父亲的歌，回忆小时候父亲骑单车载自己的温暖时光。表达对父爱的感恩，虽然父亲不善言辞，但爱一直都在。"
        default:
            return "这首歌讲述了一个动人的故事..."
        }
    }
    
    // MARK: - 歌词含义
    private func getLyricMeaning(_ name: String) -> String {
        switch name {
        case "富士山下":
            return "「谁能凭爱意要富士山私有」——富士山是共有的美景，就像美好的回忆，不能独占。爱一个人，不一定要拥有。"
        case "好久不见":
            return "「我多么想和你见一面，看看你最近改变」——这不是琖精，而是希望知道你还好。思念一个人，有时只是想确认他还幸福。"
        case "十年":
            return "「十年之后，我们是朋友，还可以问候」——曾经最亲密的人变成最熟悉的陌生人，但能保持朋友的身份，也是一种成熟。"
        case "淘汰":
            return "「被淘汰的人，是多么想变成那淘汰别人的人」——在爱情里被抛弃的人，多希望自己也能有选择的权利。"
        case "你的背包":
            return "「你的背包，让我走得好累」——背包里装的是曾经的回忆，放不下过去，每一步都很沉重。"
        case "孤勇者":
            return "「谁说站在光里的才算英雄」——英雄不一定要被粉墨登场，默默坚守的普通人，同样伟大。"
        case "我们":
            return "「我最大的遗憾，是你的遗憾与我有关」——不是后悔爱过，而是后悔让你因我而有遗憾。"
        case "K歌之王":
            return "「我唱得不够动人，你别睡」——拼命想表达爱意，对方却无动于衷。歌唱得再好，也打动不了不爱你的人。"
        case "浮夸":
            return "「其实怀着容易受傷的胃，其实我也渴望被嫣媚」——外表再强的人，内心也渴望被理解和关心。"
        case "单车":
            return "「难离弃的其实也有看着我得到」——父亲不会说爱，但会用行动证明一切。那些不说出口的爱，都在默默的陨伴里。"
        default:
            return "每一句歌词都有它的故事..."
        }
    }
}

// MARK: - ViewModel
@MainActor
class MoodRecommendViewModel: ObservableObject {
    @Published var songs: [MoodSongItem] = []
    @Published var isLoading = false
    
    private let musicService = MusicService.shared
    private let audioPlayer = AudioPlayer.shared
    
    // 陈奕迅经典歌曲列表
    private let songList = [
        ("富士山下", "释怀"),
        ("好久不见", "思念"),
        ("十年", "怀念"),
        ("淘汰", "心碎"),
        ("你的背包", "遗憾"),
        ("孤勇者", "勇气"),
        ("我们", "回忆"),
        ("K歌之王", "孤独"),
        ("浮夸", "挣扎"),
        ("单车", "温暖"),
    ]
    
    func loadSongs() async {
        isLoading = true
        
        var loadedSongs: [MoodSongItem] = []
        
        for (name, mood) in songList {
            do {
                // 搜索歌曲
                let results = try await musicService.search(keyword: "陈奕迅 \(name)", limit: 1)
                if let result = results.first {
                    // 获取歌曲详情（包含封面）
                    let details = try await musicService.getSongDetail(ids: [result.id])
                    if let detail = details.first {
                        let coverUrl = detail.al?.picUrl ?? ""
                        let album = detail.al?.name ?? result.album?.name ?? ""
                        
                        let item = MoodSongItem(
                            id: result.id,
                            name: name,
                            artist: "陈奕迅",
                            album: album,
                            coverUrl: coverUrl,
                            mood: mood
                        )
                        loadedSongs.append(item)
                    }
                }
            } catch {
                // 加载失败，使用占位数据
                let item = MoodSongItem(
                    id: name.hashValue,
                    name: name,
                    artist: "陈奕迅",
                    album: "",
                    coverUrl: "",
                    mood: mood
                )
                loadedSongs.append(item)
            }
        }
        
        songs = loadedSongs
        isLoading = false
    }
    
    func loadLyric(for song: MoodSongItem) async {
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        
        songs[index].isLoadingLyric = true
        
        do {
            let lyric = try await musicService.getLyric(id: song.id)
            let lines = parseLyricPreview(lyric)
            songs[index].lyricPreview = lines
        } catch {
            songs[index].lyricPreview = []
        }
        
        songs[index].isLoadingLyric = false
    }
    
    func playSong(_ song: MoodSongItem) {
        Task {
            do {
                let details = try await musicService.getSongDetail(ids: [song.id])
                if let track = details.first {
                    await audioPlayer.play(track: track)
                }
            } catch {
                #if DEBUG
                print("播放失败: \(error)")
                #endif
            }
        }
    }
    
    // 解析歌词预览（取几行精华）
    private func parseLyricPreview(_ lyric: String) -> [String] {
        let lines = lyric.components(separatedBy: "\n")
        var result: [String] = []
        
        for line in lines {
            // 去除时间标签 [00:00.00]
            let cleanLine = line.replacingOccurrences(of: "\\[\\d+:\\d+\\.?\\d*\\]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            
            // 过滤空行和作词作曲等信息
            if !cleanLine.isEmpty &&
               !cleanLine.contains("作词") &&
               !cleanLine.contains("作曲") &&
               !cleanLine.contains("编曲") &&
               !cleanLine.contains("制作") &&
               cleanLine.count > 2 {
                result.append(cleanLine)
            }
            
            // 最多取6行
            if result.count >= 6 {
                break
            }
        }
        
        return result
    }
}

// MARK: - 数据模型
struct MoodSongItem: Identifiable {
    let id: Int
    let name: String
    let artist: String
    let album: String
    let coverUrl: String
    let mood: String
    var lyricPreview: [String]? = nil
    var isLoadingLyric: Bool = false
    
    var moodColor: Color {
        switch mood {
        case "释怀": return .cyan
        case "思念": return .purple
        case "怀念": return .orange
        case "心碎": return .red
        case "遗憾": return .indigo
        case "勇气": return .yellow
        case "回忆": return .blue
        case "孤独": return .gray
        case "挣扎": return .pink
        case "温暖": return .orange
        default: return .gray
        }
    }
}

#Preview {
    MoodRecommendView()
}
