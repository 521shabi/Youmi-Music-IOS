import SwiftUI

// MARK: - 外观模式
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色模式"
    case dark = "深色模式"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 外观管理器
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var appearanceMode: AppearanceMode = .system {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearance_mode")
        }
    }
    
    init() {
        if let modeRaw = UserDefaults.standard.string(forKey: "appearance_mode"),
           let mode = AppearanceMode(rawValue: modeRaw) {
            self.appearanceMode = mode
        }
    }
    
    var colorScheme: ColorScheme? {
        appearanceMode.colorScheme
    }
}
