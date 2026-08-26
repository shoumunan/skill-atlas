import Foundation

// MARK: - 单技能试跑（三期 G3）
//
// 在一个只加载这一个技能的干净环境里起一次真实会话：验证「它到底会不会被触发」、
// 「触发之后的行为对不对」。这是 F1 试触发与 G2 描述开药一直在离线近似的东西的真身。
//
// 机制：CLAUDE_CONFIG_DIR 把 Claude Code 的配置根（.claude.json 与 settings.json）
// 整个重定位到沙箱目录，于是 ~/.claude/skills 的 143 个技能一个都不参与；
// CLAUDE_SECURESTORAGE_CONFIG_DIR 置空 = 仍用系统钥匙串里的登录态，不用重新登录。
//
// **名字只承诺它能兑现的**：隔离的是「技能加载面」，不是「破坏半径」。
// 会话里的 Bash/Edit 仍以当前用户身份运行，能读写整个 HOME、能联网外传。
// 所以它不是安全沙箱，不能拿来试毒——UI 必须原话这么说，不许含糊。
//
// 技能用 clonefile 拷贝而非软链：软链会让试跑里的写操作直接改到本库的技能源目录。
//
// 沙箱目录必须留在 ~/.skill-atlas/sandbox（AtlasPaths.root 下、libraryRoot 之外）：
// 一旦挪进 skills/，Scanner 会把 config/skills/<x> 扫成散装技能，「收编条」会诱导
// 用户把幽灵技能收进库——scanAtlasLibrary 的隐藏项过滤拦不住 config 这种正常目录名。
/// App 启动时注入 SkillLauncher.openTerminalForSandbox；CLI 不注入（WP5 只打印命令）。
/// core 不能依赖 AppKit，所以用函数钩子而不是直接调 AppleScript。
package enum SandboxTerminal {
    package static var opener: ((String) throws -> Void)?
}

package enum SkillSandbox {
    package static var sandboxRoot: URL { AtlasPaths.root.appendingPathComponent("sandbox") }

    package struct Plan {
        package var root: URL
        package var configDir: URL
        package var workDir: URL
        package var skillDir: URL
        package var command: String
        /// 未能隔离的项：UI 原样渲染，不许折叠不许美化
        package var caveats: [String]
    }

    package static func plan(for skill: Skill) -> Plan {
        let stamp = stampFormatter.string(from: Date())
        let root = sandboxRoot.appendingPathComponent("\(skill.directory)-\(stamp)")
        let configDir = root.appendingPathComponent("config")
        let workDir = root.appendingPathComponent("work")
        let skillDir = configDir.appendingPathComponent("skills").appendingPathComponent(skill.directory)

        // 环境变量前置在同一条命令里：不写进用户的 shell 配置，关掉窗口即失效。
        // CLAUDE_SECURESTORAGE_CONFIG_DIR 显式置空 = 沿用真实钥匙串条目。
        let command = "cd \(shellQuote(workDir.path)) && "
            + "CLAUDE_CONFIG_DIR=\(shellQuote(configDir.path)) "
            + "CLAUDE_SECURESTORAGE_CONFIG_DIR='' "
            + "claude"

        return Plan(
            root: root, configDir: configDir, workDir: workDir, skillDir: skillDir,
            command: command,
            caveats: [
                L("不是安全沙箱：会话里的命令与文件编辑仍以你本人的身份运行，能读写整台机器、能联网。"),
                L("共用你的登录态与额度：试跑消耗的是你自己的用量。"),
                L("权限询问保持开启（不加 --dangerously-skip-permissions），每个动作仍会问你。"),
                L("技能是拷贝进沙箱的：在里面改它不会影响技能库里的原件。"),
            ]
        )
    }

    /// 建目录 + 拷技能 + 写两份种子配置。任何一步失败都清空，不留半成品。
    package static func materialize(_ plan: Plan, skill: Skill) throws {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: plan.workDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(
                at: plan.skillDir.deletingLastPathComponent(), withIntermediateDirectories: true
            )

            let source = URL(fileURLWithPath: skill.sourcePath, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path) else {
                throw AtlasError(LF("找不到技能源目录：%@", source.path))
            }
            try FileClone.cloneDirectory(from: source, to: plan.skillDir)

            // 只跳过首次运行向导，不预先信任目录——「替用户点掉一次确认」正是
            // 这个功能最不该做的事（它装的可能就是一个你不信任的技能）。
            let globalConfig: [String: Any] = [
                "hasCompletedOnboarding": true,
                "numStartups": 1,
            ]
            try write(globalConfig, to: plan.configDir.appendingPathComponent(".claude.json"))

            // 内置技能也关掉：这样清单里就只剩被试的那一个，触发归因才干净
            let settings: [String: Any] = ["disableBundledSkills": true]
            try write(settings, to: plan.configDir.appendingPathComponent("settings.json"))

            let readme = L("""
            这是 Skill Atlas 的单技能试跑目录，可以随便折腾。
            当前会话只加载了一个技能，配置根是同级的 config/。
            关掉窗口后，在 Skill Atlas 设置页可以一键清理这些目录。
            """)
            try readme.write(
                to: plan.workDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8
            )

            let meta: [String: Any] = [
                "skill": skill.name,
                "directory": skill.directory,
                "createdAt": Int(Date().timeIntervalSince1970),
            ]
            try write(meta, to: plan.root.appendingPathComponent("sandbox.json"))
        } catch {
            try? fileManager.removeItem(at: plan.root)
            throw error
        }
    }

    /// 全流程。dryRunProbe 非空时只落盘计划、不开终端（无头验收用）。
    /// 标 @MainActor：末尾要走 SkillLauncher 的 AppleScript 通路（主线程隔离）。
    @MainActor
    @discardableResult
    package static func run(skill: Skill, dryRunProbe: String? = nil) throws -> Plan {
        let plan = plan(for: skill)
        try materialize(plan, skill: skill)
        if let dryRunProbe {
            let payload: [String: Any] = [
                "skill": skill.name,
                "root": plan.root.path,
                "command": plan.command,
                "skillPresent": FileManager.default.fileExists(
                    atPath: plan.skillDir.appendingPathComponent("SKILL.md").path
                ),
                "isSymlink": LinkTool.isSymlink(plan.skillDir),
                "configKeys": (try? FileManager.default.contentsOfDirectory(atPath: plan.configDir.path))?.sorted() ?? [],
                "caveats": plan.caveats,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                try? text.write(toFile: dryRunProbe, atomically: true, encoding: .utf8)
            }
            return plan
        }
        guard let opener = SandboxTerminal.opener else {
            throw AtlasError(LF("无法打开 Terminal：沙箱命令是 %@", plan.command))
        }
        try opener(plan.command)
        return plan
    }

    // MARK: 清理（只在用户点的时候做）
    //
    // 不做「超过 N 小时自动清扫」：阈值是拍脑袋定的，而正在跑的试跑会话没有任何
    // 信号告诉 App 它还活着——自动清扫等于随时可能把用户正在用的目录移进废纸篓。

    package static func existing() -> [URL] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: sandboxRoot, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return a > b
        }
    }

    /// 移入废纸篓而非直接删——与本 App 其余破坏性动作同一口径，误清了还能捞回来
    @discardableResult
    package static func clearAll() -> Int {
        var count = 0
        for url in existing() {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                count += 1
            } catch {
                continue
            }
        }
        return count
    }

    // MARK: 小工具

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func write(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
