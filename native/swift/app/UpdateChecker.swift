import AppKit
import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 应用自更新检查
//
// 拉取 appcast.json，与 CFBundleShortVersionString 做语义化比较。
// 超时 5 秒；后台失败静默。菜单「检查更新…」走三条可见路径：
// 有新版 / 已最新 / 暂时无法检查更新。
// 启动 10 秒后若距上次成功检查 ≥7 天则静默查一次；有新版时工具栏亮点。
// 有新版时首选「自动更新」（SelfUpdater 应用内下载换装重启），
// 「打开下载页」降级为手动逃生门。可见路径走 AppUpdateSheet，不再弹系统 NSAlert。

struct Appcast: Equatable {
    var version: String
    var notes: String
    var download: String
    /// DMG 直链（可选；缺省时 SelfUpdater 查 GitHub Releases API 兜底）
    var dmg: String = ""
    /// DMG 的 sha256（可选；给了就在安装前校验）
    var sha256: String = ""
}

enum UpdateOutcome: Equatable {
    case available(Appcast)
    case upToDate(current: String)
    case failed(String)
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let defaultFeed = "https://raw.githubusercontent.com/shoumunan/skill-atlas/main/appcast.json"
    private static let lastCheckKey = "atlasLastSilentUpdateCheck"

    @Published var available: Appcast?
    /// 应用自更新 sheet。id 在同一次会话里保持不变，stage 切换不会把窗拆掉重开。
    @Published var session: AppUpdateSession?

    static var feedURL: URL {
        if let override = UserDefaults.standard.string(forKey: "atlasAppcastURL"),
           let url = URL(string: override), !override.isEmpty {
            return url
        }
        return URL(string: defaultFeed)!
    }

    /// 默认源已指向 github.com/shoumunan/skill-atlas，是真实仓库
    static var feedConfigured: Bool { true }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// 启动时调用：probe 钩子立即跑；否则 10 秒后按 7 天节奏静默检查
    func bootstrap() {
        if UserDefaults.standard.string(forKey: "atlasUpdateProbe") != nil {
            Task { await probeAndMaybeQuit() }
            return
        }
        // 调试钩子：-atlasAutoUpdate 1 启动即拉 appcast，有新版直接走应用内换装（验收用）
        if LaunchArgs.flag("atlasAutoUpdate") {
            Task {
                let outcome = await Self.fetch()
                apply(outcome)
                if case .available(let feed) = outcome {
                    presentAvailable(feed)
                    SelfUpdater.shared.install(feed)
                }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            Task { await self?.silentCheckIfDue() }
        }
    }

    func checkFromMenu() {
        // 没配置更新源就别去打网络——诚实告知，而不是弹「网络错误」
        guard Self.feedConfigured else {
            presentUnconfigured()
            return
        }
        Task {
            let outcome = await Self.fetch()
            apply(outcome)
            present(outcome)
        }
    }

    func presentAvailable(_ feed: Appcast) {
        beginSession(stage: .available, feed: feed)
    }

    func enterInstalling(_ feed: Appcast) {
        if var current = session, current.feed?.version == feed.version {
            current.stage = .installing
            session = current
        } else {
            beginSession(stage: .installing, feed: feed)
        }
    }

    func enterInstallFailed(_ feed: Appcast, message: String) {
        if var current = session {
            current.stage = .installFailed
            current.feed = feed
            current.message = message
            session = current
        } else {
            beginSession(stage: .installFailed, feed: feed, message: message)
        }
    }

    func dismissSession() {
        session = nil
    }

    static func openDownload(_ feed: Appcast) {
        if let url = URL(string: feed.download) { NSWorkspace.shared.open(url) }
    }

    static func revealMainWindow() {
        if let window = NSApp.windows.first(where: { $0.contentView != nil }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 网络

    static func fetch() async -> UpdateOutcome {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        do {
            let (data, response) = try await session.data(from: feedURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failed("HTTP \(http.statusCode)")
            }
            guard let feed = parse(data) else { return .failed("appcast 无法解析") }
            let current = currentVersion
            if compareVersions(current, feed.version) == .orderedAscending {
                return .available(feed)
            }
            return .upToDate(current: current)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func parse(_ data: Data) -> Appcast? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? String, !version.isEmpty,
              let download = object["download"] as? String, !download.isEmpty else {
            return nil
        }
        return Appcast(
            version: version,
            notes: (object["notes"] as? String) ?? "",
            download: download,
            dmg: (object["dmg"] as? String) ?? "",
            sha256: (object["sha256"] as? String) ?? ""
        )
    }

    /// 语义化比较：1.2.0 < 1.10.0 < 2.0.0；缺段按 0。
    /// 纯字符串运算不碰任何 actor 状态，标 nonisolated 供后台的自更新校验调用。
    nonisolated static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        func parts(_ raw: String) -> [Int] {
            raw.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        let a = parts(lhs)
        let b = parts(rhs)
        let count = max(a.count, b.count)
        for index in 0..<count {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    // MARK: 静默 / probe

    private func silentCheckIfDue() async {
        guard Self.feedConfigured else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        let due = last == 0 || Date().timeIntervalSince1970 - last >= 7 * 86400
        guard due else { return }
        let outcome = await Self.fetch()
        apply(outcome)
        if case .failed = outcome {
            return
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
    }

    private func apply(_ outcome: UpdateOutcome) {
        if case .available(let feed) = outcome {
            available = feed
        } else if case .upToDate = outcome {
            available = nil
        }
    }

    private func probeAndMaybeQuit() async {
        let outcome = await Self.fetch()
        apply(outcome)
        if let path = UserDefaults.standard.string(forKey: "atlasUpdateProbe"), !path.isEmpty {
            let payload = Self.probeJSON(outcome)
            try? payload.write(toFile: path, atomically: true, encoding: .utf8)
        }
        if UserDefaults.standard.bool(forKey: "atlasQuit") {
            NSApp.terminate(nil)
            exit(0)
        }
    }

    static func probeJSON(_ outcome: UpdateOutcome) -> String {
        var object: [String: Any] = ["current": currentVersion]
        switch outcome {
        case .available(let feed):
            object["status"] = "available"
            object["version"] = feed.version
            object["notes"] = feed.notes
            object["download"] = feed.download
        case .upToDate(let current):
            object["status"] = "upToDate"
            object["version"] = current
        case .failed(let reason):
            object["status"] = "failed"
            object["error"] = reason
            object["feed"] = feedURL.absoluteString
        }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func present(_ outcome: UpdateOutcome) {
        switch outcome {
        case .available(let feed):
            beginSession(stage: .available, feed: feed)
        case .upToDate(let current):
            beginSession(stage: .upToDate, current: current)
        case .failed(let reason):
            beginSession(stage: .failed, message: reason)
        }
    }

    private func presentUnconfigured() {
        beginSession(stage: .unconfigured)
    }

    private func beginSession(stage: AppUpdateSession.Stage, feed: Appcast? = nil, current: String? = nil, message: String = "") {
        Self.revealMainWindow()
        session = AppUpdateSession(
            id: session?.id ?? UUID(),
            stage: stage,
            feed: feed,
            current: current ?? Self.currentVersion,
            message: message
        )
    }
}
