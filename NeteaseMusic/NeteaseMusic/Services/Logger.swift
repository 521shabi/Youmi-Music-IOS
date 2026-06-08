import Foundation
import os.log

/// 统一日志工具，替代散落各处的 #if DEBUG print(...)
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.neteasemusic"

    static let audio = os.Logger(subsystem: subsystem, category: "Audio")
    static let network = os.Logger(subsystem: subsystem, category: "Network")
    static let cache = os.Logger(subsystem: subsystem, category: "Cache")
    static let ui = os.Logger(subsystem: subsystem, category: "UI")
    static let general = os.Logger(subsystem: subsystem, category: "General")
}
