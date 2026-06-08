import ActivityKit
import WidgetKit
import SwiftUI
import AVKit

/// 歌词 Live Activity Widget - 灵动岛歌词显示
struct LyricLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricActivityAttributes.self) { context in
            // 锁屏和通知中心视图
            LockScreenLyricView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开后的区域
                DynamicIslandExpandedRegion(.leading) {
                    // 专辑封面
                    if let data = context.attributes.albumArtData,
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .frame(width: 52, height: 52)
                            .background(Color.gray.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    // 播放状态指示
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                        
                        // 进度条
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(height: 3)
                                
                                Capsule()
                                    .fill(Color.white)
                                    .frame(width: geo.size.width * CGFloat(context.state.progress), height: 3)
                            }
                        }
                        .frame(width: 40, height: 3)
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    // 歌曲信息和歌词
                    VStack(spacing: 6) {
                        // 歌曲标题
                        Text(context.attributes.songTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        // 当前歌词
                        Text(context.state.currentLyric.isEmpty ? "♪ ♪ ♪" : context.state.currentLyric)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut(duration: 0.3), value: context.state.currentLyric)
                        
                        // 下一句歌词
                        if !context.state.nextLyric.isEmpty {
                            Text(context.state.nextLyric)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    // 艺术家名称
                    Text(context.attributes.artistName)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            } compactLeading: {
                // 紧凑模式左侧 - 显示歌词前半部分
                Text(context.state.currentLyric.isEmpty ? "♪" : context.state.currentLyric)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } compactTrailing: {
                // 紧凑模式右侧 - 显示播放状态
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: context.state.isPlaying)
            } minimal: {
                // 最小模式 - 只显示音乐图标和播放状态
                Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                    .font(.system(size: 12))
            }
        }
    }
}

// MARK: - 锁屏 Live Activity 视图
struct LockScreenLyricView: View {
    let context: ActivityViewContext<LyricActivityAttributes>
    
    var body: some View {
        HStack(spacing: 12) {
            // 专辑封面
            if let data = context.attributes.albumArtData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 28))
                    .frame(width: 60, height: 60)
                    .background(Color.gray.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // 歌曲标题和艺术家
                Text(context.attributes.songTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(context.attributes.artistName)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                
                // 当前歌词
                Text(context.state.currentLyric.isEmpty ? "♪ ♪ ♪" : context.state.currentLyric)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .animation(.easeInOut(duration: 0.3), value: context.state.currentLyric)
                
                // 进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 4)
                        
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * CGFloat(context.state.progress), height: 4)
                    }
                }
                .frame(height: 4)
            }
            
            Spacer()
            
            // 播放状态
            Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 24))
                .foregroundColor(.white)
        }
        .padding(16)
        .background(Color.black.opacity(0.8))
    }
}

// MARK: - 预览
#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: LyricActivityAttributes(songTitle: "测试歌曲", artistName: "测试歌手")) {
    LyricLiveActivityWidget()
} contentStates: {
    LyricActivityAttributes.ContentState(currentLyric: "这是当前歌词", nextLyric: "这是下一句歌词", progress: 0.5, isPlaying: true)
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: LyricActivityAttributes(songTitle: "测试歌曲", artistName: "测试歌手")) {
    LyricLiveActivityWidget()
} contentStates: {
    LyricActivityAttributes.ContentState(currentLyric: "这是当前歌词", nextLyric: "这是下一句歌词", progress: 0.5, isPlaying: true)
}

#Preview("Lock Screen", as: .content, using: LyricActivityAttributes(songTitle: "测试歌曲", artistName: "测试歌手")) {
    LyricLiveActivityWidget()
} contentStates: {
    LyricActivityAttributes.ContentState(currentLyric: "这是当前歌词", nextLyric: "这是下一句歌词", progress: 0.5, isPlaying: true)
}
