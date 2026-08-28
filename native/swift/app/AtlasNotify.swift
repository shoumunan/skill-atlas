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

    /// swift build 直跑的裸二进制没有 bundle 身份，UNUserNotificationCenter 会直接抛
    /// NSInternalInconsistencyException（bundleProxyForCurrentProcess is nil）。
    /// 探针与无头验收都走裸二进制，这里必须静默降级。
    private static var canNotify: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static func requestAuthorization() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func securityHit(count: Int) {
        guard securityEnabled, count > 0 else { return }
        post(id: "security-\(count)-\(Int(Date().timeIntervalSince1970))",
             title: L("安全复扫命中"),
             body: LF("有 %d 个技能出现关键级发现。打开 Skill Atlas 查看。", count),
             deepLink: "skillatlas://inbox")
    }

    static func missDigest(_ hits: [MissHit]) {
        guard missEnabled, !hits.isEmpty else { return }
        let names = hits.prefix(MissRules.digestCap).map(\.name).joined(separator: "、")
        post(id: "miss-weekly",
             title: L("本周有技能该触发却没触发"),
             body: names,
             deepLink: "skillatlas://inbox")
    }

    static func updatesAvailable(count: Int) {
        guard updatesEnabled, count > 0 else { return }
        let last = UserDefaults.standard.double(forKey: "atlasNotifyUpdatesAt")
        if Date().timeIntervalSince1970 - last < 20 * 3600 { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "atlasNotifyUpdatesAt")
        post(id: "updates-daily",
             title: L("有技能可以更新"),
             body: LF("%d 个技能有新版本。", count),
             deepLink: "skillatlas://inbox")
    }

    /// 通知一律带深链（DESIGN v15）：点开就落到收件箱对应条目，
    /// 而不是把人扔到主窗口自己找。没有这一步，「不打开窗口的人」这个
    /// 验收人物就拿不到任何入口。
    private static func post(id: String, title: String, body: String, deepLink: String) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["deepLink": deepLink]
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
