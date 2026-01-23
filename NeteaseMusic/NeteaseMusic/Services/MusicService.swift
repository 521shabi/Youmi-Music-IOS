import Foundation

/// 音乐服务
class MusicService {
    static let shared = MusicService()
    private let network = NetworkService.shared
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - 通用网络请求方法

    /// 通用 GET 请求（自动解码）
    private func fetch<T: Decodable>(_ endpoint: String) async throws -> T {
        guard let url = URL(string: "\(APIConfig.baseURL)/\(endpoint)") else {
            throw NetworkError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode(T.self, from: data)
    }

    /// 通用 GET 请求（带完整 URL）
    private func fetchURL<T: Decodable>(_ url: URL) async throws -> T {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode(T.self, from: data)
    }

    /// 预热网络连接（DNS解析 + TCP连接）
    func warmup() {
        Task(priority: .background) {
            guard let url = URL(string: "\(APIConfig.baseURL)/") else { return }
            _ = try? await URLSession.shared.data(from: url)
        }
    }
    
    /// 获取推荐歌单（带缓存）
    /// - Parameter limit: 数量，默认30
    func getPersonalized(limit: Int = 30) async throws -> [RecommendPlaylist] {
        if let cached = await APICache.shared.getCachedPersonalized() {
            return cached
        }
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let response: PersonalizedResponse = try await fetch("personalized?limit=\(limit)&timestamp=\(timestamp)")
        let result = response.result ?? []
        await APICache.shared.cachePersonalized(result)
        return result
    }

    /// 获取歌单详情
    /// - Parameter id: 歌单ID
    func getPlaylistDetail(id: Int) async throws -> PlaylistDetail? {
        let response: PlaylistDetailResponse = try await fetch("playlist/detail?id=\(id)")
        return response.playlist
    }

    /// 获取Banner（带缓存）
    func getBanners() async throws -> [Banner] {
        if let cached = await APICache.shared.getCachedBanners() {
            return cached
        }
        let response: BannerResponse = try await fetch("banner?type=1")
        let result = response.banners ?? []
        await APICache.shared.cacheBanners(result)
        return result
    }

    /// 获取歌词
    func getLyric(id: Int) async throws -> String {
        let response: LyricResponse = try await fetch("lyric?id=\(id)")
        return response.lrc?.lyric ?? ""
    }

    /// 获取歌词（带翻译）
    func getLyricWithTranslation(id: Int) async throws -> (lyric: String, translation: String?) {
        let response: LyricResponse = try await fetch("lyric?id=\(id)")
        return (response.lrc?.lyric ?? "", response.tlyric?.lyric)
    }

    /// 获取逐字歌词（YRC格式）
    func getYrcLyric(id: Int) async throws -> (yrc: String?, lyric: String, translation: String?) {
        let response: YrcLyricResponse = try await fetch("lyric/new?id=\(id)")
        return (response.yrc?.lyric, response.lrc?.lyric ?? "", response.tlyric?.lyric)
    }

    /// 搜索歌曲
    func search(keyword: String, limit: Int = 30, offset: Int = 0) async throws -> [SearchSong] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let response: SearchResponse = try await fetch("search?keywords=\(encoded)&limit=\(limit)&offset=\(offset)&type=1")
        return response.result?.songs ?? []
    }

    /// 搜索歌手
    func searchArtists(keyword: String, limit: Int = 20, offset: Int = 0) async throws -> [SearchArtistResult] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let response: SearchArtistResponse = try await fetch("search?keywords=\(encoded)&limit=\(limit)&offset=\(offset)&type=100")
        return response.result?.artists ?? []
    }

    /// 搜索专辑
    func searchAlbums(keyword: String, limit: Int = 20, offset: Int = 0) async throws -> [SearchAlbumResult] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let response: SearchAlbumResponse = try await fetch("search?keywords=\(encoded)&limit=\(limit)&offset=\(offset)&type=10")
        return response.result?.albums ?? []
    }

    /// 获取热搜列表（带缓存）
    func getHotSearch() async throws -> [HotSearch] {
        if let cached = await APICache.shared.getCachedHotSearch() {
            return cached
        }
        let response: HotSearchResponse = try await fetch("search/hot/detail")
        let result = response.data ?? []
        await APICache.shared.cacheHotSearch(result)
        return result
    }

    /// 获取歌曲详情(包含封面)
    func getSongDetail(ids: [Int]) async throws -> [Track] {
        let idsStr = ids.map { String($0) }.joined(separator: ",")
        let response: SongDetailResponse = try await fetch("song/detail?ids=\(idsStr)")
        return response.songs ?? []
    }

    /// 获取歌曲播放URL
    func getSongUrl(id: Int, br: Int = 320000) async throws -> SongUrlData? {
        let response: SongUrlResponse = try await fetch("song/url?id=\(id)&br=\(br)")
        return response.data?.first
    }

    /// 检查音乐是否可用（是否可播放）
    func checkMusicAvailable(id: Int) async throws -> Bool {
        let response: CheckMusicResponse = try await fetch("check/music?id=\(id)")
        return response.success ?? false
    }

    /// 获取所有排行榜（带缓存）
    func getToplist() async throws -> [ToplistItem] {
        if let cached = await APICache.shared.getCachedToplist() {
            return cached
        }
        let response: ToplistResponse = try await fetch("toplist")
        let result = response.list ?? []
        await APICache.shared.cacheToplist(result)
        return result
    }

    /// 获取精品歌单（歌单广场）
    func getTopPlaylist(cat: String = "全部", limit: Int = 30, before: Int? = nil) async throws -> [RecommendPlaylist] {
        let catEncoded = cat.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cat
        var endpoint = "top/playlist/highquality?cat=\(catEncoded)&limit=\(limit)"
        if let before = before {
            endpoint += "&before=\(before)"
        }
        let response: TopPlaylistResponse = try await fetch(endpoint)
        return response.playlists ?? []
    }

    /// 获取热门歌单
    func getHotPlaylist(cat: String = "全部", limit: Int = 30, offset: Int = 0) async throws -> [RecommendPlaylist] {
        let catEncoded = cat.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cat
        let response: HotPlaylistResponse = try await fetch("top/playlist?cat=\(catEncoded)&limit=\(limit)&offset=\(offset)")
        return response.playlists ?? []
    }
    
    /// 获取新歌速递
    /// - Parameter type: 地区类型 0:全部 7:华语 96:欧美 8:日本 16:韩国
    func getTopSongs(type: Int = 0) async throws -> [Track] {
        let response: TopSongResponse = try await fetch("top/song?type=\(type)")
        return response.data ?? []
    }
    
    /// 获取新碑上架（最新专辑）
    /// - Parameters:
    ///   - area: 地区 ALL:全部 ZH:华语 EA:欧美 JP:日本 KR:韩国
    ///   - limit: 数量
    ///   - offset: 偏移
    func getNewAlbums(area: String = "ALL", limit: Int = 30, offset: Int = 0) async throws -> [NewAlbum] {
        let response: NewAlbumResponse = try await fetch("album/new?area=\(area)&limit=\(limit)&offset=\(offset)")
        return response.albums ?? []
    }
    
    /// 获取推荐新音乐（首页推荐新歌）
    func getPersonalizedNewSong(limit: Int = 10) async throws -> [PersonalizedSong] {
        let response: PersonalizedNewSongResponse = try await fetch("personalized/newsong?limit=\(limit)")
        return response.result ?? []
    }

    /// 获取歌单分类
    func getPlaylistCategories() async throws -> PlaylistCatResponse {
        return try await fetch("playlist/catlist")
    }

    /// 获取专辑动态封面 (网易云)
    func getDynamicCover(albumId: Int) async throws -> String? {
        let response: DynamicCoverResponse = try await fetch("album/detail/dynamic?id=\(albumId)")
        return response.data?.videoGroup?.video?.url
    }
    
    /// 获取 Apple Music 动态封面
    /// - Parameters:
    ///   - songName: 歌曲名
    ///   - artistName: 歌手名
    func getAppleMusicAnimatedCover(songName: String, artistName: String) async throws -> String? {
        // Step 1: 用 iTunes Search API 搜索获取专辑ID
        let searchTerm = "\(songName) \(artistName)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let searchUrl = URL(string: "https://itunes.apple.com/search?term=\(searchTerm)&media=music&entity=song&limit=1") else {
            throw NetworkError.invalidURL
        }
        
        let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
        let searchResponse = try JSONDecoder().decode(ITunesSearchResponse.self, from: searchData)
        
        guard let collectionId = searchResponse.results?.first?.collectionId else {
            return nil
        }
        
        // Step 2: 获取 Bearer Token
        guard let token = await AppleMusicTokenManager.shared.getToken() else {
            print(" 无法获取 Apple Music Token")
            return nil
        }
        
        // Step 3: 调用 Apple Music AMP API 获取动态封面
        guard let ampUrl = URL(string: "https://amp-api.music.apple.com/v1/catalog/cn/albums/\(collectionId)?extend=editorialVideo") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: ampUrl)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        
        let (ampData, _) = try await URLSession.shared.data(for: request)
        let ampResponse = try JSONDecoder().decode(AppleMusicAlbumResponse.self, from: ampData)
        
        // Step 4: 提取动态封面 URL
        // 优先使用 3:4 竖版视频（锁屏动态封面需要），其次是 1:1 正方形
        if let editorialVideo = ampResponse.data?.first?.attributes?.editorialVideo {
            return editorialVideo.motionTallVideo3x4?.video ??
                   editorialVideo.motionSquareVideo1x1?.video ??
                   editorialVideo.motionDetailSquare?.video
        }
        
        return nil
    }
    
    // MARK: - 评论 API
    
    /// 获取歌曲评论
    /// - Parameters:
    ///   - id: 歌曲ID
    ///   - limit: 每页数量
    ///   - offset: 偏移量
    func getComments(id: Int, limit: Int = 20, offset: Int = 0) async throws -> CommentResponse {
        guard let url = URL(string: "\(APIConfig.baseURL)/comment/music?id=\(id)&limit=\(limit)&offset=\(offset)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(CommentResponse.self, from: data)
    }
    
    // MARK: - 歌手 API
    
    /// 获取歌手详情
    /// - Parameter id: 歌手ID
    func getArtistDetail(id: Int) async throws -> ArtistDetail? {
        guard let url = URL(string: "\(APIConfig.baseURL)/artist/detail?id=\(id)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ArtistDetailResponse.self, from: data)
        
        return response.data?.artist
    }
    
    /// 获取歌手热门歌曲
    /// - Parameter id: 歌手ID
    func getArtistTopSongs(id: Int) async throws -> [Track] {
        guard let url = URL(string: "\(APIConfig.baseURL)/artist/top/song?id=\(id)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ArtistTopSongsResponse.self, from: data)
        
        return response.songs ?? []
    }
    
    /// 获取歌手专辑
    /// - Parameters:
    ///   - id: 歌手ID
    ///   - limit: 数量
    ///   - offset: 偏移
    func getArtistAlbums(id: Int, limit: Int = 30, offset: Int = 0) async throws -> [AlbumDetail] {
        guard let url = URL(string: "\(APIConfig.baseURL)/artist/album?id=\(id)&limit=\(limit)&offset=\(offset)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ArtistAlbumsResponse.self, from: data)
        
        return response.hotAlbums ?? []
    }
    
    // MARK: - 专辑 API
    
    /// 获取专辑详情
    /// - Parameter id: 专辑ID
    func getAlbumDetail(id: Int) async throws -> (album: AlbumDetail?, songs: [Track]) {
        guard let url = URL(string: "\(APIConfig.baseURL)/album?id=\(id)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(AlbumDetailResponse.self, from: data)
        
        return (response.album, response.songs ?? [])
    }
    
    // MARK: - 云端音乐 API
    
    /// 获取歌单歌曲列表（云端）
    /// - Parameter playlistId: 歌单ID
    func getPlaylistTracks(playlistId: Int) async throws -> [CloudTrack] {
        guard let url = URL(string: "\(APIConfig.baseURL)/playlist/detail?id=\(playlistId)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "GET")
        let response = try JSONDecoder().decode(CloudPlaylistDetailResponse.self, from: data)
        
        return response.playlist?.tracks ?? []
    }
    
    /// 获取专辑歌曲列表（云端）
    /// - Parameter albumId: 专辑ID
    func getAlbumTracks(albumId: Int) async throws -> [CloudTrack] {
        guard let url = URL(string: "\(APIConfig.baseURL)/album?id=\(albumId)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "GET")
        let response = try JSONDecoder().decode(CloudAlbumDetailResponse.self, from: data)
        
        return response.songs ?? []
    }
}

// MARK: - Apple Music Token 管理器（优化版）
class AppleMusicTokenManager {
    static let shared = AppleMusicTokenManager()

    private var cachedToken: String?
    private var tokenExpiry: Date?
    private var fetchTask: Task<String?, Never>?  // 避免重复请求
    private let session: URLSession
    private var failureCount: Int = 0
    private let maxFailureCount: Int = 3  // 连续失败3次后停止重试
    private var lastFailureTime: Date?

    private init() {
        // 配置合理的超时时间
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15  // 增加到15秒
        config.timeoutIntervalForResource = 30  // 增加到30秒
        self.session = URLSession(configuration: config)
    }

    /// App 启动时预热 Token（静默失败，不影响主流程）
    func warmUp() {
        Task(priority: .background) {
            _ = await getToken()
        }
    }

    /// 重置失败计数（可在网络恢复时调用）
    func resetFailureCount() {
        failureCount = 0
        lastFailureTime = nil
    }

    /// 获取 Token（自动缓存 1 小时，避免重复请求）
    func getToken() async -> String? {
        // 检查缓存是否有效
        if let token = cachedToken,
           let expiry = tokenExpiry,
           Date() < expiry {
            return token
        }

        // 如果连续失败次数过多，暂时停止尝试（5分钟后可重试）
        if failureCount >= maxFailureCount {
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) < 300 {
                #if DEBUG
                print(" Apple Music Token 获取暂停（连续失败\(failureCount)次）")
                #endif
                return nil
            } else {
                // 超过5分钟，重置计数器
                failureCount = 0
                lastFailureTime = nil
            }
        }

        // 如果已有请求在进行中，等待它完成
        if let task = fetchTask {
            return await task.value
        }

        // 创建新的请求任务
        let task = Task<String?, Never> {
            return await fetchTokenFromAppleMusic()
        }
        fetchTask = task

        let newToken = await task.value
        fetchTask = nil

        if let token = newToken {
            cachedToken = token
            tokenExpiry = Date().addingTimeInterval(60 * 60) // 缓存 1 小时
            failureCount = 0  // 成功后重置失败计数
        } else {
            failureCount += 1
            lastFailureTime = Date()
        }

        return newToken
    }

    /// 从 Apple Music 网站获取 Token
    private func fetchTokenFromAppleMusic() async -> String? {
        do {
            guard let browseUrl = URL(string: "https://music.apple.com/us/browse") else {
                return nil
            }

            #if DEBUG
            print(" 正在获取 Apple Music Token...")
            #endif
            let (htmlData, _) = try await session.data(from: browseUrl)
            guard let html = String(data: htmlData, encoding: .utf8) else {
                return nil
            }

            // 从 HTML 中提取 JS 文件路径
            let jsPattern = #"/assets/index[^"'\s]*\.js"#
            guard let jsRegex = try? NSRegularExpression(pattern: jsPattern),
                  let jsMatch = jsRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let jsRange = Range(jsMatch.range, in: html) else {
                return nil
            }

            let jsPath = String(html[jsRange])
            let jsUrl = "https://music.apple.com\(jsPath)"

            guard let jsURL = URL(string: jsUrl) else {
                return nil
            }

            let (jsData, _) = try await session.data(from: jsURL)
            guard let jsContent = String(data: jsData, encoding: .utf8) else {
                return nil
            }

            // 用正则提取 JWT
            let tokenPattern = #"eyJhbGciOiJFUzI1Ni[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#
            guard let tokenRegex = try? NSRegularExpression(pattern: tokenPattern),
                  let tokenMatch = tokenRegex.firstMatch(in: jsContent, range: NSRange(jsContent.startIndex..., in: jsContent)),
                  let tokenRange = Range(tokenMatch.range, in: jsContent) else {
                return nil
            }

            let token = String(jsContent[tokenRange])
            #if DEBUG
            print(" 成功获取 Apple Music Token")
            #endif
            return token

        } catch {
            #if DEBUG
            print(" 获取 Apple Music Token 失败: \(error)")
            #endif
            return nil
        }
    }
}
