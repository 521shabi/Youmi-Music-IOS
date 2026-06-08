import Foundation

/// API 响应缓存（通用 key-value 缓存 + 请求去重）
actor APICache {
    static let shared = APICache()

    private struct CacheEntry {
        let data: Any
        let timestamp: Date
        let ttl: TimeInterval

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > ttl
        }
    }

    // 统一缓存存储
    private var cache: [String: CacheEntry] = [:]

    // 请求去重：正在进行中的请求
    private var inflightTasks: [String: Task<Any, Error>] = [:]

    // 预设 TTL 配置
    private let ttlConfig: [String: TimeInterval] = [
        "hotSearch": 10 * 60,       // 热搜 10 分钟
        "toplist": 30 * 60,         // 排行榜 30 分钟
        "banners": 15 * 60,         // Banner 15 分钟
        "personalized": 5 * 60,     // 推荐歌单 5 分钟
        "playlistDetail": 5 * 60,   // 歌单详情 5 分钟
        "artistDetail": 10 * 60,    // 歌手详情 10 分钟
        "albumDetail": 10 * 60,     // 专辑详情 10 分钟
        "searchResult": 3 * 60      // 搜索结果 3 分钟
    ]

    private let defaultTTL: TimeInterval = 5 * 60  // 默认 5 分钟

    private init() {}

    // MARK: - 通用缓存方法

    /// 获取缓存（泛型）
    func get<T>(_ key: String) -> T? {
        guard let entry = cache[key], !entry.isExpired else {
            if cache[key] != nil {
                cache.removeValue(forKey: key)  // 清理过期条目
            }
            return nil
        }
        return entry.data as? T
    }

    /// 写入缓存（泛型，可自定义 TTL）
    func set<T>(_ key: String, data: T, ttl: TimeInterval? = nil) {
        let effectiveTTL = ttl ?? ttlConfig[key] ?? defaultTTL
        cache[key] = CacheEntry(data: data, timestamp: Date(), ttl: effectiveTTL)
    }

    /// 请求去重：如果同一个 key 的请求正在进行中，等待它完成而不是发起新请求
    func deduplicated<T>(_ key: String, ttl: TimeInterval? = nil, fetch: @Sendable @escaping () async throws -> T) async throws -> T {
        // 1. 先检查缓存
        if let cached: T = get(key) {
            return cached
        }

        // 2. 检查是否有正在进行的请求
        if let existingTask = inflightTasks[key] {
            if let result = try await existingTask.value as? T {
                return result
            }
        }

        // 3. 创建新请求
        let task = Task<Any, Error> {
            let result = try await fetch()
            return result as Any
        }
        inflightTasks[key] = task

        do {
            let result = try await task.value
            inflightTasks.removeValue(forKey: key)

            // 缓存结果
            if let typedResult = result as? T {
                set(key, data: typedResult, ttl: ttl)
                return typedResult
            }
            throw NSError(domain: "APICache", code: -1, userInfo: [NSLocalizedDescriptionKey: "类型转换失败"])
        } catch {
            inflightTasks.removeValue(forKey: key)
            throw error
        }
    }

    /// 清除指定 key 的缓存
    func remove(_ key: String) {
        cache.removeValue(forKey: key)
    }

    // MARK: - 兼容旧接口（保持向后兼容）

    func getCachedHotSearch() -> [HotSearch]? { get("hotSearch") }
    func cacheHotSearch(_ data: [HotSearch]) { set("hotSearch", data: data) }

    func getCachedToplist() -> [ToplistItem]? { get("toplist") }
    func cacheToplist(_ data: [ToplistItem]) { set("toplist", data: data) }

    func getCachedBanners() -> [Banner]? { get("banners") }
    func cacheBanners(_ data: [Banner]) { set("banners", data: data) }

    func getCachedPersonalized() -> [RecommendPlaylist]? { get("personalized") }
    func cachePersonalized(_ data: [RecommendPlaylist]) { set("personalized", data: data) }

    // MARK: - 清理缓存

    func clearAll() {
        cache.removeAll()
        inflightTasks.values.forEach { $0.cancel() }
        inflightTasks.removeAll()
    }

    func clearHotSearch() { remove("hotSearch") }
    func clearToplist() { remove("toplist") }
}
