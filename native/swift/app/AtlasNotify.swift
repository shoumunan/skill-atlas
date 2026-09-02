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

    /// 已经告知过的关键级技能。通知说的是「刚发生了什么」，不是「现在有几个」——
    /// 没有这层记账，每次复扫（装技能、改档位、目录被 touch 都会触发）都会把同一批
    /// 陈年发现重播一遍，而它们其实一直安静地躺在收件箱队首。
    private static let notifiedCriticalKey = "atlasNotifiedCriticalDirs"

    /// 只为**新出现**的关键级发现打扰用户。已知的那些留在收件箱里（severity 0、
    /// 不可忽略、永远排在队首），不靠反复弹窗刷存在感。
    static func securityHit(critical: [(directory: String, name: String)]) {
        let defaults = UserDefaults.standard
        let current = Set(critical.map(\.directory))

        // 首次建立基线：现存发现早就在收件箱排队了，不为它们补一次弹窗
        guard defaults.object(forKey: notifiedCriticalKey) != nil else {
            defaults.set(current.sorted(), forKey: notifiedCriticalKey)
            return
        }

        let known = Set(defaults.stringArray(forKey: notifiedCriticalKey) ?? [])
        let fresh = current.subtracting(known)
        // 被修掉或卸载的要退出记账，将来重新出现仍算新事件
        defaults.set(current.sorted(), forKey: notifiedCriticalKey)

        guard securityEnabled, !fresh.isEmpty else { return }
        let names = critical.filter { fresh.contains($0.directory) }.map(\.name).sorted()
        let title: String
        if names.count == 1 {
            title = LF("「%@」有需要你看一眼的写法", names[0])
        } else if names.count <= 3 {
            title = LF("%@ 有需要你看一眼的写法", names.joined(separator: "、"))
        } else {
            title = LF("%@ 等 %d 个技能有需要你看一眼的写法", names[0], names.count)
        }
        // id 稳定：同一批发现重复投递会合并，不会在通知中心堆成一摞
        post(id: "security-\(fresh.sorted().joined(separator: ","))",
             title: title,
             body: L("装之前扫出来的。到技能详情里看原文。"),
             deepLink: "skillatlas://skill/\(names[0])")
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
