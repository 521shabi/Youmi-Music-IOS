import Foundation
import UIKit

// MARK: - 缓存的歌曲 URL 数据
struct CachedSongUrl: Codable {
    let id: Int
    let url: String
    let quality: String
    let expireTime: Date
    let createdAt: Date
    
    var isExpired: Bool {
        Date() > expireTime
    }
}

// MARK: - 缓存的歌词数据
struct CachedLyric: Codable {
    let id: Int
    let lyric: String
    let translation: String?
    let yrc: String?           // 逐字歌词
    let createdAt: Date
}

// MARK: - 歌曲缓存服务
final class SongCacheService {
    static let shared = SongCacheService()
    
    // MARK: - 常量
    private let urlCacheKey = "cached_song_urls"
    private let lyricCacheKey = "cached_lyrics"
    private let urlTTL: TimeInterval = 15 * 60          // URL 缓存 15 分钟（网易云 URL 有效期较短）
    private let lyricTTL: TimeInterval = 7 * 24 * 3600  // 歌词缓存 7 天
    private let maxUrlCacheCount = 100
    private let maxLyricCacheCount = 200
    
    // MARK: - 内存缓存
    private var urlMemoryCache: [String: CachedSongUrl] = [:]
    private var lyricMemoryCache: [Int: CachedLyric] = [:]
    private let cacheLock = NSLock()
    
    // MARK: - 初始化
    private init() {
        loadFromDisk()
        
        // 监听内存警告
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // 监听 App 进入后台
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        // 内存警告时只保留最近的缓存
        cacheLock.lock()
        if urlMemoryCache.count > 20 {
            let sorted = urlMemoryCache.sorted { $0.value.createdAt > $1.value.createdAt }
            urlMemoryCache = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(20)))
        }
        if lyricMemoryCache.count > 50 {
            let sorted = lyricMemoryCache.sorted { $0.value.createdAt > $1.value.createdAt }
            lyricMemoryCache = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(50)))
        }
        cacheLock.unlock()
        
        #if DEBUG
        print(" 内存警告：已清理部分歌曲缓存")
        #endif
    }
    
    @objc private func handleEnterBackground() {
        saveToDisk()
    }
    
    // MARK: - URL 缓存
    
    /// 获取缓存的歌曲 URL
    func getCachedUrl(songId: Int, quality: String) -> String? {
        let key = "\(songId)_\(quality)"
        
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        guard let cached = urlMemoryCache[key] else {
            return nil
        }
        
        // 检查是否过期
        if cached.isExpired {
            urlMemoryCache.removeValue(forKey: key)
            return nil
        }
        
        #if DEBUG
        print(" 命中 URL 缓存: \(songId) (\(quality))")
        #endif
        
        return cached.url
    }
    
    /// 缓存歌曲 URL
    func cacheUrl(songId: Int, url: String, quality: String) {
        let key = "\(songId)_\(quality)"
        let cached = CachedSongUrl(
            id: songId,
            url: url,
            quality: quality,
            expireTime: Date().addingTimeInterval(urlTTL),
            createdAt: Date()
        )
        
        cacheLock.lock()
        urlMemoryCache[key] = cached
        
        // 超过上限时清理最旧的
        if urlMemoryCache.count > maxUrlCacheCount {
            let sorted = urlMemoryCache.sorted { $0.value.createdAt > $1.value.createdAt }
            urlMemoryCache = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(maxUrlCacheCount)))
        }
        cacheLock.unlock()
        
        #if DEBUG
        print(" 缓存 URL: \(songId) (\(quality)), TTL: \(Int(urlTTL/60))分钟")
        #endif
    }
    
    /// 批量获取缓存的 URL
    func getCachedUrls(songIds: [Int], quality: String) -> [Int: String] {
        var result: [Int: String] = [:]
        
        cacheLock.lock()
        for id in songIds {
            let key = "\(id)_\(quality)"
            if let cached = urlMemoryCache[key], !cached.isExpired {
                result[id] = cached.url
            }
        }
        cacheLock.unlock()
        
        return result
    }
    
    // MARK: - 歌词缓存
    
    /// 获取缓存的歌词
    func getCachedLyric(songId: Int) -> CachedLyric? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        guard let cached = lyricMemoryCache[songId] else {
            return nil
        }
        
        // 检查是否过期（7天）
        if Date().timeIntervalSince(cached.createdAt) > lyricTTL {
            lyricMemoryCache.removeValue(forKey: songId)
            return nil
        }
        
        #if DEBUG
        print(" 命中歌词缓存: \(songId)")
        #endif
        
        return cached
    }
    
    /// 缓存歌词
    func cacheLyric(songId: Int, lyric: String, translation: String?, yrc: String?) {
        let cached = CachedLyric(
            id: songId,
            lyric: lyric,
            translation: translation,
            yrc: yrc,
            createdAt: Date()
        )
        
        cacheLock.lock()
        lyricMemoryCache[songId] = cached
        
        // 超过上限时清理最旧的
        if lyricMemoryCache.count > maxLyricCacheCount {
            let sorted = lyricMemoryCache.sorted { $0.value.createdAt > $1.value.createdAt }
            lyricMemoryCache = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(maxLyricCacheCount)))
        }
        cacheLock.unlock()
        
        #if DEBUG
        print(" 缓存歌词: \(songId), 有YRC: \(yrc != nil)")
        #endif
    }
    
    // MARK: - 持久化
    
    /// 保存到磁盘
    func saveToDisk() {
        cacheLock.lock()
        let urls = Array(urlMemoryCache.values)
        let lyrics = Array(lyricMemoryCache.values)
        cacheLock.unlock()
        
        // 只保存未过期的 URL
        let validUrls = urls.filter { !$0.isExpired }
        
        if let urlData = try? JSONEncoder().encode(validUrls) {
            UserDefaults.standard.set(urlData, forKey: urlCacheKey)
        }
        
        if let lyricData = try? JSONEncoder().encode(lyrics) {
            UserDefaults.standard.set(lyricData, forKey: lyricCacheKey)
        }
        
        #if DEBUG
        print(" 缓存已保存: \(validUrls.count) URLs, \(lyrics.count) 歌词")
        #endif
    }
    
    /// 从磁盘加载
    private func loadFromDisk() {
        // 加载 URL 缓存
        if let data = UserDefaults.standard.data(forKey: urlCacheKey),
           let urls = try? JSONDecoder().decode([CachedSongUrl].self, from: data) {
            cacheLock.lock()
            for cached in urls where !cached.isExpired {
                let key = "\(cached.id)_\(cached.quality)"
                urlMemoryCache[key] = cached
            }
            cacheLock.unlock()
            
            #if DEBUG
            print(" 已加载 \(urlMemoryCache.count) 个 URL 缓存")
            #endif
        }
        
        // 加载歌词缓存
        if let data = UserDefaults.standard.data(forKey: lyricCacheKey),
           let lyrics = try? JSONDecoder().decode([CachedLyric].self, from: data) {
            cacheLock.lock()
            for cached in lyrics {
                // 检查是否过期
                if Date().timeIntervalSince(cached.createdAt) <= lyricTTL {
                    lyricMemoryCache[cached.id] = cached
                }
            }
            cacheLock.unlock()
            
            #if DEBUG
            print(" 已加载 \(lyricMemoryCache.count) 个歌词缓存")
            #endif
        }
    }
    
    // MARK: - 清理
    
    /// 清理所有缓存
    func clearAll() {
        cacheLock.lock()
        urlMemoryCache.removeAll()
        lyricMemoryCache.removeAll()
        cacheLock.unlock()
        
        UserDefaults.standard.removeObject(forKey: urlCacheKey)
        UserDefaults.standard.removeObject(forKey: lyricCacheKey)
        
        #if DEBUG
        print(" 已清空所有歌曲缓存")
        #endif
    }
    
    /// 清理过期缓存
    func cleanExpired() {
        cacheLock.lock()
        
        // 清理过期 URL
        let expiredUrlKeys = urlMemoryCache.filter { $0.value.isExpired }.map { $0.key }
        for key in expiredUrlKeys {
            urlMemoryCache.removeValue(forKey: key)
        }
        
        // 清理过期歌词
        let expiredLyricIds = lyricMemoryCache.filter { 
            Date().timeIntervalSince($0.value.createdAt) > lyricTTL 
        }.map { $0.key }
        for id in expiredLyricIds {
            lyricMemoryCache.removeValue(forKey: id)
        }
        
        cacheLock.unlock()
        
        #if DEBUG
        if !expiredUrlKeys.isEmpty || !expiredLyricIds.isEmpty {
            print(" 清理过期缓存: \(expiredUrlKeys.count) URLs, \(expiredLyricIds.count) 歌词")
        }
        #endif
    }
    
    /// 清理指定歌曲的 URL 缓存（用于切换音质后或播放失败时）
    func clearUrlCache(songId: Int) {
        cacheLock.lock()
        let keysToRemove = urlMemoryCache.keys.filter { $0.hasPrefix("\(songId)_") }
        for key in keysToRemove {
            urlMemoryCache.removeValue(forKey: key)
        }
        cacheLock.unlock()
        
        #if DEBUG
        if !keysToRemove.isEmpty {
            print(" 清除歌曲 \(songId) 的 URL 缓存")
        }
        #endif
        
        // 同步到磁盘
        saveToDisk()
    }
    
    // MARK: - 统计
    
    var urlCacheCount: Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return urlMemoryCache.count
    }
    
    var lyricCacheCount: Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return lyricMemoryCache.count
    }
}
