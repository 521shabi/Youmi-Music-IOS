import Foundation
import AVFoundation

// MARK: - 下载状态
enum AudioDownloadState: Equatable {
    case idle
    case downloading(progress: Double)
    case completed(localURL: URL)
    case failed(String)
}

// MARK: - 缓存的音频文件
struct CachedAudioFile {
    let trackId: Int
    let localURL: URL
    let createdAt: Date
    let fileSize: Int64
}

// MARK: - 音频下载服务
/// 下载音频文件到本地，供 DJMixer 使用
final class AudioDownloadService: ObservableObject {
    static let shared = AudioDownloadService()
    
    // MARK: - Published
    @Published var downloadStates: [Int: AudioDownloadState] = [:]
    
    // MARK: - 配置
    private let cacheDirectory: URL
    private let maxCacheSize: Int64 = 500 * 1024 * 1024  // 500MB 缓存上限
    private let maxCacheAge: TimeInterval = 24 * 3600     // 24小时过期
    
    // MARK: - 内部状态
    private var downloadTasks: [Int: URLSessionDownloadTask] = [:]
    private var cachedFiles: [Int: CachedAudioFile] = [:]
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "audioDownload.queue")
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }()
    
    // MARK: - 初始化
    
    /// 根据 HTTP 响应和 URL 确定文件扩展名
    private func getFileExtension(from response: HTTPURLResponse, url: URL) -> String {
        // 优先从 URL 路径判断（更准确，因为 Content-Type 可能错误）
        let urlPath = url.path.lowercased()
        // 检查 URL 路径中的文件扩展名（包括查询参数前的部分）
        if urlPath.contains(".flac") {
            return "flac"
        } else if urlPath.contains(".m4a") {
            return "m4a"
        } else if urlPath.contains(".mp3") {
            return "mp3"
        } else if urlPath.contains(".aac") {
            return "m4a"  // AAC 使用 m4a 容器
        } else if urlPath.contains(".ogg") {
            return "ogg"
        } else if urlPath.contains(".wav") {
            return "wav"
        }
        
        // 其次从 Content-Type 判断
        if let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
            if contentType.contains("audio/flac") || contentType.contains("audio/x-flac") {
                return "flac"
            } else if contentType.contains("audio/mp4") || contentType.contains("audio/aac") || contentType.contains("audio/x-m4a") {
                return "m4a"
            } else if contentType.contains("audio/ogg") {
                return "ogg"
            } else if contentType.contains("audio/wav") {
                return "wav"
            } else if contentType.contains("audio/mpeg") || contentType.contains("audio/mp3") {
                return "mp3"
            }
        }
        
        // 默认使用 m4a
        return "m4a"
    }
    
    private init() {
        // 创建缓存目录
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDir.appendingPathComponent("AudioCache", isDirectory: true)
        
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            print("❌ 创建音频缓存目录失败: \(error)")
            #endif
        }
        
        // 加载已缓存的文件信息
        loadCachedFiles()
        
        // 清理过期缓存
        cleanExpiredCache()
    }
    
    // MARK: - 公开 API
    
    /// 获取本地音频文件（如果已缓存）
    func getCachedFile(trackId: Int) -> URL? {
        guard let cached = cachedFiles[trackId] else { return nil }
        
        // 检查文件是否存在
        guard fileManager.fileExists(atPath: cached.localURL.path) else {
            cachedFiles.removeValue(forKey: trackId)
            return nil
        }
        
        // 检查是否过期
        if Date().timeIntervalSince(cached.createdAt) > maxCacheAge {
            try? fileManager.removeItem(at: cached.localURL)
            cachedFiles.removeValue(forKey: trackId)
            return nil
        }
        
        #if DEBUG
        print("✅ 音频缓存命中: \(trackId)")
        #endif
        
        return cached.localURL
    }
    
    /// 下载音频文件
    /// - Parameters:
    ///   - url: 远程音频 URL
    ///   - trackId: 歌曲 ID
    ///   - headers: HTTP 请求头
    /// - Returns: 本地文件 URL
    func downloadAudio(from url: URL, trackId: Int, headers: [String: String]? = nil) async throws -> URL {
        // 检查缓存
        if let cachedURL = getCachedFile(trackId: trackId) {
            // 验证缓存文件是否有效
            do {
                _ = try AVAudioFile(forReading: cachedURL)
                #if DEBUG
                print("✅ 使用有效缓存: \(cachedURL.lastPathComponent)")
                #endif
                return cachedURL
            } catch {
                // 缓存文件无效，删除并重新下载
                #if DEBUG
                print("⚠️ 缓存文件无效，删除并重新下载: \(cachedURL.lastPathComponent)")
                #endif
                try? fileManager.removeItem(at: cachedURL)
                cachedFiles.removeValue(forKey: trackId)
            }
        }

        #if DEBUG
        print("📥 开始下载音频: \(url.absoluteString.prefix(100))...")
        #endif

        // 更新状态
        await MainActor.run {
            downloadStates[trackId] = .downloading(progress: 0)
        }
        
        // 创建请求
        var request = URLRequest(url: url)
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        // 默认请求头（网易云防盗链）
        if headers == nil {
            request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            request.setValue("https://music.163.com", forHTTPHeaderField: "Origin")
        }

        do {
            let (tempURL, response) = try await urlSession.download(for: request)

            // 检查响应
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AudioDownloadError.invalidResponse
            }

            #if DEBUG
            print("📥 下载响应: HTTP \(httpResponse.statusCode), Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
            #endif

            guard (200...299).contains(httpResponse.statusCode) else {
                #if DEBUG
                print("❌ HTTP 错误: \(httpResponse.statusCode)")
                #endif
                throw AudioDownloadError.invalidResponse
            }

            // 根据 Content-Type 确定文件扩展名
            let fileExtension = getFileExtension(from: httpResponse, url: url)
            let localURL = cacheDirectory.appendingPathComponent("\(trackId).\(fileExtension)")

            // 移动到缓存目录
            if fileManager.fileExists(atPath: localURL.path) {
                try fileManager.removeItem(at: localURL)
            }
            try fileManager.moveItem(at: tempURL, to: localURL)

            // 获取文件大小
            let attributes = try fileManager.attributesOfItem(atPath: localURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            #if DEBUG
            print("📥 下载完成: \(fileSize / 1024) KB")
            // 检查文件头部（判断是否是 HTML 或 m3u8）
            if let fileHandle = FileHandle(forReadingAtPath: localURL.path) {
                let headerData = fileHandle.readData(ofLength: 100)
                fileHandle.closeFile()
                if let headerString = String(data: headerData, encoding: .utf8) {
                    let preview = headerString.prefix(50).replacingOccurrences(of: "\n", with: " ")
                    print("📥 文件头部: \(preview)")
                    if headerString.contains("<!DOCTYPE") || headerString.contains("<html") || headerString.contains("#EXTM3U") {
                        print("❌ 下载的是网页或播放列表，不是音频文件！")
                    }
                }
            }
            #endif

            // 验证是否为有效音频文件
            do {
                let audioFile = try AVAudioFile(forReading: localURL)
                #if DEBUG
                print("✅ 音频文件验证通过: \(audioFile.length) frames, \(audioFile.fileFormat.sampleRate) Hz")
                #endif
            } catch {
                // 删除无效文件
                try? fileManager.removeItem(at: localURL)
                #if DEBUG
                print("❌ 下载的文件不是有效音频: \(error.localizedDescription)")
                #endif
                throw AudioDownloadError.invalidAudioFormat
            }
            
            // 缓存信息
            let cached = CachedAudioFile(
                trackId: trackId,
                localURL: localURL,
                createdAt: Date(),
                fileSize: fileSize
            )
            cachedFiles[trackId] = cached
            
            // 更新状态
            await MainActor.run {
                downloadStates[trackId] = .completed(localURL: localURL)
            }
            
            #if DEBUG
            print("✅ 音频下载完成: \(trackId), 大小: \(fileSize / 1024)KB")
            #endif
            
            // 检查缓存大小
            checkCacheSize()
            
            return localURL
            
        } catch {
            await MainActor.run {
                downloadStates[trackId] = .failed(error.localizedDescription)
            }
            throw error
        }
    }
    
    /// 预下载音频（后台执行）
    func predownload(from url: URL, trackId: Int, headers: [String: String]? = nil) {
        // 如果已缓存，跳过
        if getCachedFile(trackId: trackId) != nil { return }
        
        Task(priority: .utility) {
            do {
                _ = try await downloadAudio(from: url, trackId: trackId, headers: headers)
            } catch {
                #if DEBUG
                print("⚠️ 预下载失败: \(trackId) - \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    /// 取消下载
    func cancelDownload(trackId: Int) {
        downloadTasks[trackId]?.cancel()
        downloadTasks.removeValue(forKey: trackId)
        
        Task { @MainActor in
            downloadStates[trackId] = .idle
        }
    }
    
    /// 清除指定歌曲的缓存
    func clearCache(trackId: Int) {
        if let cached = cachedFiles[trackId] {
            try? fileManager.removeItem(at: cached.localURL)
            cachedFiles.removeValue(forKey: trackId)
        }
        
        Task { @MainActor in
            downloadStates.removeValue(forKey: trackId)
        }
    }
    
    /// 清除所有缓存
    func clearAllCache() {
        for cached in cachedFiles.values {
            try? fileManager.removeItem(at: cached.localURL)
        }
        cachedFiles.removeAll()
        
        Task { @MainActor in
            downloadStates.removeAll()
        }
        
        #if DEBUG
        print("🗑️ 已清除所有音频缓存")
        #endif
    }
    
    /// 获取缓存大小
    var cacheSize: Int64 {
        cachedFiles.values.reduce(0) { $0 + $1.fileSize }
    }
    
    /// 格式化缓存大小
    var formattedCacheSize: String {
        let size = cacheSize
        if size < 1024 * 1024 {
            return "\(size / 1024) KB"
        } else {
            return String(format: "%.1f MB", Double(size) / 1024 / 1024)
        }
    }
    
    // MARK: - 私有方法
    
    /// 加载已缓存的文件
    private func loadCachedFiles() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]) else {
            return
        }
        
        for fileURL in files {
            guard let trackIdStr = fileURL.deletingPathExtension().lastPathComponent.components(separatedBy: "_").first,
                  let trackId = Int(trackIdStr) else {
                continue
            }
            
            do {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                let createdAt = attributes[.creationDate] as? Date ?? Date()
                
                cachedFiles[trackId] = CachedAudioFile(
                    trackId: trackId,
                    localURL: fileURL,
                    createdAt: createdAt,
                    fileSize: fileSize
                )
            } catch {
                continue
            }
        }
        
        #if DEBUG
        print("📂 已加载 \(cachedFiles.count) 个音频缓存")
        #endif
    }
    
    /// 清理过期缓存
    private func cleanExpiredCache() {
        let now = Date()
        var expiredIds: [Int] = []
        
        for (trackId, cached) in cachedFiles {
            if now.timeIntervalSince(cached.createdAt) > maxCacheAge {
                try? fileManager.removeItem(at: cached.localURL)
                expiredIds.append(trackId)
            }
        }
        
        for id in expiredIds {
            cachedFiles.removeValue(forKey: id)
        }
        
        #if DEBUG
        if !expiredIds.isEmpty {
            print("🗑️ 清理 \(expiredIds.count) 个过期音频缓存")
        }
        #endif
    }
    
    /// 检查缓存大小，超过上限时清理最旧的
    private func checkCacheSize() {
        var totalSize = cacheSize
        
        guard totalSize > maxCacheSize else { return }
        
        // 按创建时间排序，清理最旧的
        let sorted = cachedFiles.values.sorted { $0.createdAt < $1.createdAt }
        
        for cached in sorted {
            guard totalSize > maxCacheSize else { break }
            
            try? fileManager.removeItem(at: cached.localURL)
            cachedFiles.removeValue(forKey: cached.trackId)
            totalSize -= cached.fileSize
            
            #if DEBUG
            print("🗑️ 缓存超限，清理: \(cached.trackId)")
            #endif
        }
    }
}

// MARK: - 错误类型
enum AudioDownloadError: Error, LocalizedError {
    case invalidResponse
    case downloadFailed
    case fileNotFound
    case invalidAudioFormat

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无效的服务器响应"
        case .downloadFailed: return "下载失败"
        case .fileNotFound: return "文件未找到"
        case .invalidAudioFormat: return "无效的音频格式（可能是流媒体链接）"
        }
    }
}
