import Foundation

// MARK: - 汽水音乐解析 API 响应
struct QiShuiAPIResponse: Codable {
    let code: Int?
    let msg: String?
    let data: QiShuiSongData?
}

struct QiShuiSongData: Codable {
    // 音频
    let url: String?
    let Bitrate: Int?
    let Size: String?
    let Format: String?
    let Codec: String?
    let UrlExpire: Int?
    // 歌词
    let lyric: String?
    // 歌曲信息
    let albumname: String?
    let artistsname: String?
    let artistsid: Int64?
    let artistsmedium_avatar_url: [String]?
}

// MARK: - 汽水音乐歌曲模型（持久化）
struct QiShuiTrack: Codable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let coverUrl: String?
    let audioUrl: String
    let lyric: String?
    let duration: Int
    let sourceUrl: String
    let addedAt: Date
    let format: String?
    let bitrate: Int?
    let urlExpireAt: Date?

    /// 转换为播放器使用的 Track
    func toTrack() -> Track {
        let trackId = abs(id.hashValue) * -1
        return Track(
            id: trackId,
            name: title,
            ar: [Artist(id: 0, name: artist)],
            al: Album(id: 0, name: "汽水音乐", picUrl: coverUrl),
            dt: duration * 1000
        )
    }

    /// 音频 URL 是否已过期
    var isUrlExpired: Bool {
        guard let expire = urlExpireAt else { return false }
        return Date() >= expire
    }
}

// MARK: - 汽水音乐服务
@MainActor
class QiShuiMusicService: ObservableObject {
    static let shared = QiShuiMusicService()

    private let storageKey = "qishui_playlist_tracks"
    private let apiBaseURL = "https://api.bugpk.com/api/qsmusic"

    @Published var tracks: [QiShuiTrack] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private init() {
        loadTracks()
    }

    // MARK: - 解析汽水音乐链接

    /// 解析分享链接并添加到歌单
    func parseAndAdd(url shareUrl: String) async {
        let trimmed = shareUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "请输入链接"
            return
        }

        // 从分享文本中提取 URL
        let extractedUrl = extractUrl(from: trimmed)

        // 检查是否已存在
        if tracks.contains(where: { $0.sourceUrl == extractedUrl }) {
            errorMessage = "该歌曲已在歌单中"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let track = try await fetchSongData(shareUrl: extractedUrl)
            tracks.insert(track, at: 0)
            saveTracks()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 从分享文本中提取 URL（用户可能粘贴整段分享文字）
    private func extractUrl(from text: String) -> String {
        let pattern = #"https?://[^\s<>\"']+"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            return String(text[range])
        }
        return text
    }

    /// 刷新已过期的音频 URL
    func refreshUrlIfNeeded(for track: QiShuiTrack) async -> String? {
        if !track.isUrlExpired {
            return track.audioUrl
        }
        do {
            let refreshed = try await fetchSongData(shareUrl: track.sourceUrl)
            if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                tracks[index] = QiShuiTrack(
                    id: track.id,
                    title: track.title,
                    artist: track.artist,
                    coverUrl: refreshed.coverUrl ?? track.coverUrl,
                    audioUrl: refreshed.audioUrl,
                    lyric: track.lyric,
                    duration: track.duration,
                    sourceUrl: track.sourceUrl,
                    addedAt: track.addedAt,
                    format: refreshed.format,
                    bitrate: refreshed.bitrate,
                    urlExpireAt: refreshed.urlExpireAt
                )
                saveTracks()
            }
            return refreshed.audioUrl
        } catch {
            #if DEBUG
            print("🥤 刷新汽水音乐 URL 失败: \(error)")
            #endif
            return nil
        }
    }

    /// 调用 API 解析
    private func fetchSongData(shareUrl: String) async throws -> QiShuiTrack {
        guard let encoded = shareUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(apiBaseURL)?url=\(encoded)") else {
            throw QiShuiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw QiShuiError.networkError
        }

        // 先尝试 Codable 解析
        if let apiResponse = try? JSONDecoder().decode(QiShuiAPIResponse.self, from: data),
           let songData = apiResponse.data,
           let audioUrl = songData.url, !audioUrl.isEmpty {

            let expireDate: Date? = songData.UrlExpire.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            let coverUrl = songData.artistsmedium_avatar_url?.first

            return QiShuiTrack(
                id: UUID().uuidString,
                title: songData.albumname ?? "未知歌曲",
                artist: songData.artistsname ?? "未知歌手",
                coverUrl: coverUrl,
                audioUrl: audioUrl,
                lyric: songData.lyric,
                duration: 0,
                sourceUrl: shareUrl,
                addedAt: Date(),
                format: songData.Format,
                bitrate: songData.Bitrate,
                urlExpireAt: expireDate
            )
        }

        // 兜底：从原始 JSON 字典提取
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return try extractFromRawJSON(json, shareUrl: shareUrl)
        }

        throw QiShuiError.parseFailed("无法解析返回数据")
    }

    /// 从原始 JSON 提取数据（兼容不同返回格式）
    private func extractFromRawJSON(_ json: [String: Any], shareUrl: String) throws -> QiShuiTrack {
        let data = json["data"] as? [String: Any] ?? json

        guard let audioUrl = data["url"] as? String, !audioUrl.isEmpty else {
            let msg = json["msg"] as? String ?? "未获取到音频地址"
            throw QiShuiError.parseFailed(msg)
        }

        let expireTimestamp = data["UrlExpire"] as? Int
        let expireDate = expireTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let avatarUrls = data["artistsmedium_avatar_url"] as? [String]
        let coverUrl = avatarUrls?.first ?? data["cover"] as? String

        return QiShuiTrack(
            id: UUID().uuidString,
            title: data["albumname"] as? String ?? data["title"] as? String ?? "未知歌曲",
            artist: data["artistsname"] as? String ?? data["author"] as? String ?? "未知歌手",
            coverUrl: coverUrl,
            audioUrl: audioUrl,
            lyric: data["lyric"] as? String ?? data["lrc"] as? String,
            duration: 0,
            sourceUrl: shareUrl,
            addedAt: Date(),
            format: data["Format"] as? String,
            bitrate: data["Bitrate"] as? Int,
            urlExpireAt: expireDate
        )
    }

    // MARK: - 歌单管理

    func removeTrack(_ track: QiShuiTrack) {
        tracks.removeAll { $0.id == track.id }
        saveTracks()
    }

    func removeTrack(at offsets: IndexSet) {
        tracks.remove(atOffsets: offsets)
        saveTracks()
    }

    func clearAll() {
        tracks.removeAll()
        saveTracks()
    }

    // MARK: - 持久化

    private func saveTracks() {
        if let data = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadTracks() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([QiShuiTrack].self, from: data) else {
            return
        }
        tracks = saved
    }
}

// MARK: - 错误类型
enum QiShuiError: LocalizedError {
    case invalidURL
    case networkError
    case parseFailed(String)
    case noAudioUrl

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的链接"
        case .networkError: return "网络请求失败"
        case .parseFailed(let msg): return "解析失败: \(msg)"
        case .noAudioUrl: return "未获取到音频地址"
        }
    }
}
