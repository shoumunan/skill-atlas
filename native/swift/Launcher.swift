import AppKit
import Foundation

// MARK: - Terminal 通路（试跑探针复用，界面不露「发起会话」）

enum SkillLauncher {
    static func openTerminalForSandbox(command: String) throws {
        try openTerminal(running: command)
    }

    /// Terminal.app 新窗口执行（首次会弹「控制 Terminal」授权，系统级、一次性）
    private static func openTerminal(running commandLine: String) throws {
        let escaped = commandLine
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw AtlasError(L("无法构造 Terminal 启动脚本"))
        }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo, let message = errorInfo[NSAppleScript.errorMessage] as? String {
            throw AtlasError(LF("打开 Terminal 失败：%@（首次使用需在弹窗里允许控制 Terminal）", message))
        }
    }
}


// MARK: - 库 git 化（二期 F8：多机同步的最小闭环）
//
// App 只做三件事：init（含 .gitignore 与首次提交）、快照提交、状态展示。
// remote/push 交给用户在终端做——「在终端打开」一键到位，不在 GUI 里管凭据。

enum GitSync {
    static var libraryRoot: URL { AtlasPaths.root }

    static func isRepo() -> Bool {
        FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent(".git").path)
    }

    struct Status {
        var branch: String
        var dirtyCount: Int
        var lastCommit: String
    }

    static func status() -> Status? {
        guard isRepo() else { return nil }
        let branch = run(["rev-parse", "--abbrev-ref", "HEAD"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
        let dirty = run(["status", "--porcelain"])?
            .split(separator: "\n").filter { !$0.isEmpty }.count ?? 0
        let last = run(["log", "-1", "--format=%cd · %s", "--date=format:%m/%d %H:%M"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Status(branch: branch, dirtyCount: dirty, lastCommit: last)
    }

    /// 不该进 git 快照的东西。往 ~/.skill-atlas 塞新文件的功能**必须**在这里登记，
    /// 否则 snapshot() 的 `git add -A` 会把它们推到远端：settings 备份含用户 env 与
    /// API base、事件日志含使用行为、沙箱与 Profile 快照都是一次性物。
    static let defaultIgnores = [
        "usage-index.json",
        "security-index.json",
        "usage-events.jsonl",
        "skill-backups/",
        "settings-backups/",
        "profile-snapshots/",
        "sandbox/",
        "update.log",
        ".DS_Store",
    ]

    /// 幂等补齐 .gitignore。原实现只在文件不存在时写一次，于是 F8 之后新增的功能
    /// 在老仓库上永远补不进条目——新文件被静默纳入快照。
    static func ensureIgnored(_ lines: [String] = defaultIgnores) throws {
        let gitignore = libraryRoot.appendingPathComponent(".gitignore")
        let existing = (try? String(contentsOf: gitignore, encoding: .utf8)) ?? ""
        let present = Set(existing.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        let missing = lines.filter { !present.contains($0) }
        guard !missing.isEmpty else { return }
        var text = existing
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += missing.joined(separator: "\n") + "\n"
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try text.write(to: gitignore, atomically: true, encoding: .utf8)
    }

    /// git init + .gitignore（使用缓存与备份不入库）+ 首次提交
    static func initialize() throws {
        guard !isRepo() else { return }
        try ensureIgnored()
        guard run(["init"]) != nil else { throw AtlasError(L("git init 失败（本机没有可用的 git？）")) }
        _ = run(["add", "-A"])
        _ = run(["commit", "-m", "Skill Atlas 初始快照"])
    }

    /// 快照提交；无改动时返回 false
    @discardableResult
    static func snapshot() throws -> Bool {
        guard isRepo() else { throw AtlasError(L("还不是 git 仓库，先初始化")) }
        // 每次提交前补齐忽略项：老仓库是在这些文件出现之前 init 的
        try? ensureIgnored()
        _ = run(["add", "-A"])
        let dirty = run(["status", "--porcelain"])?
            .split(separator: "\n").filter { !$0.isEmpty }.count ?? 0
        guard dirty > 0 else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard run(["commit", "-m", "快照 " + formatter.string(from: Date())]) != nil else {
            throw AtlasError(L("提交失败，请在终端里查看 git 状态"))
        }
        return true
    }

    /// 在 Terminal 里打开库目录（配远端、push 都在终端做）
    @MainActor
    static func openInTerminal() {
        let source = """
        tell application "Terminal"
            activate
            do script "cd '\(libraryRoot.path)'"
        end tell
        """
        NSAppleScript(source: source)?.executeAndReturnError(nil)
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", libraryRoot.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return nil
        }
    }
}
