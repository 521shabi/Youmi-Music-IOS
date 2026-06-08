import Foundation
import AVFoundation
import UIKit
import UniformTypeIdentifiers

// MARK: - 本地音乐服务
@MainActor
class LocalMusicService: ObservableObject {
    static let shared = LocalMusicService()

    private let localTracksKey = "local_music_tracks"
    private let localMusicDirectory = "LocalMusic"

    @Published var localTracks: [LocalTrack] = []
    @Published var isImporting = false
    @Published var importProgress: Double = 0

    private init() {
        loadLocalTracks()
        createLocalMusicDirectoryIfNeeded()
    }
    
    // MARK: - 目录管理
    
    /// 获取本地音乐存储目录
    var localMusicDirectoryURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent(localMusicDirectory, isDirectory: true)
    }
    
    /// 创建本地音乐目录
    private func createLocalMusicDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: localMusicDirectoryURL.path) {
            do {
                try fm.createDirectory(at: localMusicDirectoryURL, withIntermediateDirectories: true)
                #if DEBUG
                print("✅ 已创建本地音乐目录: \(localMusicDirectoryURL.path)")
                #endif
            } catch {
                #if DEBUG
                print("❌ 创建本地音乐目录失败: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    // MARK: - 导入音频文件
    
    /// 导入单个音频文件
    func importAudioFile(from sourceURL: URL) async throws -> LocalTrack {
        // 开始访问安全范围资源
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        await MainActor.run {
            isImporting = true
            importProgress = 0.1
        }
        
        // 获取文件信息
        let fileName = sourceURL.lastPathComponent
        let fileExtension = sourceURL.pathExtension.lowercased()
        
        // 检查格式支持
        guard AudioFormat.supportedExtensions.contains(fileExtension) else {
            throw LocalMusicError.unsupportedFormat(fileExtension)
        }
        
        await MainActor.run { importProgress = 0.2 }
        
        // 复制文件到本地目录
        let destinationURL = localMusicDirectoryURL.appendingPathComponent(fileName)
        
        // 如果文件已存在，生成唯一名称
        let finalURL = getUniqueFileURL(for: destinationURL)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: finalURL)
        } catch {
            throw LocalMusicError.copyFailed(error.localizedDescription)
        }
        
        await MainActor.run { importProgress = 0.4 }
        
        // 提取元数据
        let localTrack = try await extractMetadata(from: finalURL)
        
        await MainActor.run { importProgress = 0.9 }
        
        // 添加到列表
        await MainActor.run {
            localTracks.insert(localTrack, at: 0)
            saveLocalTracks()
            isImporting = false
            importProgress = 1.0
        }
        
        #if DEBUG
        print("✅ 导入成功: \(localTrack.displayTitle)")
        #endif
        
        return localTrack
    }
    
    /// 批量导入音频文件
    func importAudioFiles(from sourceURLs: [URL]) async -> [LocalTrack] {
        var importedTracks: [LocalTrack] = []
        let total = sourceURLs.count
        
        await MainActor.run {
            isImporting = true
            importProgress = 0
        }
        
        for (index, url) in sourceURLs.enumerated() {
            do {
                let track = try await importAudioFile(from: url)
                importedTracks.append(track)
            } catch {
                #if DEBUG
                print("❌ 导入失败: \(url.lastPathComponent) - \(error.localizedDescription)")
                #endif
            }
            
            await MainActor.run {
                importProgress = Double(index + 1) / Double(total)
            }
        }
        
        await MainActor.run {
            isImporting = false
        }
        
        return importedTracks
    }
    
    /// 获取唯一文件URL（避免覆盖）
    private func getUniqueFileURL(for url: URL) -> URL {
        let fm = FileManager.default
        var finalURL = url
        var counter = 1
        
        while fm.fileExists(atPath: finalURL.path) {
            let nameWithoutExt = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let newName = "\(nameWithoutExt)_\(counter).\(ext)"
            finalURL = url.deletingLastPathComponent().appendingPathComponent(newName)
            counter += 1
        }
        
        return finalURL
    }
    
    // MARK: - 元数据提取
    
    /// 提取音频文件元数据
    func extractMetadata(from fileURL: URL) async throws -> LocalTrack {
        let asset = AVURLAsset(url: fileURL)
        
        // 获取文件属性
        let fileName = fileURL.lastPathComponent
        let fileExtension = fileURL.pathExtension.lowercased()
        
        // 获取文件大小
        var fileSize: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        }
        
        // 获取时长
        var duration: Double = 0
        do {
            let durationTime = try await asset.load(.duration)
            duration = CMTimeGetSeconds(durationTime)
        } catch {
            #if DEBUG
            print("⚠️ 获取时长失败: \(error.localizedDescription)")
            #endif
        }
        
        // 提取 ID3/iTunes 元数据
        var title = ""
        var artist = ""
        var album = ""
        var artworkData: Data?
        var embeddedLyrics: String?
        
        // 使用 AVMetadataItem 提取元数据
        let metadata = try await asset.load(.metadata)
        
        for item in metadata {
            guard let key = item.commonKey?.rawValue else { continue }
            
            switch key {
            case AVMetadataKey.commonKeyTitle.rawValue:
                title = try await item.load(.stringValue) ?? ""
            case AVMetadataKey.commonKeyArtist.rawValue:
                artist = try await item.load(.stringValue) ?? ""
            case AVMetadataKey.commonKeyAlbumName.rawValue:
                album = try await item.load(.stringValue) ?? ""
            case AVMetadataKey.commonKeyArtwork.rawValue:
                artworkData = try await item.load(.dataValue)
            default:
                break
            }
        }
        
        // 尝试提取内嵌歌词（ID3 USLT 标签）
        embeddedLyrics = await extractEmbeddedLyrics(from: asset)
        
        // 如果标题为空，使用文件名
        if title.isEmpty {
            title = fileURL.deletingPathExtension().lastPathComponent
        }
        
        // 压缩封面图片（避免存储过大）
        if let data = artworkData, data.count > 500_000 {
            artworkData = compressArtwork(data: data, maxSize: 300)
        }
        
        return LocalTrack(
            fileName: fileName,
            fileURL: fileURL,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            fileSize: fileSize,
            format: fileExtension,
            bitrate: nil,
            sampleRate: nil,
            artworkData: artworkData,
            embeddedLyrics: embeddedLyrics
        )
    }
    
    /// 提取内嵌歌词
    private func extractEmbeddedLyrics(from asset: AVURLAsset) async -> String? {
        // 方法1: 从 AVAsset 的 lyrics 属性获取
        do {
            let lyrics = try await asset.load(.lyrics)
            if let lyrics = lyrics, !lyrics.isEmpty {
                #if DEBUG
                print("✅ 从 AVAsset.lyrics 提取到歌词")
                #endif
                return lyrics
            }
        } catch {
            #if DEBUG
            print("⚠️ 从 AVAsset.lyrics 提取歌词失败: \(error.localizedDescription)")
            #endif
        }
        
        // 方法2: 从 ID3 元数据提取 (USLT/SYLT 标签)
        do {
            let metadata = try await asset.load(.metadata)
            
            for item in metadata {
                // 检查 ID3v2 歌词标签
                if let identifier = item.identifier {
                    let id = identifier.rawValue
                    
                    // USLT - 非同步歌词
                    if id.contains("USLT") || id.contains("uslt") || id.contains("lyrics") {
                        if let lyrics = try await item.load(.stringValue), !lyrics.isEmpty {
                            #if DEBUG
                            print("✅ 从 ID3 USLT 标签提取到歌词")
                            #endif
                            return lyrics
                        }
                    }
                    
                    // iTunes 歌词
                    if id.contains("©lyr") || id.contains("lyr") {
                        if let lyrics = try await item.load(.stringValue), !lyrics.isEmpty {
                            #if DEBUG
                            print("✅ 从 iTunes 歌词标签提取到歌词")
                            #endif
                            return lyrics
                        }
                    }
                }
                
                // 检查 key
                if let key = item.key as? String {
                    if key.lowercased().contains("lyric") || key.lowercased().contains("uslt") {
                        if let lyrics = try await item.load(.stringValue), !lyrics.isEmpty {
                            return lyrics
                        }
                    }
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ 从 ID3 元数据提取歌词失败: \(error.localizedDescription)")
            #endif
        }
        
        return nil
    }
    
    /// 压缩封面图片
    private func compressArtwork(data: Data, maxSize: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return data }
        
        let size = CGSize(width: maxSize, height: maxSize)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage?.jpegData(compressionQuality: 0.8)
    }
    
    // MARK: - 下载歌曲保存
    
    /// 保存下载的歌曲到本地音乐库
    /// - Parameters:
    ///   - tempFileURL: 临时文件URL
    ///   - track: 原始 Track 信息
    ///   - fileExtension: 文件扩展名
    ///   - coverData: 封面图片数据
    func saveDownloadedTrack(
        tempFileURL: URL,
        track: Track,
        fileExtension: String,
        coverData: Data?
    ) async throws -> LocalTrack {
        // 生成文件名: 歌手 - 歌名.ext
        let safeArtist = track.artistName.replacingOccurrences(of: "/", with: "_")
        let safeName = track.name.replacingOccurrences(of: "/", with: "_")
        let fileName = "\(safeArtist) - \(safeName).\(fileExtension)"
        
        let destinationURL = localMusicDirectoryURL.appendingPathComponent(fileName)
        let finalURL = getUniqueFileURL(for: destinationURL)
        
        // 移动文件到本地音乐目录
        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: tempFileURL, to: finalURL)
        } catch {
            throw LocalMusicError.copyFailed(error.localizedDescription)
        }
        
        // 获取文件大小
        var fileSize: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: finalURL.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        }
        
        // 压缩封面图片
        var artworkData: Data? = coverData
        if let data = coverData, data.count > 500_000 {
            artworkData = compressArtwork(data: data, maxSize: 300)
        }
        
        // 创建 LocalTrack
        let localTrack = LocalTrack(
            fileName: finalURL.lastPathComponent,
            fileURL: finalURL,
            title: track.name,
            artist: track.artistName,
            album: track.albumName,
            duration: track.durationSeconds,
            fileSize: fileSize,
            format: fileExtension,
            bitrate: nil,
            sampleRate: nil,
            artworkData: artworkData,
            embeddedLyrics: nil,
            addedDate: Date(),
            sourceTrackId: track.id,
            sourceCoverUrl: track.coverUrl
        )
        
        // 添加到列表
        await MainActor.run {
            localTracks.insert(localTrack, at: 0)
            saveLocalTracks()
        }
        
        #if DEBUG
        print("✅ 下载保存成功: \(localTrack.displayTitle)")
        #endif
        
        return localTrack
    }
    
    // MARK: - 歌词侧载（.lrc）
    
    /// 查找与音频同名的 .lrc/.txt 歌词文件
    func findSidecarLyrics(for track: LocalTrack) -> String? {
        let base = track.fileURL.deletingPathExtension()
        let candidates = [base.appendingPathExtension("lrc"), base.appendingPathExtension("txt")]
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path),
               let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
                return text
            }
        }
        return nil
    }
    
    /// 将歌词以 .lrc 侧载文件的形式保存到同目录
    @discardableResult
    func saveSidecarLyrics(for track: LocalTrack, lrcContent: String) -> URL? {
        let lrcURL = track.fileURL.deletingPathExtension().appendingPathExtension("lrc")
        do {
            try lrcContent.data(using: .utf8)?.write(to: lrcURL, options: [.atomic])
            #if DEBUG
            print("✅ 已保存侧载歌词: \(lrcURL.lastPathComponent)")
            #endif
            return lrcURL
        } catch {
            #if DEBUG
            print("⚠️ 保存侧载歌词失败: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
    
    /// 更新内存中的本地曲目歌词并落盘列表
    func updateLocalTrackLyrics(trackId: UUID, lyrics: String) {
        if let idx = localTracks.firstIndex(where: { $0.id == trackId }) {
            var t = localTracks[idx]
            // 重新构造以更新 embeddedLyrics
            let updated = LocalTrack(
                id: t.id,
                fileName: t.fileName,
                fileURL: t.fileURL,
                title: t.title,
                artist: t.artist,
                album: t.album,
                duration: t.duration,
                fileSize: t.fileSize,
                format: t.format,
                bitrate: t.bitrate,
                sampleRate: t.sampleRate,
                artworkData: t.artworkData,
                embeddedLyrics: lyrics,
                addedDate: t.addedDate,
                sourceTrackId: t.sourceTrackId,
                sourceCoverUrl: t.sourceCoverUrl
            )
            localTracks[idx] = updated
            saveLocalTracks()
        }
    }
    
    // MARK: - 歌曲管理
    
    /// 删除本地歌曲
    func deleteTrack(_ track: LocalTrack) {
        // 从列表移除
        localTracks.removeAll { $0.id == track.id }
        
        // 删除文件
        do {
            try FileManager.default.removeItem(at: track.fileURL)
            #if DEBUG
            print("✅ 已删除文件: \(track.fileName)")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ 删除文件失败: \(error.localizedDescription)")
            #endif
        }
        
        saveLocalTracks()
    }
    
    /// 批量删除
    func deleteTracks(_ tracks: [LocalTrack]) {
        for track in tracks {
            deleteTrack(track)
        }
    }
    
    /// 清空所有本地歌曲
    func clearAllTracks() {
        for track in localTracks {
            try? FileManager.default.removeItem(at: track.fileURL)
        }
        localTracks.removeAll()
        saveLocalTracks()
    }
    
    /// 刷新本地音乐库（扫描目录）
    func refreshLibrary() async {
        let fm = FileManager.default
        
        guard let contents = try? fm.contentsOfDirectory(
            at: localMusicDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        
        // 找出新文件（不在当前列表中的）
        let existingURLs = Set(localTracks.map { $0.fileURL.lastPathComponent })
        let newFiles = contents.filter { url in
            let ext = url.pathExtension.lowercased()
            return AudioFormat.supportedExtensions.contains(ext) &&
                   !existingURLs.contains(url.lastPathComponent)
        }
        
        // 导入新文件
        for fileURL in newFiles {
            do {
                let track = try await extractMetadata(from: fileURL)
                await MainActor.run {
                    localTracks.append(track)
                }
            } catch {
                #if DEBUG
                print("⚠️ 扫描文件失败: \(fileURL.lastPathComponent) - \(error)")
                #endif
            }
        }
        
        // 移除不存在的文件
        await MainActor.run {
            localTracks.removeAll { track in
                !fm.fileExists(atPath: track.fileURL.path)
            }
            saveLocalTracks()
        }
    }
    
    // MARK: - 持久化
    
    /// 保存本地歌曲列表
    private func saveLocalTracks() {
        do {
            let data = try JSONEncoder().encode(localTracks)
            UserDefaults.standard.set(data, forKey: localTracksKey)
            #if DEBUG
            print("✅ 已保存 \(localTracks.count) 首本地歌曲")
            #endif
        } catch {
            #if DEBUG
            print("❌ 保存本地歌曲失败: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// 加载本地歌曲列表
    private func loadLocalTracks() {
        guard let data = UserDefaults.standard.data(forKey: localTracksKey),
              let tracks = try? JSONDecoder().decode([LocalTrack].self, from: data) else {
            return
        }
        
        // 验证文件是否存在
        localTracks = tracks.filter { track in
            FileManager.default.fileExists(atPath: track.fileURL.path)
        }
        
        #if DEBUG
        print("✅ 已加载 \(localTracks.count) 首本地歌曲")
        #endif
    }
    
    // MARK: - 获取歌词
    
    /// 获取本地歌曲的歌词
    func getLyrics(for track: LocalTrack) -> LocalLyricParseResult {
        return LocalLyricParseResult(lyrics: track.embeddedLyrics)
    }
    
    /// 检查文件是否支持
    func isSupported(fileURL: URL) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        return AudioFormat.supportedExtensions.contains(ext)
    }
    
    // MARK: - 分享功能

    /// 分享本地歌曲文件
    func shareTrack(_ track: LocalTrack, from viewController: UIViewController? = nil) {
        let fileURL = track.fileURL

        // 确保文件存在
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            #if DEBUG
            print("❌ 分享失败：文件不存在")
            #endif
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )

        // 获取当前视图控制器
        if let vc = viewController ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController {

            // iPad 需要设置 popover
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = vc.view
                popover.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            vc.present(activityVC, animated: true)
        }
    }

    /// 批量分享歌曲
    func shareTracks(_ tracks: [LocalTrack], from viewController: UIViewController? = nil) {
        let fileURLs = tracks.compactMap { track -> URL? in
            guard FileManager.default.fileExists(atPath: track.fileURL.path) else { return nil }
            return track.fileURL
        }

        guard !fileURLs.isEmpty else { return }

        let activityVC = UIActivityViewController(
            activityItems: fileURLs,
            applicationActivities: nil
        )

        if let vc = viewController ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController {

            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = vc.view
                popover.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            vc.present(activityVC, animated: true)
        }
    }

    // MARK: - 支持的文件类型（用于文件选择器）

    var supportedContentTypes: [UTType] {
        [
            .mp3,
            .mpeg4Audio,
            .aiff,
            .wav,
            UTType(filenameExtension: "flac") ?? .audio,
            UTType(filenameExtension: "ogg") ?? .audio,
            .audio
        ]
    }
}

// MARK: - 错误类型
enum LocalMusicError: Error, LocalizedError {
    case unsupportedFormat(String)
    case copyFailed(String)
    case metadataExtractionFailed(String)
    case fileNotFound
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "不支持的音频格式: \(format)"
        case .copyFailed(let reason):
            return "文件复制失败: \(reason)"
        case .metadataExtractionFailed(let reason):
            return "元数据提取失败: \(reason)"
        case .fileNotFound:
            return "文件不存在"
        }
    }
}
