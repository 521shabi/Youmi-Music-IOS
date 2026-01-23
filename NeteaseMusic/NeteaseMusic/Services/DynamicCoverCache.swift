//
//  DynamicCoverCache.swift
//  NeteaseMusic
//
//  Created by Claude Code on 2026-01-23.
//  统一的动态封面缓存管理器
//

import Foundation
import UIKit

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

    /// 预加载变体URL（异步）
    func preloadVariant(masterUrl: String) {
        // 如果已缓存，直接返回
        if getVariantUrl(for: masterUrl) != nil {
            return
        }

        guard let url = URL(string: masterUrl) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self,
                  let data = data,
                  let text = String(data: data, encoding: .utf8) else {
                return
            }

            // 使用HLSParser解析并选择最佳变体
            let variants = HLSParser.shared.parseVariants(from: text)
            guard let best = variants.max(by: { a, b in
                if a.pixelCount != b.pixelCount {
                    return a.pixelCount < b.pixelCount
                }
                return a.bandwidth < b.bandwidth
            }) else {
                return
            }

            let variantUrl = HLSParser.shared.resolveUrl(best.url, baseUrl: masterUrl)
            self.cacheVariantUrl(variantUrl, for: masterUrl)
        }.resume()
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
