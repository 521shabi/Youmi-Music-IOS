import Foundation
import UserNotifications

class NotificationService {
    static let shared = NotificationService()
    
    private let lastOpenKey = "lastAppOpenDate"
    private let notificationIdentifier = "comeBackNotification"
    
    // 推送消息列表（随机选一条）
    private let messages = [
        "死了吗？没死快来 Youmi Music 听歌！🎵",
        "喂！还活着吗？快来听歌！🎧",
        "人呢？Youmi Music 想你了！💔",
        "这么久不来听歌，是不是忘了我？😢",
        "醒醒！该听歌了！🔔",
        "你的歌单都长草了，快来打理一下！🌱"
    ]
    
    private init() {}
    
    // MARK: - 请求通知权限
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ 通知权限已授权")
            } else {
                print("❌ 通知权限被拒绝")
            }
        }
    }
    
    // MARK: - 记录 App 打开时间
    func recordAppOpen() {
        UserDefaults.standard.set(Date(), forKey: lastOpenKey)
        // 取消之前的通知，重新安排
        cancelScheduledNotification()
        scheduleNotification()
    }
    
    // MARK: - 安排通知（3小时后）
    func scheduleNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Youmi Music"
        content.body = messages.randomElement() ?? messages[0]
        content.sound = .default
        
        // 3小时后触发
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3 * 60 * 60, repeats: false)
        
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 安排通知失败: \(error)")
            } else {
                print("✅ 已安排 3 天后的通知")
            }
        }
    }
    
    // MARK: - 取消已安排的通知
    func cancelScheduledNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }
}
