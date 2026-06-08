import Foundation
import Combine

/// 定时关闭模式
enum SleepTimerMode: Equatable {
    case off                    // 未启用
    case countdown(minutes: Int) // 倒计时模式
    case endOfTrack             // 播完当前歌曲
}

/// 定时关闭管理器
class SleepTimerManager: ObservableObject {
    static let shared = SleepTimerManager()
    
    /// 当前模式
    @Published private(set) var mode: SleepTimerMode = .off
    
    /// 剩余秒数（仅倒计时模式有效）
    @Published private(set) var remainingSeconds: Int = 0
    
    /// 是否已激活
    var isActive: Bool {
        mode != .off
    }
    
    /// 格式化的剩余时间
    var formattedRemainingTime: String {
        guard case .countdown = mode else { return "" }
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupTrackEndObserver()
    }
    
    // MARK: - Public Methods
    
    /// 设置倒计时（分钟）
    func setCountdown(minutes: Int) {
        stopTimer()
        mode = .countdown(minutes: minutes)
        remainingSeconds = minutes * 60
        startTimer()
    }
    
    /// 设置播完当前歌曲后关闭
    func setEndOfTrack() {
        stopTimer()
        mode = .endOfTrack
        remainingSeconds = 0
    }
    
    /// 取消定时
    func cancel() {
        stopTimer()
        mode = .off
        remainingSeconds = 0
    }
    
    // MARK: - Private Methods
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.remainingSeconds > 0 {
                self.remainingSeconds -= 1
            }
            
            if self.remainingSeconds == 0 {
                self.triggerSleep()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func setupTrackEndObserver() {
        // 监听歌曲播放结束
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if case .endOfTrack = self.mode {
                    self.triggerSleep()
                }
            }
            .store(in: &cancellables)
    }
    
    private func triggerSleep() {
        // 暂停播放
        AudioPlayer.shared.pause()
        
        // 重置状态
        mode = .off
        remainingSeconds = 0
        stopTimer()
        
        // 发送通知（可用于显示提示）
        NotificationCenter.default.post(name: .sleepTimerTriggered, object: nil)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let sleepTimerTriggered = Notification.Name("sleepTimerTriggered")
}
