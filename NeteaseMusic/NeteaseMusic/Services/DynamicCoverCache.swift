//
//  DynamicCoverCache.swift
//  NeteaseMusic
//
//  Created by Claude Code on 2026-01-23.
//  统一的动态封面缓存管理器
//

import Foundation
import UIKit

// MARK: - 中国网络优化的 URLSession 配置

/// 针对 Apple Music 动态封面优化的网络会话
/// 解决中国大陆网络环境下的连接问题
class AppleMusicNetworkSession {
    static let shared = AppleMusicNetworkSession()

    // MARK: - 熔断器（Circuit Breaker）
    // 当 Apple Music CDN 连续超时时，短暂降级（减少重试次数、降低超时），而不是完全停止
    private var consecutiveFailures = 0
    private var circuitOpenUntil: Date = .distantPast
    private let circuitBreakThreshold = 5       // 连续失败 5 次后进入降级模式
    private let circuitResetInterval: TimeInterval = 60  // 降级 60 秒后恢复正常模式
    private let circuitQueue = DispatchQueue(label: "com.netease.appleMusicCircuitBreaker")

    /// 检查是否处于降级模式（减少重试，不完全停止）
    var isDegraded: Bool {
        circuitQueue.sync {
            if consecutiveFailures >= circuitBreakThreshold {
                if Date() < circuitOpenUntil {
                    return true
                }
                // 降级时间已过，重置
                consecutiveFailures = 0
                return false
            }
            return false
        }
    }

    /// 记录请求成功，重置计数
    func recordSuccess() {
        circuitQueue.async { [weak self] in
            self?.consecutiveFailures = 0
        }
    }

    /// 记录请求失败
    func recordFailure() {
        circuitQueue.async { [weak self] in
            guard let self = self else { return }
            self.consecutiveFailures += 1
            if self.consecutiveFailures >= self.circuitBreakThreshold {
                self.circuitOpenUntil = Date().addingTimeInterval(self.circuitResetInterval)
                #if DEBUG
                print("⚠️ Apple Music CDN 进入降级模式，\(Int(self.circuitResetInterval))秒后恢复")
                #endif
            }
        }
    }

    /// 优化的 URLSession，针对中国网络环境
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.default

        // 增加超时时间（中国访问 Apple 服务器较慢）
        config.timeoutIntervalForRequest = 20  // 请求超时 20 秒
        config.timeoutIntervalForResource = 45 // 资源超时 45 秒

        // 允许蜂窝网络
        config.allowsCellularAccess = true

        // 允许昂贵网络（如热点）
        config.allowsExpensiveNetworkAccess = true

        // 允许受限网络
        config.allowsConstrainedNetworkAccess = true

        // 禁用等待网络连接（立即尝试）
        config.waitsForConnectivity = false

        // 增加并发连接数
        config.httpMaximumConnectionsPerHost = 6

        // 使用管道化提高效率
        config.httpShouldUsePipelining = true

        // 设置缓存策略
        config.requestCachePolicy = .returnCacheDataElseLoad

        // 设置 URL 缓存
        let cache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,  // 50MB 内存缓存
            diskCapacity: 200 * 1024 * 1024,   // 200MB 磁盘缓存
            diskPath: "AppleMusicHLSCache"
        )
        config.urlCache = cache

        return URLSession(configuration: config)
    }()

    /// 带重试机制的数据请求
    /// - Parameters:
    ///   - url: 请求 URL
    ///   - maxRetries: 最大重试次数
    ///   - completion: 完成回调
    func fetchData(
        from url: URL,
        maxRetries: Int = 3,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) {
        // 降级模式：减少重试次数，加快失败速度
        let effectiveRetries = isDegraded ? 1 : maxRetries
        fetchDataWithRetry(url: url, retriesLeft: effectiveRetries, completion: completion)
    }

    private func fetchDataWithRetry(
        url: URL,
        retriesLeft: Int,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        // 添加 User-Agent 模拟 Safari
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        session.dataTask(with: request) { [weak self] data, response, error in
            // 检查是否需要重试
            let shouldRetry: Bool
            if let error = error {
                let nsError = error as NSError
                // 网络超时、连接失败等可重试错误
                let retryableCodes = [
                    NSURLErrorTimedOut,
                    NSURLErrorCannotConnectToHost,
                    NSURLErrorNetworkConnectionLost,
                    NSURLErrorNotConnectedToInternet,
                    NSURLErrorDNSLookupFailed,
                    NSURLErrorCannotFindHost
                ]
                shouldRetry = retryableCodes.contains(nsError.code)
            } else if let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode >= 500 {
                // 服务器错误也可重试
                shouldRetry = true
            } else {
                shouldRetry = false
            }

            if shouldRetry && retriesLeft > 0 {
                #if DEBUG
                print("🔄 网络请求失败，\(retriesLeft) 次重试剩余: \(url.lastPathComponent)")
                #endif
                // 延迟重试（指数退避）
                let delay = Double(4 - retriesLeft) * 1.0
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self?.fetchDataWithRetry(
                        url: url,
                        retriesLeft: retriesLeft - 1,
                        completion: completion
                    )
                }
            } else {
                // 记录成功或最终失败
                if error == nil && !(shouldRetry) {
                    self?.recordSuccess()
                } else if retriesLeft == 0 {
                    self?.recordFailure()
                }
                completion(data, response, error)
            }
        }.resume()
    }

    private init() {}
}

/// 统一的动态封面缓存管理器
/// 整合了原有的三个独立缓存系统：
/// - preloadedDynamicCovers (master URL缓存)
/// - downloadedAnimatedArtworkURLs (本地文件缓存)
/// - HLSVariantCache (变体URL缓存)
class DynamicCoverCache {
    static let shared = DynamicCoverCache()

    // MARK: - Configuration

    private let maxMemoryCacheCount = 20
    private let maxDiskCacheSize: Int64 = 100 * 1024 * 1024  // 100MB

    // MARK: - Cache Storage

    /// 缓存 trackId -> master m3u8 URL
    private var masterUrlCache: [Int: String] = [:]

    /// 缓存 master URL -> variant URL
    private var variantUrlCache: [String: String] = [:]

    /// 缓存 trackId -> 本地文件URL
    private var localFileCache: [Int: URL] = [:]

    // MARK: - LRU Tracking

    /// 变体URL缓存的LRU顺序
    private var variantCacheOrder: [String] = []

    /// 本地文件缓存的LRU顺序
    private var localFileCacheOrder: [Int] = []

    // MARK: - Thread Safety

    private let queue = DispatchQueue(label: "com.netease.dynamicCoverCache", attributes: .concurrent)

    // MARK: - Initialization

    private init() {
        // 监听内存警告
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Master URL Cache

    /// 获取歌曲的master m3u8 URL
    func getMasterUrl(for trackId: Int) -> String? {
        return queue.sync {
            return masterUrlCache[trackId]
        }
    }

    /// 缓存歌曲的master m3u8 URL
    func cacheMasterUrl(_ url: String, for trackId: Int) {
        queue.async(flags: .barrier) { [weak self] in
            self?.masterUrlCache[trackId] = url
        }
    }

    // MARK: - Variant URL Cache

    /// 获取master URL对应的变体URL
    func getVariantUrl(for masterUrl: String) -> String? {
        return queue.sync {
            guard let variant = variantUrlCache[masterUrl] else { return nil }
            updateVariantLRUOrder(for: masterUrl)
            return variant
        }
    }

    /// 缓存变体URL
    func cacheVariantUrl(_ variantUrl: String, for masterUrl: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.removeFromVariantOrder(masterUrl)
            self.evictVariantCacheIfNeeded()
            self.variantUrlCache[masterUrl] = variantUrl
            self.variantCacheOrder.append(masterUrl)

            #if DEBUG
            print(" DynamicCoverCache: 缓存变体URL (\(self.variantUrlCache.count)/\(self.maxMemoryCacheCount))")
            #endif
        }
    }

    /// 预加载变体URL（异步，带重试机制）
    func preloadVariant(masterUrl: String) {
        // 如果已缓存，直接返回
        if getVariantUrl(for: masterUrl) != nil {
            return
        }

        guard let url = URL(string: masterUrl) else { return }

        // 使用优化的网络会话（带重试机制）
        AppleMusicNetworkSession.shared.fetchData(from: url, maxRetries: 3) { [weak self] data, _, error in
            guard let self = self,
                  let data = data,
                  let text = String(data: data, encoding: .utf8) else {
                #if DEBUG
                if let error = error {
                    print("❌ 预加载变体失败: \(error.localizedDescription)")
                }
                #endif
                return
            }

            // 使用 HLSParser 选择「可播放」变体。
            // 重点：
            // - 过滤 I-FRAME trick-play（否则会出现"像一帧一帧"的幻灯片效果）
            // - 限制最大分辨率，避免选择过高码率导致卡顿/掉帧
            // - 中国网络环境下降低分辨率以减少缓冲
            let maxPixels = 720 * 960  // 降低分辨率，提高加载成功率
            if let variantUrl = HLSParser.shared.selectVariant(
                from: text,
                baseUrl: masterUrl,
                strategy: .preferAspectRatio(width: 3, height: 4, maxPixels: maxPixels)
            ) {
                self.cacheVariantUrl(variantUrl, for: masterUrl)
                #if DEBUG
                print("✅ 预加载变体成功: \(variantUrl.suffix(50))")
                #endif
            } else {
                // 如果 master 本身就是变体（没有 #EXT-X-STREAM-INF），这里缓存自身以便后续直接使用。
                self.cacheVariantUrl(masterUrl, for: masterUrl)
            }
        }
    }

    // MARK: - Local File Cache

    /// 获取歌曲的本地文件URL
    func getLocalFile(for trackId: Int) -> URL? {
        return queue.sync {
            guard let fileUrl = localFileCache[trackId] else { return nil }
            updateLocalFileLRUOrder(for: trackId)
            return fileUrl
        }
    }

    /// 缓存本地文件URL
    func cacheLocalFile(_ fileUrl: URL, for trackId: Int) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.removeFromLocalFileOrder(trackId)
            self.evictLocalFileCacheIfNeeded()
            self.localFileCache[trackId] = fileUrl
            self.localFileCacheOrder.append(trackId)

            #if DEBUG
            print(" DynamicCoverCache: 缓存本地文件 (\(self.localFileCache.count)/\(self.maxMemoryCacheCount))")
            #endif
        }
    }
    
    /// 清除指定歌曲的本地文件缓存
    func clearLocalFile(for trackId: Int) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            if let url = self.localFileCache.removeValue(forKey: trackId) {
                try? FileManager.default.removeItem(at: url)
                #if DEBUG
                print("⚠️ DynamicCoverCache: 已清除无效的本地文件缓存")
                #endif
            }
            
            if let index = self.localFileCacheOrder.firstIndex(of: trackId) {
                self.localFileCacheOrder.remove(at: index)
            }
        }
    }
    
    // MARK: - Cache Management

    /// 清除所有缓存
    func clearAll() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self.masterUrlCache.removeAll()
            self.variantUrlCache.removeAll()
            self.variantCacheOrder.removeAll()

            // 删除本地文件
            for (_, url) in self.localFileCache {
                try? FileManager.default.removeItem(at: url)
            }
            self.localFileCache.removeAll()
            self.localFileCacheOrder.removeAll()

            #if DEBUG
            print(" DynamicCoverCache: 已清除所有缓存")
            #endif
        }
    }

    /// 清理过期的磁盘缓存
    func cleanExpiredDiskCache() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let cacheDir = self.getAnimatedArtworkDirectory()
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else {
                return
            }

            var totalSize: Int64 = 0
            var fileInfos: [(url: URL, size: Int64, date: Date)] = []

            // 收集文件信息
            for fileUrl in files {
                guard let resourceValues = try? fileUrl.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                      let size = resourceValues.fileSize,
                      let date = resourceValues.contentModificationDate else {
                    continue
                }

                totalSize += Int64(size)
                fileInfos.append((url: fileUrl, size: Int64(size), date: date))
            }

            // 如果超过限制，删除最旧的文件
            if totalSize > self.maxDiskCacheSize {
                // 按修改日期排序（最旧的在前）
                fileInfos.sort { $0.date < $1.date }

                var deletedSize: Int64 = 0
                let targetDeleteSize = totalSize - self.maxDiskCacheSize

                for fileInfo in fileInfos {
                    if deletedSize >= targetDeleteSize {
                        break
                    }

                    try? FileManager.default.removeItem(at: fileInfo.url)
                    deletedSize += fileInfo.size

                    // 从缓存中移除
                    if let trackId = self.localFileCache.first(where: { $0.value == fileInfo.url })?.key {
                        self.localFileCache.removeValue(forKey: trackId)
                        if let index = self.localFileCacheOrder.firstIndex(of: trackId) {
                            self.localFileCacheOrder.remove(at: index)
                        }
                    }
                }

                #if DEBUG
                print(" DynamicCoverCache: 清理磁盘缓存 \(deletedSize/1024/1024)MB")
                #endif
            }
        }
    }

    /// 获取磁盘缓存大小
    func getDiskCacheSize() -> Int64 {
        let cacheDir = getAnimatedArtworkDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for fileUrl in files {
            if let resourceValues = try? fileUrl.resourceValues(forKeys: [.fileSizeKey]),
               let size = resourceValues.fileSize {
                totalSize += Int64(size)
            }
        }

        return totalSize
    }

    // MARK: - Private Helpers

    /// 获取动画封面缓存目录
    private func getAnimatedArtworkDirectory() -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let animatedArtworkDir = cacheDir.appendingPathComponent("AnimatedArtwork", isDirectory: true)

        // 确保目录存在
        if !FileManager.default.fileExists(atPath: animatedArtworkDir.path) {
            try? FileManager.default.createDirectory(at: animatedArtworkDir, withIntermediateDirectories: true)
        }

        return animatedArtworkDir
    }

    /// 更新变体缓存的LRU顺序
    private func updateVariantLRUOrder(for key: String) {
        if let index = variantCacheOrder.firstIndex(of: key) {
            variantCacheOrder.remove(at: index)
            variantCacheOrder.append(key)
        }
    }

    /// 从变体缓存顺序中移除
    private func removeFromVariantOrder(_ key: String) {
        if let index = variantCacheOrder.firstIndex(of: key) {
            variantCacheOrder.remove(at: index)
        }
    }

    /// 驱逐变体缓存（如果需要）
    private func evictVariantCacheIfNeeded() {
        while variantCacheOrder.count >= maxMemoryCacheCount {
            if let oldest = variantCacheOrder.first {
                variantCacheOrder.removeFirst()
                variantUrlCache.removeValue(forKey: oldest)

                #if DEBUG
                print(" DynamicCoverCache: 驱逐最旧的变体缓存")
                #endif
            }
        }
    }

    /// 更新本地文件缓存的LRU顺序
    private func updateLocalFileLRUOrder(for trackId: Int) {
        if let index = localFileCacheOrder.firstIndex(of: trackId) {
            localFileCacheOrder.remove(at: index)
            localFileCacheOrder.append(trackId)
        }
    }

    /// 从本地文件缓存顺序中移除
    private func removeFromLocalFileOrder(_ trackId: Int) {
        if let index = localFileCacheOrder.firstIndex(of: trackId) {
            localFileCacheOrder.remove(at: index)
        }
    }

    /// 驱逐本地文件缓存（如果需要）
    private func evictLocalFileCacheIfNeeded() {
        while localFileCacheOrder.count >= maxMemoryCacheCount {
            if let oldest = localFileCacheOrder.first {
                localFileCacheOrder.removeFirst()

                // 删除磁盘文件
                if let url = localFileCache.removeValue(forKey: oldest) {
                    try? FileManager.default.removeItem(at: url)

                    #if DEBUG
                    print(" DynamicCoverCache: 驱逐最旧的本地文件缓存")
                    #endif
                }
            }
        }
    }

    /// 处理内存警告
    @objc private func handleMemoryWarning() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // 清除变体URL缓存
            self.variantUrlCache.removeAll()
            self.variantCacheOrder.removeAll()

            #if DEBUG
            print(" DynamicCoverCache: 内存警告，已清理变体缓存")
            #endif
        }
    }
}
