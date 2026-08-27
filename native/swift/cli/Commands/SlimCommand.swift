import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas slim [--apply] [--json]
//
// 按 SlimRules 出草案；--apply 写入 Claude skillOverrides（先备份）。

enum SlimCommand {
    static func run(_ args: Args) -> Int32 {
        let scanData: AtlasData
        do {
            scanData = try SkillScanner.scan()
        } catch {
            return fail(op: "slim", json: args.json, code: .general, message: error.localizedDescription)
        }

        var usage = UsageIndexer.loadCached()
        if usage.isEmpty {
            let known = Set(scanData.skills.map(\.directory))
            usage = UsageIndexer.index(knownDirs: known, progress: { _ in }).usage
        }
        let favorites = Set(
            UserDefaults(suiteName: "local.skill-atlas.dashboard")?
                .stringArray(forKey: "skill-atlas-favorites") ?? []
        )
        let rows = SlimPlanner.draft(skills: scanData.skills, usage: usage, favorites: favorites)
        let before = ContextDoctor.report(
            skills: scanData.skills, usage: usage,
            staleDirectories: staleDirectories(skills: scanData.skills, usage: usage),
            contextWindowTokens: contextWindowTokensDefault()
        ).totalTokens

        if !args.flags.contains("apply") {
            let data: [String: Any] = [
                "beforeTokens": before,
                "core": rows.filter { $0.tier == .core }.count,
                "userInvocable": rows.filter { $0.tier == .userInvocable }.count,
                "off": rows.filter { $0.tier == .off }.count,
                "rows": rows.prefix(40).map { row -> [String: Any] in
                    ["name": row.name, "dir": row.directory, "sessions": row.sessions, "tier": row.tier.rawValue]
                },
            ]
            return succeed(op: "slim", json: args.json, data: data) {
                say(LF("草案：完整 %d · 仅用户可调 %d · 不挂载 %d。当前约 %d tok。加 --apply 才会写入。",
                       rows.filter { $0.tier == .core }.count,
                       rows.filter { $0.tier == .userInvocable }.count,
                       rows.filter { $0.tier == .off }.count,
                       before))
            }
        }

        guard AtlasLock.acquire(timeout: 5) else {
            return fail(op: "slim", json: args.json, code: .locked,
                        message: L("技能库正在被另一个 Skill Atlas 进程写入，请稍后再试。"))
        }
        defer { AtlasLock.release() }

        do {
            try SlimPlanner.apply(rows, target: ProfileWriter.userSettingsURL)
        } catch {
            Oplog.record(actor: "cli", op: "profile-apply", target: "slim-draft", ok: false,
                         detail: error.localizedDescription)
            return fail(op: "slim", json: args.json, code: .general, message: error.localizedDescription)
        }
        Oplog.record(actor: "cli", op: "profile-apply", target: "slim-draft", ok: true,
                     detail: "core \(rows.filter { $0.tier == .core }.count)")
        let after = ContextDoctor.report(
            skills: scanData.skills, usage: usage,
            staleDirectories: staleDirectories(skills: scanData.skills, usage: usage),
            contextWindowTokens: contextWindowTokensDefault()
        ).totalTokens
        let data: [String: Any] = [
            "beforeTokens": before,
            "afterTokens": after,
            "core": rows.filter { $0.tier == .core }.count,
            "excluded": rows.filter { $0.tier != .core }.count,
        ]
        return succeed(op: "slim", json: args.json, data: data) {
            say(LF("已应用瘦身草案：%d tok → %d tok。只对 Claude Code 生效。", before, after))
        }
    }
}
