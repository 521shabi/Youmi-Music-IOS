import Foundation
import ActivityKit
import SwiftUI

// MARK: - 歌词 Live Activity 数据模型
// 注意：此定义需要与 LyricWidget/LyricActivityAttributes.swift 保持一致
struct LyricActivityAttributes: ActivityAttributes {
    /// 静态内容 - 歌曲信息
    var songTitle: String
    var artistName: String
    var albumArtData: Data?
    
    /// 动态内容状态
    public struct ContentState: Codable, Hashable {
        var currentLyric: String
        var nextLyric: String
        var progress: Float
        var isPlaying: Bool
    }
}

// MARK: - 歌词 Live Activity 管理器
@available(iOS 16.2, *)
class LyricActivityManager: ObservableObject {
    static let shared = LyricActivityManager()
    
    private var currentActivity: Activity<LyricActivityAttributes>?
    @Published var isActivityActive: Bool = false
    
    private init() {}
    
    /// 检查是否支持 Live Activities
    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }
    
    /// 开始歌词 Live Activity
    func startActivity(
        songTitle: String,
        artistName: String,
        albumArtData: Data? = nil,
        currentLyric: String = "",
        nextLyric: String = "",
        progress: Float = 0,
        isPlaying: Bool = true
    ) {
        // 如果已有活动，先结束它
        if currentActivity != nil {
            stopActivity()
        }
        
        guard isSupported else {
            #if DEBUG
            print("⚠️ Live Activities 不可用")
            #endif
            return
        }
        
        let attributes = LyricActivityAttributes(
            songTitle: songTitle,
            artistName: artistName,
            albumArtData: albumArtData
        )
        
        let initialState = LyricActivityAttributes.ContentState(
            currentLyric: currentLyric,
            nextLyric: nextLyric,
            progress: progress,
            isPlaying: isPlaying
        )
        
        // 设置高优先级，让歌词 Activity 优先显示
        let content = ActivityContent(state: initialState, staleDate: nil, relevanceScore: 100)
        
        do {
            let activity = try Activity<LyricActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivity = activity
            isActivityActive = true
            
            #if DEBUG
            print("✅ Live Activity 已启动: \(activity.id)")
            #endif
        } catch {
            #if DEBUG
            print("❌ 启动 Live Activity 失败: \(error)")
            #endif
        }
    }
    
    /// 更新歌词
    func updateLyric(
        currentLyric: String,
        nextLyric: String = "",
        progress: Float,
        isPlaying: Bool
    ) {
        guard let activity = currentActivity else { return }
        
        let updatedState = LyricActivityAttributes.ContentState(
            currentLyric: currentLyric,
            nextLyric: nextLyric,
            progress: progress,
            isPlaying: isPlaying
        )
        
        Task {
            await activity.update(
                ActivityContent(state: updatedState, staleDate: nil, relevanceScore: 100)
            )
        }
    }
    
    /// 停止 Live Activity
    func stopActivity() {
        guard let activity = currentActivity else { return }
        
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            await MainActor.run {
                currentActivity = nil
                isActivityActive = false
            }
            #if DEBUG
            print("🛑 Live Activity 已停止")
            #endif
        }
    }
    
    /// 结束所有 Live Activities
    func endAllActivities() {
        Task {
            for activity in Activity<LyricActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            await MainActor.run {
                currentActivity = nil
                isActivityActive = false
            }
        }
    }
}

// MARK: - 压缩专辑封面工具
@available(iOS 16.2, *)
extension LyricActivityManager {
    /// 压缩图片为适合 Live Activity 的大小
    static func compressAlbumArt(_ image: UIImage, maxSize: CGSize = CGSize(width: 100, height: 100)) -> Data? {
        let size = CGSize(
            width: min(image.size.width, maxSize.width),
            height: min(image.size.height, maxSize.height)
        )
        
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage?.jpegData(compressionQuality: 0.6)
    }
}
