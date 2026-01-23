import Foundation

// MARK: - 本地存储服务
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
    func isFavorite(_ trackId: Int) -> Bool {
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
    func getFavorites() -> [Track] {
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
    
    private func saveFavorites(_ tracks: [Track]) {
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
    func getHistory() -> [Track] {
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
    
    private func saveHistory(_ tracks: [Track]) {
        if let data = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
    
    // MARK: - 私有方法
    
    private func updateCounts() {
        DispatchQueue.main.async {
            self.favoritesCount = self.getFavorites().count
            self.historyCount = self.getHistory().count
        }
    }
    
    // MARK: - 上次播放歌曲
    
    /// 保存上次播放的歌曲
    func saveLastPlayedTrack(_ track: Track) {
        if let data = try? JSONEncoder().encode(track) {
            UserDefaults.standard.set(data, forKey: lastPlayedTrackKey)
        }
    }
    
    /// 获取上次播放的歌曲
    func getLastPlayedTrack() -> Track? {
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
}
