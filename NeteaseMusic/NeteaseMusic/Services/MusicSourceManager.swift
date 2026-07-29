import Foundation
import SwiftUI

/// 音乐源类型
enum MusicSourceType: String, CaseIterable, Identifiable, Codable {
    case netease = "netease"      // 网易云音乐
    case qq = "qq"                // QQ音乐
    case appleMusic = "apple"     // Apple Music
    case kuwo = "kuwo"            // 酷我音乐
    case kugou = "kugou"         // 酷狗音乐
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .netease: return "网易云音乐"
        case .qq: return "QQ音乐"
        case .appleMusic: return "Apple Music"
        case .kuwo: return "酷我音乐"
        case .kugou: return "酷狗音乐"
        }
    }
    
    var iconName: String {
        switch self {
        case .netease: return "music.note"
        case .qq: return "music.quarternote.3"
        case .appleMusic: return "music"
        case .kuwo: return "waveform"
        case .kugou: return "speaker.wave.2"
        }
    }
    
    var color: String {
        switch self {
        case .netease: return "#D1001F"
        case .qq: return "#31C27C"
        case .appleMusic: return "#FF2D55"
        case .kuwo: return "#2D7DFF"
        case .kugou: return "#FF6B00"
        }
    }
}

/// 音乐源配置
struct MusicSourceConfig: Codable, Identifiable {
    let id: String
    let type: MusicSourceType
    var name: String
    var isActive: Bool
    var priority: Int
}

/// 公共API服务器列表
struct PublicAPIServer: Identifiable, Codable {
    let id = UUID()
    let name: String
    let url: String
    let description: String
    let isDefault: Bool
}

/// 音乐源管理器
@MainActor
class MusicSourceManager: ObservableObject {
    static let shared = MusicSourceManager()
    
    private let userDefaults = UserDefaults.standard
    
    // MARK: - 公共API服务器列表
    
    let publicAPIServers: [PublicAPIServer] = [
        PublicAPIServer(name: "官方默认", url: "https://netease-cloud-music-api-sigma-sage.vercel.app", description: "社区维护，稳定可靠", isDefault: true),
        PublicAPIServer(name: "备用1", url: "https://api.03c3.cn", description: "备用服务器", isDefault: false),
        PublicAPIServer(name: "备用2", url: "https://api.injahow.cn", description: "备用服务器", isDefault: false),
        PublicAPIServer(name: "备用3", url: "https://music-api.ixiaoping.com", description: "备用服务器", isDefault: false),
    ]
    
    // MARK: - 已启用的音乐源
    
    @Published var enabledSources: [MusicSourceConfig] {
        didSet { saveSources() }
    }
    
    // MARK: - 当前选中的音乐源
    
    @Published var currentSource: MusicSourceType {
        didSet {
            userDefaults.set(currentSource.rawValue, forKey: "current_music_source")
            updateAPIConfigForSource(currentSource)
        }
    }
    
    // MARK: - 当前使用的API服务器
    
    @Published var currentAPIServer: PublicAPIServer {
        didSet {
            userDefaults.set(currentAPIServer.url, forKey: "current_api_server")
            APIConfig.setBaseURL(currentAPIServer.url)
        }
    }
    
    // MARK: - 是否使用公共API
    
    @Published var usePublicAPI: Bool {
        didSet {
            userDefaults.set(usePublicAPI, forKey: "use_public_api")
            if usePublicAPI { APIConfig.setBaseURL(currentAPIServer.url) }
        }
    }
    
    // MARK: - 自定义API地址
    
    @Published var customAPIURL: String {
        didSet { userDefaults.set(customAPIURL, forKey: "custom_api_url") }
    }
    
    // MARK: - 初始化
    
    private init() {
        if let data = userDefaults.data(forKey: "enabled_sources"),
           let decoded = try? JSONDecoder().decode([MusicSourceConfig].self, from: data) {
            self.enabledSources = decoded
        } else {
            self.enabledSources = [
                MusicSourceConfig(id: "netease", type: .netease, name: "网易云音乐", isActive: true, priority: 1),
                MusicSourceConfig(id: "qq", type: .qq, name: "QQ音乐", isActive: false, priority: 2),
                MusicSourceConfig(id: "apple", type: .appleMusic, name: "Apple Music", isActive: true, priority: 3),
                MusicSourceConfig(id: "kuwo", type: .kuwo, name: "酷我音乐", isActive: false, priority: 4),
                MusicSourceConfig(id: "kugou", type: .kugou, name: "酷狗音乐", isActive: false, priority: 5),
            ]
        }
        
        let savedSource = userDefaults.string(forKey: "current_music_source") ?? "netease"
        self.currentSource = MusicSourceType(rawValue: savedSource) ?? .netease
        
        let savedURL = userDefaults.string(forKey: "current_api_server") ?? publicAPIServers.first!.url
        self.currentAPIServer = publicAPIServers.first(where: { $0.url == savedURL }) ?? publicAPIServers.first!
        
        self.usePublicAPI = userDefaults.object(forKey: "use_public_api") as? Bool ?? true
        self.customAPIURL = userDefaults.string(forKey: "custom_api_url") ?? "http://localhost:3000"
        
        if usePublicAPI { APIConfig.setBaseURL(currentAPIServer.url) }
    }
    
    // MARK: - 音乐源管理
    
    func setSourceEnabled(_ type: MusicSourceType, enabled: Bool) {
        if let index = enabledSources.firstIndex(where: { $0.type == type }) {
            enabledSources[index].isActive = enabled
        }
    }
    
    func getActiveSources() -> [MusicSourceConfig] {
        return enabledSources.filter { $0.isActive }.sorted(by: { $0.priority < $1.priority })
    }
    
    func switchToNextSource() {
        let activeSources = getActiveSources()
        guard let currentIndex = activeSources.firstIndex(where: { $0.type == currentSource }) else { return }
        let nextIndex = (currentIndex + 1) % activeSources.count
        currentSource = activeSources[nextIndex].type
    }
    
    // MARK: - API服务器管理
    
    func switchToAPIServer(_ server: PublicAPIServer) { currentAPIServer = server }
    
    func useCustomAPI(_ url: String) {
        customAPIURL = url
        usePublicAPI = false
        APIConfig.setBaseURL(url)
    }
    
    func restorePublicAPI() {
        usePublicAPI = true
        APIConfig.setBaseURL(currentAPIServer.url)
    }
    
    // MARK: - 测试API连接
    
    func testAPIConnection(url: String) async -> Bool {
        guard let testURL = URL(string: "\(url)/search/hot/detail") else { return false }
        do {
            let (data, response) = try await URLSession.shared.data(from: testURL)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200 && data.count > 0
            }
            return false
        } catch { return false }
    }
    
    // MARK: - 私有方法
    
    private func saveSources() {
        if let data = try? JSONEncoder().encode(enabledSources) {
            userDefaults.set(data, forKey: "enabled_sources")
        }
    }
    
    private func updateAPIConfigForSource(_ source: MusicSourceType) {
        switch source {
        case .netease:
            if usePublicAPI { APIConfig.setBaseURL(currentAPIServer.url) }
            else { APIConfig.setBaseURL(customAPIURL) }
        case .qq: APIConfig.setBaseURL("https://c.y.qq.com")
        case .appleMusic: APIConfig.setBaseURL("https://itunes.apple.com")
        case .kuwo: APIConfig.setBaseURL("https://www.kuwo.cn")
        case .kugou: APIConfig.setBaseURL("https://www.kugou.com")
        }
    }
}