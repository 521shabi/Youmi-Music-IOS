//
//  WidgetDataService.swift
//  NeteaseMusic
//
//  共享数据服务 - 用于主 App 和 Widget 之间共享播放状态
//  通过 App Group UserDefaults 实现数据共享
//

import Foundation
import UIKit
import WidgetKit

// MARK: - Widget 共享数据模型
struct WidgetPlaybackData: Codable {
    var songName: String
    var artistName: String
    var albumName: String
    var coverImageData: Data?
    var currentLyric: String
    var nextLyric: String
    var isPlaying: Bool
    var progress: Float  // 0.0 - 1.0
    var currentTime: Double
    var duration: Double
    var lastUpdated: Date

    static var empty: WidgetPlaybackData {
        WidgetPlaybackData(
            songName: "",
            artistName: "",
            albumName: "",
            coverImageData: nil,
            currentLyric: "",
            nextLyric: "",
            isPlaying: false,
            progress: 0,
            currentTime: 0,
            duration: 0,
            lastUpdated: Date()
        )
    }
}

// MARK: - Widget 数据服务
class WidgetDataService {
    static let shared = WidgetDataService()

    // App Group ID - 需要在 Xcode 中配置
    private let appGroupID = "group.com.youmi.neteasemusic"
    private let dataKey = "widgetPlaybackData"

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private init() {}

    // MARK: - 写入数据（主 App 调用）

    /// 更新播放状态到 Widget
    func updatePlaybackState(
        songName: String,
        artistName: String,
        albumName: String,
        coverImage: UIImage?,
        currentLyric: String,
        nextLyric: String,
        isPlaying: Bool,
        progress: Float,
        currentTime: Double,
        duration: Double
    ) {
        // 压缩封面图片
        var coverData: Data? = nil
        if let image = coverImage {
            // 缩小到 200x200 并压缩
            let targetSize = CGSize(width: 200, height: 200)
            let resizedImage = resizeImage(image, to: targetSize)
            coverData = resizedImage.jpegData(compressionQuality: 0.7)
        }

        let data = WidgetPlaybackData(
            songName: songName,
            artistName: artistName,
            albumName: albumName,
            coverImageData: coverData,
            currentLyric: currentLyric,
            nextLyric: nextLyric,
            isPlaying: isPlaying,
            progress: progress,
            currentTime: currentTime,
            duration: duration,
            lastUpdated: Date()
        )

        saveData(data)
        
        // 刷新所有 Widget
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 仅更新歌词（高频调用，避免重复写入封面）
    func updateLyrics(currentLyric: String, nextLyric: String, progress: Float, currentTime: Double) {
        guard var data = loadData() else { return }
        data.currentLyric = currentLyric
        data.nextLyric = nextLyric
        data.progress = progress
        data.currentTime = currentTime
        data.lastUpdated = Date()
        saveData(data)
        
        // 刷新所有 Widget
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 更新播放状态
    func updatePlayingState(isPlaying: Bool) {
        guard var data = loadData() else { return }
        data.isPlaying = isPlaying
        data.lastUpdated = Date()
        saveData(data)
        
        // 刷新所有 Widget
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 清除播放数据
    func clearPlaybackData() {
        saveData(WidgetPlaybackData.empty)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - 读取数据（Widget 调用）

    /// 获取当前播放数据
    func getPlaybackData() -> WidgetPlaybackData? {
        return loadData()
    }

    /// 获取封面图片
    func getCoverImage() -> UIImage? {
        guard let data = loadData(),
              let imageData = data.coverImageData else {
            return nil
        }
        return UIImage(data: imageData)
    }

    // MARK: - 私有方法

    private func saveData(_ data: WidgetPlaybackData) {
        guard let defaults = sharedDefaults else {
            #if DEBUG
            print("⚠️ WidgetDataService: 无法访问 App Group UserDefaults")
            #endif
            return
        }

        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: dataKey)
            defaults.synchronize()
        } catch {
            #if DEBUG
            print("❌ WidgetDataService: 保存数据失败 - \(error)")
            #endif
        }
    }

    private func loadData() -> WidgetPlaybackData? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: dataKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(WidgetPlaybackData.self, from: data)
        } catch {
            #if DEBUG
            print("❌ WidgetDataService: 读取数据失败 - \(error)")
            #endif
            return nil
        }
    }

    /// 缩放图片
    private func resizeImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let ratio = min(widthRatio, heightRatio)

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let rect = CGRect(origin: .zero, size: newSize)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage ?? image
    }
}
