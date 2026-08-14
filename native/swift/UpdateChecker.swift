import AppKit
import Foundation

// MARK: - 应用自更新检查
//
// 拉取 GitHub Releases 最新版本（同时兼容自定义 appcast.json），
// 与 CFBundleShortVersionString 做语义化比较。
// 超时 5 秒；后台失败静默。菜单「检查更新…」走三条可见路径：
// 有新版 / 已最新 / 暂时无法检查更新。
// 启动 10 秒后若距上次成功检查 ≥7 天则静默查一次；有新版时工具栏亮点。

struct Appcast: Equatable {
    var version: String
    var notes: String
    var download: String
}

enum UpdateOutcome: Equatable {
    case available(Appcast)
    case upToDate(current: String)
    case failed(String)
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let defaultFeed = "https://api.github.com/repos/shoumunan/skill-atlas/releases/latest"
    private static let lastCheckKey = "atlasLastSilentUpdateCheck"

    @Published var available: Appcast?

    static var feedURL: URL {
        if let override = UserDefaults.standard.string(forKey: "atlasAppcastURL"),
           let url = URL(string: override), !override.isEmpty {
            return url
        }
        return URL(string: defaultFeed)!
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// 启动时调用：probe 钩子立即跑；否则 10 秒后按 7 天节奏静默检查
    func bootstrap() {
        if UserDefaults.standard.string(forKey: "atlasUpdateProbe") != nil {
            Task { await probeAndMaybeQuit() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            Task { await self?.silentCheckIfDue() }
        }
    }

    func checkFromMenu() {
        Task {
            let outcome = await Self.fetch()
            apply(outcome)
            Self.presentAlert(outcome)
        }
    }

    // MARK: 网络

    static func fetch() async -> UpdateOutcome {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        do {
            var request = URLRequest(url: feedURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Skill-Atlas/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
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
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let tag = object["tag_name"] as? String {
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let notes = (object["body"] as? String) ?? ""
            let assets = object["assets"] as? [[String: Any]] ?? []
            guard !version.isEmpty,
                  let download = assets.first(where: {
                      (($0["name"] as? String) ?? "").lowercased().hasSuffix(".dmg")
                  })?["browser_download_url"] as? String,
                  isSecureDownload(download) else {
                return nil
            }
            return Appcast(version: version, notes: notes, download: download)
        }

        guard let version = object["version"] as? String, !version.isEmpty,
              let download = object["download"] as? String, !download.isEmpty,
              isSecureDownload(download) else {
            return nil
        }
        return Appcast(version: version, notes: (object["notes"] as? String) ?? "", download: download)
    }

    private static func isSecureDownload(_ raw: String) -> Bool {
        URL(string: raw)?.scheme?.lowercased() == "https"
    }

    /// 语义化比较：1.2.0 < 1.10.0 < 2.0.0；缺段按 0
    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
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

    static func presentAlert(_ outcome: UpdateOutcome) {
        let alert = NSAlert()
        switch outcome {
        case .available(let feed):
            alert.messageText = LF("发现新版本 %@", feed.version)
            alert.informativeText = feed.notes.isEmpty
                ? LF("当前版本 %@。", currentVersion)
                : feed.notes
            alert.addButton(withTitle: L("打开下载页"))
            alert.addButton(withTitle: L("稍后"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: feed.download) {
                NSWorkspace.shared.open(url)
            }
        case .upToDate:
            alert.messageText = L("已是最新版本")
            alert.informativeText = LF("当前版本 %@。", currentVersion)
            alert.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        case .failed(_):
            alert.messageText = L("暂时无法检查更新")
            alert.informativeText = L("请检查网络后重试。")
            alert.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
