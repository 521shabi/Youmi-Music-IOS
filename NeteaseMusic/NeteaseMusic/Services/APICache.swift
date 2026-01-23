import Foundation

/// API 响应缓存（用于热搜、排行榜等不频繁更新的数据）
actor APICache {
    static let shared = APICache()
    
    private struct CacheEntry<T> {
        let data: T
        let timestamp: Date
        let ttl: TimeInterval
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > ttl
        }
    }
    
    // 缓存存储
    private var hotSearchCache: CacheEntry<[HotSearch]>?
    private var toplistCache: CacheEntry<[ToplistItem]>?
    private var bannersCache: CacheEntry<[Banner]>?
    private var personalizedCache: CacheEntry<[RecommendPlaylist]>?
    
    // 默认 TTL（秒）
    private let hotSearchTTL: TimeInterval = 10 * 60      // 热搜 10 分钟
    private let toplistTTL: TimeInterval = 30 * 60        // 排行榜 30 分钟
    private let bannersTTL: TimeInterval = 15 * 60        // Banner 15 分钟
    private let personalizedTTL: TimeInterval = 5 * 60    // 推荐歌单 5 分钟
    
    private init() {}
    
    // MARK: - 热搜缓存
    
    func getCachedHotSearch() -> [HotSearch]? {
        guard let cache = hotSearchCache, !cache.isExpired else {
            return nil
        }
        print(" 使用热搜缓存")
        return cache.data
    }
    
    func cacheHotSearch(_ data: [HotSearch]) {
        hotSearchCache = CacheEntry(data: data, timestamp: Date(), ttl: hotSearchTTL)
        print(" 热搜已缓存，TTL: \(Int(hotSearchTTL))s")
    }
    
    // MARK: - 排行榜缓存
    
    func getCachedToplist() -> [ToplistItem]? {
        guard let cache = toplistCache, !cache.isExpired else {
            return nil
        }
        print(" 使用排行榜缓存")
        return cache.data
    }
    
    func cacheToplist(_ data: [ToplistItem]) {
        toplistCache = CacheEntry(data: data, timestamp: Date(), ttl: toplistTTL)
        print(" 排行榜已缓存，TTL: \(Int(toplistTTL))s")
    }
    
    // MARK: - Banner 缓存
    
    func getCachedBanners() -> [Banner]? {
        guard let cache = bannersCache, !cache.isExpired else {
            return nil
        }
        print(" 使用 Banner 缓存")
        return cache.data
    }
    
    func cacheBanners(_ data: [Banner]) {
        bannersCache = CacheEntry(data: data, timestamp: Date(), ttl: bannersTTL)
        print(" Banner 已缓存，TTL: \(Int(bannersTTL))s")
    }
    
    // MARK: - 推荐歌单缓存
    
    func getCachedPersonalized() -> [RecommendPlaylist]? {
        guard let cache = personalizedCache, !cache.isExpired else {
            return nil
        }
        print(" 使用推荐歌单缓存")
        return cache.data
    }
    
    func cachePersonalized(_ data: [RecommendPlaylist]) {
        personalizedCache = CacheEntry(data: data, timestamp: Date(), ttl: personalizedTTL)
        print(" 推荐歌单已缓存，TTL: \(Int(personalizedTTL))s")
    }
    
    // MARK: - 清理缓存
    
    func clearAll() {
        hotSearchCache = nil
        toplistCache = nil
        bannersCache = nil
        personalizedCache = nil
        print(" API 缓存已清空")
    }
    
    func clearHotSearch() {
        hotSearchCache = nil
    }
    
    func clearToplist() {
        toplistCache = nil
    }
}
