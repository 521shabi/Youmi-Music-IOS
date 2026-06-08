import Foundation

// MARK: - 本地存储服务
@MainActor
class LocalStorageService: ObservableObject {
    static let shared = LocalStorageService()

    private let favoritesKey = "favorites_tracks"
    private let historyKey = "play_history_tracks"
    private let lastPlayedTrackKey = "last_played_track"
    private let maxFavorites = 500
    private let maxHistory = 200

    @Published var favoritesCount: Int = 0
    @Published var historyCount: Int = 0

    private init() {
        updateCounts()
    }

    // MARK: - 收藏功能

    /// 添加到收藏
    func addFavorite(_ track: Track) {
        var favorites = getFavorites()

        // 如果已存在则移除（避免重复）
        favorites.removeAll { $0.id == track.id }

        // 添加到开头
        favorites.insert(track, at: 0)

        // 限制数量
        if favorites.count > maxFavorites {
            favorites = Array(favorites.prefix(maxFavorites))
        }

        saveFavorites(favorites)
        updateCounts()
    }

    /// 从收藏移除
    func removeFavorite(_ trackId: Int) {
        var favorites = getFavorites()
        favorites.removeAll { $0.id == trackId }
        saveFavorites(favorites)
        updateCounts()
    }

    /// 检查是否已收藏
    nonisolated func isFavorite(_ trackId: Int) -> Bool {
        let favorites = getFavorites()
        return favorites.contains { $0.id == trackId }
    }

    /// 切换收藏状态
    func toggleFavorite(_ track: Track) -> Bool {
        if isFavorite(track.id) {
            removeFavorite(track.id)
            return false
        } else {
            addFavorite(track)
            return true
        }
    }

    /// 获取所有收藏
    nonisolated func getFavorites() -> [Track] {
        guard let data = UserDefaults.standard.data(forKey: favoritesKey),
              let tracks = try? JSONDecoder().decode([Track].self, from: data) else {
            return []
        }
        return tracks
    }

    /// 清空收藏
    func clearFavorites() {
        UserDefaults.standard.removeObject(forKey: favoritesKey)
        updateCounts()
    }

    private nonisolated func saveFavorites(_ tracks: [Track]) {
        if let data = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }

    // MARK: - 播放历史功能

    /// 添加到播放历史
    func addToHistory(_ track: Track) {
        var history = getHistory()

        // 如果已存在则移除（避免重复，新播放的移到最前）
        history.removeAll { $0.id == track.id }

        // 添加到开头
        history.insert(track, at: 0)

        // 限制数量
        if history.count > maxHistory {
            history = Array(history.prefix(maxHistory))
        }

        saveHistory(history)
        updateCounts()
    }

    /// 获取播放历史
    nonisolated func getHistory() -> [Track] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let tracks = try? JSONDecoder().decode([Track].self, from: data) else {
            return []
        }
        return tracks
    }

    /// 从历史移除
    func removeFromHistory(_ trackId: Int) {
        var history = getHistory()
        history.removeAll { $0.id == trackId }
        saveHistory(history)
        updateCounts()
    }

    /// 清空播放历史
    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
        updateCounts()
    }

    private nonisolated func saveHistory(_ tracks: [Track]) {
        if let data = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    // MARK: - 私有方法

    private func updateCounts() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.favoritesCount = self.getFavorites().count
            self.historyCount = self.getHistory().count
        }
    }

    // MARK: - 上次播放歌曲

    /// 保存上次播放的歌曲
    nonisolated func saveLastPlayedTrack(_ track: Track) {
        if let data = try? JSONEncoder().encode(track) {
            UserDefaults.standard.set(data, forKey: lastPlayedTrackKey)
        }
    }

    /// 获取上次播放的歌曲
    nonisolated func getLastPlayedTrack() -> Track? {
        guard let data = UserDefaults.standard.data(forKey: lastPlayedTrackKey),
              let track = try? JSONDecoder().decode(Track.self, from: data) else {
            return nil
        }
        return track
    }

    /// 清除上次播放的歌曲
    func clearLastPlayedTrack() {
        UserDefaults.standard.removeObject(forKey: lastPlayedTrackKey)
    }

    // MARK: - 播放队列（用于重启后恢复播放列表）

    private let playbackStateKey = "playback_state_v1"
    private let maxPlaybackQueueCount = 500

    struct PlaybackState: Codable {
        let playlist: [Track]
        let currentIndex: Int
        let playMode: String?      // PlayMode.storageValue
        let savedAt: Date
    }

    /// 保存播放队列（不自动播放，仅用于恢复 UI/队列状态）
    nonisolated func savePlaybackState(playlist: [Track], currentIndex: Int, playMode: String? = nil) {
        // 空队列：直接清除
        guard !playlist.isEmpty else {
            UserDefaults.standard.removeObject(forKey: playbackStateKey)
            return
        }

        // 限制队列长度，避免 UserDefaults 过大
        var trimmed = playlist
        if trimmed.count > maxPlaybackQueueCount {
            trimmed = Array(trimmed.prefix(maxPlaybackQueueCount))
        }

        let safeIndex = min(max(0, currentIndex), max(trimmed.count - 1, 0))
        let state = PlaybackState(
            playlist: trimmed,
            currentIndex: safeIndex,
            playMode: playMode,
            savedAt: Date()
        )

        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: playbackStateKey)
        }
    }

    /// 获取播放队列
    nonisolated func getPlaybackState() -> PlaybackState? {
        guard let data = UserDefaults.standard.data(forKey: playbackStateKey),
              let state = try? JSONDecoder().decode(PlaybackState.self, from: data) else {
            return nil
        }
        return state
    }

    /// 清除播放队列
    nonisolated func clearPlaybackState() {
        UserDefaults.standard.removeObject(forKey: playbackStateKey)
    }
}
