import Foundation
import UserNotifications
#if SWIFT_PACKAGE
import AtlasCore
#endif

/// 系统通知。默认只开安全类；miss 周报与可更新聚合要在设置里打开。
enum AtlasNotify {
    static let securityKey = "atlasNotifySecurity"
    static let missKey = "atlasNotifyMiss"
    static let updatesKey = "atlasNotifyUpdates"

    static var securityEnabled: Bool {
        UserDefaults.standard.object(forKey: securityKey) as? Bool ?? true
    }
    static var missEnabled: Bool {
        UserDefaults.standard.bool(forKey: missKey)
    }
    static var updatesEnabled: Bool {
        UserDefaults.standard.bool(forKey: updatesKey)
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func securityHit(count: Int) {
        guard securityEnabled, count > 0 else { return }
        post(id: "security-\(count)-\(Int(Date().timeIntervalSince1970))",
             title: L("安全复扫命中"),
             body: LF("有 %d 个技能出现关键级发现。打开 Skill Atlas 查看。", count))
    }

    static func missDigest(_ hits: [MissHit]) {
        guard missEnabled, !hits.isEmpty else { return }
        let names = hits.prefix(MissRules.digestCap).map(\.name).joined(separator: "、")
        post(id: "miss-weekly",
             title: L("本周有技能该触发却没触发"),
             body: names)
    }

    static func updatesAvailable(count: Int) {
        guard updatesEnabled, count > 0 else { return }
        let last = UserDefaults.standard.double(forKey: "atlasNotifyUpdatesAt")
        if Date().timeIntervalSince1970 - last < 20 * 3600 { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "atlasNotifyUpdatesAt")
        post(id: "updates-daily",
             title: L("有技能可以更新"),
             body: LF("%d 个技能有新版本。", count))
    }

    private static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
