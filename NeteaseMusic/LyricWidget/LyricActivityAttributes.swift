import Foundation
import ActivityKit

// MARK: - 歌词 Live Activity 数据模型
// 注意：此文件需要同时被主 App 和 Widget Extension 引用
// 主 App 和 Widget Extension 必须使用相同的数据结构

struct LyricActivityAttributes: ActivityAttributes {
    /// 静态内容 - 歌曲信息（创建 Activity 时设置，不变）
    var songTitle: String
    var artistName: String
    var albumArtData: Data?  // 专辑封面（压缩后的图片数据）
    var dynamicCoverURL: String?  // iOS 26+ 动态封面视频 URL

    /// 动态内容状态 - 歌词变化时更新
    public struct ContentState: Codable, Hashable {
        var currentLyric: String
        var nextLyric: String
        var progress: Float  // 0.0 - 1.0
        var isPlaying: Bool
    }
}
