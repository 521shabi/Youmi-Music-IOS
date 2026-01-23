import Foundation
import UIKit

// MARK: - 本地歌曲模型
struct LocalTrack: Codable, Identifiable {
    let id: UUID
    let fileName: String           // 原始文件名
    let fileURL: URL               // 文件路径
    let title: String              // 歌曲标题
    let artist: String             // 艺术家
    let album: String              // 专辑名
    let duration: Double           // 时长(秒)
    let fileSize: Int64            // 文件大小(字节)
    let format: String             // 文件格式
    let bitrate: Int?              // 比特率
    let sampleRate: Double?        // 采样率
    let addedDate: Date            // 添加日期
    
    // 封面图片数据（Base64编码存储）
    let artworkData: Data?
    
    // 内嵌歌词
    let embeddedLyrics: String?
    
    // 计算属性
    var artistName: String {
        artist.isEmpty ? "未知艺术家" : artist
    }
    
    var albumName: String {
        album.isEmpty ? "未知专辑" : album
    }
    
    var displayTitle: String {
        title.isEmpty ? fileName : title
    }
    
    var durationText: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var fileSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var formatBadge: String {
        format.uppercased()
    }
    
    // 获取封面图片
    var artworkImage: UIImage? {
        guard let data = artworkData else { return nil }
        return UIImage(data: data)
    }
    
    // 判断是否有歌词
    var hasLyrics: Bool {
        guard let lyrics = embeddedLyrics else { return false }
        return !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // 初始化方法
    init(
        id: UUID = UUID(),
        fileName: String,
        fileURL: URL,
        title: String = "",
        artist: String = "",
        album: String = "",
        duration: Double = 0,
        fileSize: Int64 = 0,
        format: String = "",
        bitrate: Int? = nil,
        sampleRate: Double? = nil,
        artworkData: Data? = nil,
        embeddedLyrics: String? = nil,
        addedDate: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileSize = fileSize
        self.format = format
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.artworkData = artworkData
        self.embeddedLyrics = embeddedLyrics
        self.addedDate = addedDate
    }
    
    // 转换为 Track 用于播放器
    func toTrack() -> Track {
        Track(
            id: id.hashValue,
            name: displayTitle,
            ar: [Artist(id: 0, name: artistName)],
            al: Album(id: 0, name: albumName, picUrl: nil),
            artists: nil,
            album: nil,
            dt: Int(duration * 1000),
            duration: nil,
            mv: nil,
            mvid: nil
        )
    }
}

// MARK: - 支持的音频格式
enum AudioFormat: String, CaseIterable {
    case mp3 = "mp3"
    case m4a = "m4a"
    case flac = "flac"
    case wav = "wav"
    case aiff = "aiff"
    case aac = "aac"
    case alac = "alac"
    case ogg = "ogg"
    
    var displayName: String {
        switch self {
        case .mp3: return "MP3"
        case .m4a: return "M4A/AAC"
        case .flac: return "FLAC"
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        case .aac: return "AAC"
        case .alac: return "Apple Lossless"
        case .ogg: return "OGG"
        }
    }
    
    var utType: String {
        switch self {
        case .mp3: return "public.mp3"
        case .m4a: return "public.mpeg-4-audio"
        case .flac: return "org.xiph.flac"
        case .wav: return "com.microsoft.waveform-audio"
        case .aiff: return "public.aiff-audio"
        case .aac: return "public.aac-audio"
        case .alac: return "com.apple.m4a-audio"
        case .ogg: return "org.xiph.ogg"
        }
    }
    
    // 支持的文件扩展名
    static var supportedExtensions: [String] {
        ["mp3", "m4a", "flac", "wav", "aiff", "aif", "aac", "alac", "ogg", "m4b", "m4p", "m4r"]
    }
    
    static func from(extension ext: String) -> AudioFormat? {
        switch ext.lowercased() {
        case "mp3": return .mp3
        case "m4a", "m4b", "m4p", "m4r": return .m4a
        case "flac": return .flac
        case "wav": return .wav
        case "aiff", "aif": return .aiff
        case "aac": return .aac
        case "alac": return .alac
        case "ogg": return .ogg
        default: return nil
        }
    }
}

// MARK: - 本地歌词解析结果
struct LocalLyricParseResult {
    let originalLyrics: String?        // 原始歌词文本
    let parsedLines: [LyricLine]       // 解析后的歌词行
    let hasTimestamp: Bool             // 是否有时间戳
    
    init(lyrics: String?) {
        self.originalLyrics = lyrics
        
        if let lyrics = lyrics, !lyrics.isEmpty {
            self.parsedLines = LyricLine.parse(lyrics)
            self.hasTimestamp = !parsedLines.isEmpty
        } else {
            self.parsedLines = []
            self.hasTimestamp = false
        }
    }
}
