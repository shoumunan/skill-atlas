import AppKit
import Combine
import CryptoKit
import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 应用内自更新（下载 DMG → 校验 → 换装 → 重启）
//
// 无 Sparkle 依赖的最小闭环：
// 1. 定位直链：appcast 的 dmg 字段优先；缺省时查 GitHub Releases API
//    （tag v<版本>，兜底 latest）里第一个 .dmg 资产——老 appcast 只有落地页也能自动更。
// 2. URLSession 下载到临时目录；appcast 带 sha256 时先校验再动手。
// 3. hdiutil 只读挂载，找出 .app，核对包内版本不低于公告版本。
// 4. ditto 拷到暂存目录并去掉 quarantine——应用是 ad-hoc 签名，带隔离位的新包
//    会被 Gatekeeper 拦启动，更新完打不开比不更新更糟。
// 5. 写一个等待本进程退出的 shell 助手：备份旧包 → ditto 新包 → 失败回滚 → open 重启。
//    日志落 ~/.skill-atlas/update.log，出问题有账可查。
// 6. 应用自身 terminate，换装交给助手。任何一步失败都回到 AppUpdateSheet 并给「打开下载页」逃生门。
// 运行中的包在 App Translocation 路径时不做（那是系统只读挂载点，换了也白换）。

@MainActor
final class SelfUpdater: NSObject, ObservableObject {
    static let shared = SelfUpdater()
    /// GitHub 仓库（appcast 没给 dmg 直链时按它查 Releases API）
    static let repo = "shoumunan/skill-atlas"

    private(set) var busy = false
    @Published var statusText = ""
    @Published var progress = 0.0

    func install(_ feed: Appcast) {
        guard !busy else { return }
        let target = Bundle.main.bundleURL
        guard !target.path.contains("/AppTranslocation/") else {
            Self.fail(feed, L("应用正处于系统隔离运行状态。先把 Skill Atlas 移进「应用程序」文件夹再试，或手动下载覆盖。"))
            return
        }
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            Self.fail(feed, LF("没有权限替换 %@ 里的应用。", target.deletingLastPathComponent().path))
            return
        }
        busy = true
        statusText = L("准备中…")
        progress = 0
        UpdateChecker.shared.enterInstalling(feed)
        Task {
            do {
                try await run(feed, target: target)
                // 成功路径在 run 里 terminate，不会回到这里
            } catch {
                busy = false
                Self.fail(feed, (error as? AtlasError)?.message ?? error.localizedDescription)
            }
        }
    }

    // MARK: 主流程

    private func run(_ feed: Appcast, target: URL) async throws {
        setStatus(L("正在定位安装包…"), progress: 0.02)
        let dmgURL = try await Self.resolveDMGURL(feed)

        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skill-atlas-update-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let dmgFile = staging.appendingPathComponent("update.dmg")

        try await download(from: dmgURL, to: dmgFile)

        if !feed.sha256.isEmpty {
            setStatus(L("正在校验安装包…"), progress: 0.80)
            let digest = try Self.sha256(of: dmgFile)
            guard digest.caseInsensitiveCompare(feed.sha256) == .orderedSame else {
                throw AtlasError(LF("安装包校验失败（sha256 不一致），已中止。下载 %@，公告 %@", digest, feed.sha256))
            }
        }

        setStatus(L("正在展开安装包…"), progress: 0.86)
        let version = feed.version
        let staged = try await Task.detached(priority: .userInitiated) {
            try Self.stageApp(dmg: dmgFile, staging: staging, expectVersion: version)
        }.value

        setStatus(L("即将重启完成更新…"), progress: 0.97)
        try Self.spawnSwapHelper(staged: staged, target: target, stagingDir: staging, version: feed.version)
        try? await Task.sleep(nanoseconds: 500_000_000)
        NSApp.terminate(nil)
        exit(0)
    }

    // MARK: 直链解析

    static func resolveDMGURL(_ feed: Appcast) async throws -> URL {
        if !feed.dmg.isEmpty, let direct = URL(string: feed.dmg) { return direct }
        let candidates = [
            "https://api.github.com/repos/\(repo)/releases/tags/v\(feed.version)",
            "https://api.github.com/repos/\(repo)/releases/latest",
        ]
        for api in candidates {
            guard let url = URL(string: api) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request) else { continue }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assets = object["assets"] as? [[String: Any]] else { continue }
            for asset in assets {
                if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                   let raw = asset["browser_download_url"] as? String,
                   let direct = URL(string: raw) {
                    return direct
                }
            }
        }
        throw AtlasError(L("找不到新版安装包（Release 里没有 .dmg 资产）。"))
    }

    // MARK: 下载（进度按 5%–75% 映射）

    private func download(from url: URL, to file: URL) async throws {
        setStatus(L("正在下载安装包…"), progress: 0.05)
        let (temp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AtlasError(LF("下载失败：HTTP %d", http.statusCode))
        }
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        try FileManager.default.moveItem(at: temp, to: file)
        setStatus(L("正在下载安装包…"), progress: 0.75)
    }

    static func sha256(of file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 挂载 → 校验 → 暂存

    nonisolated static func stageApp(dmg: URL, staging: URL, expectVersion: String) throws -> URL {
        // 下载物先去隔离位，防 hdiutil / Gatekeeper 半路插评估
        _ = try? runTool("/usr/bin/xattr", ["-d", "com.apple.quarantine", dmg.path])
        let mountPoint = staging.appendingPathComponent("mount", isDirectory: true)
        let attach = try runTool("/usr/bin/hdiutil", [
            "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path,
        ])
        guard attach.status == 0 else {
            throw AtlasError(LF("挂载安装包失败：%@", attach.stderr.isEmpty ? "hdiutil attach 未成功" : attach.stderr))
        }
        defer { _ = try? runTool("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

        let fileManager = FileManager.default
        guard let appName = try fileManager.contentsOfDirectory(atPath: mountPoint.path)
            .first(where: { $0.hasSuffix(".app") }) else {
            throw AtlasError(L("安装包里没有找到应用。"))
        }
        let mountedApp = mountPoint.appendingPathComponent(appName)
        let plist = mountedApp.appendingPathComponent("Contents/Info.plist")
        let newVersion = (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String) ?? ""
        guard UpdateChecker.compareVersions(newVersion, expectVersion) != .orderedAscending else {
            throw AtlasError(LF("安装包版本（%@）低于公告版本（%@），已中止。", newVersion.isEmpty ? "未知" : newVersion, expectVersion))
        }

        let staged = staging.appendingPathComponent(appName)
        let copy = try runTool("/usr/bin/ditto", [mountedApp.path, staged.path])
        guard copy.status == 0 else {
            throw AtlasError(LF("展开安装包失败：%@", copy.stderr))
        }
        _ = try? runTool("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        return staged
    }

    // MARK: 换装助手（等本进程退出后执行，失败回滚）

    nonisolated static func spawnSwapHelper(staged: URL, target: URL, stagingDir: URL, version: String) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        try? FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        let log = AtlasPaths.root.appendingPathComponent("update.log").path
        let backup = target.deletingLastPathComponent()
            .appendingPathComponent(target.lastPathComponent + ".updating-backup")
        let script = """
        #!/bin/sh
        exec >> "\(log)" 2>&1
        echo "== update to \(version) · $(date) =="
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "\(backup.path)"
        if ! /bin/mv "\(target.path)" "\(backup.path)"; then
            echo "backup move failed, abort"
            exit 1
        fi
        if /usr/bin/ditto "\(staged.path)" "\(target.path)"; then
            /usr/bin/xattr -dr com.apple.quarantine "\(target.path)" 2>/dev/null
            /bin/rm -rf "\(backup.path)"
            echo "swap ok"
        else
            echo "swap failed, rolling back"
            /bin/rm -rf "\(target.path)"
            /bin/mv "\(backup.path)" "\(target.path)"
        fi
        /usr/bin/open "\(target.path)"
        /bin/rm -rf "\(stagingDir.path)"
        echo "== done =="
        """
        let scriptURL = stagingDir.appendingPathComponent("swap.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    nonisolated static func runTool(_ tool: String, _ arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        func read(_ pipe: Pipe) -> String {
            String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return (process.terminationStatus, read(out), read(err))
    }

    private func setStatus(_ text: String, progress: Double) {
        statusText = text
        self.progress = progress
    }

    // MARK: 失败逃生门

    static func fail(_ feed: Appcast, _ message: String) {
        // 无头验收：-atlasQuit 时错误落盘退出，不弹模态窗挂住进程
        if LaunchArgs.flag("atlasQuit") {
            if let path = LaunchArgs.value("atlasProbeOut") {
                let payload = ["updateError": message, "version": feed.version]
                if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
                   let text = String(data: data, encoding: .utf8) {
                    try? text.write(toFile: path, atomically: true, encoding: .utf8)
                }
            }
            exit(1)
        }
        UpdateChecker.shared.enterInstallFailed(feed, message: message)
    }
}
