//
//  LyricHomeWidget.swift
//  LyricWidget
//
//  主屏幕歌词小组件 - 支持小/中/大三种尺寸
//

import WidgetKit
import SwiftUI

// MARK: - Widget 共享数据模型
struct WidgetPlaybackData: Codable {
    var songName: String
    var artistName: String
    var albumName: String
    var coverImageData: Data?
    var currentLyric: String
    var nextLyric: String
    var isPlaying: Bool
    var progress: Float
    var currentTime: Double
    var duration: Double
    var lastUpdated: Date
}

// MARK: - Timeline Entry
struct LyricWidgetEntry: TimelineEntry {
    let date: Date
    let songName: String
    let artistName: String
    let albumName: String
    let coverImage: UIImage?
    let currentLyric: String
    let nextLyric: String
    let isPlaying: Bool
    let progress: Float

    static var placeholder: LyricWidgetEntry {
        LyricWidgetEntry(
            date: Date(),
            songName: "歌曲名称",
            artistName: "歌手",
            albumName: "专辑",
            coverImage: nil,
            currentLyric: "歌词显示在这里",
            nextLyric: "下一句歌词",
            isPlaying: false,
            progress: 0.3
        )
    }

    static var empty: LyricWidgetEntry {
        LyricWidgetEntry(
            date: Date(),
            songName: "",
            artistName: "",
            albumName: "",
            coverImage: nil,
            currentLyric: "",
            nextLyric: "",
            isPlaying: false,
            progress: 0
        )
    }
}

// MARK: - Timeline Provider
struct LyricWidgetProvider: TimelineProvider {
    // App Group ID
    private let appGroupID = "group.com.youmi.neteasemusic"
    private let dataKey = "widgetPlaybackData"

    func placeholder(in context: Context) -> LyricWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (LyricWidgetEntry) -> Void) {
        let entry = loadCurrentEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LyricWidgetEntry>) -> Void) {
        let currentEntry = loadCurrentEntry()

        // 创建未来 5 秒间隔的 Timeline entries
        var entries: [LyricWidgetEntry] = []
        let currentDate = Date()

        for secondOffset in stride(from: 0, to: 60, by: 5) {
            guard let entryDate = Calendar.current.date(byAdding: .second, value: secondOffset, to: currentDate) else {
                continue
            }
            let entry = LyricWidgetEntry(
                date: entryDate,
                songName: currentEntry.songName,
                artistName: currentEntry.artistName,
                albumName: currentEntry.albumName,
                coverImage: currentEntry.coverImage,
                currentLyric: currentEntry.currentLyric,
                nextLyric: currentEntry.nextLyric,
                isPlaying: currentEntry.isPlaying,
                progress: currentEntry.progress
            )
            entries.append(entry)
        }

        // 每 30 秒刷新一次 Timeline
        let refreshDate = Calendar.current.date(byAdding: .second, value: 30, to: currentDate) ?? currentDate.addingTimeInterval(30)
        let timeline = Timeline(entries: entries, policy: .after(refreshDate))
        completion(timeline)
    }

    // 从 App Group 读取数据
    private func loadCurrentEntry() -> LyricWidgetEntry {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: dataKey) else {
            return .empty
        }

        do {
            let playbackData = try JSONDecoder().decode(WidgetPlaybackData.self, from: data)

            var coverImage: UIImage? = nil
            if let imageData = playbackData.coverImageData {
                coverImage = UIImage(data: imageData)
            }

            return LyricWidgetEntry(
                date: Date(),
                songName: playbackData.songName,
                artistName: playbackData.artistName,
                albumName: playbackData.albumName,
                coverImage: coverImage,
                currentLyric: playbackData.currentLyric,
                nextLyric: playbackData.nextLyric,
                isPlaying: playbackData.isPlaying,
                progress: playbackData.progress
            )
        } catch {
            return .empty
        }
    }
}

// MARK: - 小号 Widget 视图
struct SmallLyricWidgetView: View {
    let entry: LyricWidgetEntry

    var body: some View {
        VStack(spacing: 8) {
            // 专辑封面
            if let image = entry.coverImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 80, height: 80)

                    Image(systemName: "music.note")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
            }

            VStack(spacing: 2) {
                // 歌曲名
                Text(entry.songName.isEmpty ? "未在播放" : entry.songName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // 歌手名
                Text(entry.artistName.isEmpty ? "MiuMuse" : entry.artistName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

// MARK: - 中号 Widget 视图
struct MediumLyricWidgetView: View {
    let entry: LyricWidgetEntry

    var body: some View {
        HStack(spacing: 12) {
            // 专辑封面
            if let image = entry.coverImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(
                            colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 100, height: 100)

                    Image(systemName: "music.note")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                // 歌曲信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.songName.isEmpty ? "未在播放" : entry.songName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(entry.artistName.isEmpty ? "MiuMuse" : entry.artistName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Divider()

                // 当前歌词
                Text(entry.currentLyric.isEmpty ? "♪ ♪ ♪" : entry.currentLyric)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // 进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)

                        Capsule()
                            .fill(LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * CGFloat(entry.progress), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

// MARK: - 大号 Widget 视图
struct LargeLyricWidgetView: View {
    let entry: LyricWidgetEntry

    var body: some View {
        VStack(spacing: 16) {
            // 大封面
            if let image = entry.coverImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(LinearGradient(
                            colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 160, height: 160)

                    Image(systemName: "music.note")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                }
            }

            // 歌曲信息
            VStack(spacing: 4) {
                Text(entry.songName.isEmpty ? "未在播放" : entry.songName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(entry.artistName.isEmpty ? "MiuMuse" : entry.artistName)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Divider()
                .padding(.horizontal, 20)

            // 歌词区域
            VStack(spacing: 8) {
                // 当前歌词
                Text(entry.currentLyric.isEmpty ? "♪ ♪ ♪" : entry.currentLyric)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                // 下一句歌词
                if !entry.nextLyric.isEmpty {
                    Text(entry.nextLyric)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            // 进度条
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)

                        Capsule()
                            .fill(LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * CGFloat(entry.progress), height: 6)
                    }
                }
                .frame(height: 6)

                // 播放状态
                HStack {
                    Image(systemName: entry.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    Text(entry.isPlaying ? "正在播放" : "已暂停")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

// MARK: - Widget 主体
struct LyricHomeWidget: Widget {
    let kind: String = "LyricHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LyricWidgetProvider()) { entry in
            LyricWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("歌词小组件")
        .description("在主屏幕显示当前播放的歌曲和歌词")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - 入口视图
struct LyricWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: LyricWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallLyricWidgetView(entry: entry)
        case .systemMedium:
            MediumLyricWidgetView(entry: entry)
        case .systemLarge:
            LargeLyricWidgetView(entry: entry)
        default:
            MediumLyricWidgetView(entry: entry)
        }
    }
}

// MARK: - 预览
#Preview("Small", as: .systemSmall) {
    LyricHomeWidget()
} timeline: {
    LyricWidgetEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    LyricHomeWidget()
} timeline: {
    LyricWidgetEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    LyricHomeWidget()
} timeline: {
    LyricWidgetEntry.placeholder
}
