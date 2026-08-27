import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas enable|disable <name> [--platform p] [--json]
//
// 本 WP 唯一的写操作：包 AtlasLock（ADR-5，等 5 秒拿不到锁退出码 6），
// 成功/失败都记一笔 Oplog（actor "cli"）。链上动作与 catalog 落盘全在
// core 的 SkillActions.setPlatform 里，这里只做参数解析 + 锁 + 落盘后回读。

enum EnableDisableCommand {
    static func run(op: String, _ args: Args) -> Int32 {
        let enabled = (op == "enable")
        guard let token = args.positionals.first, !token.isEmpty else {
            return fail(op: op, json: args.json, code: .usage, message: LF("用法：atlas %@ <name> [--platform p]", op))
        }

        var targetPlatforms: [AgentPlatform]
        if let raw = args.platform {
            guard let platform = AgentPlatform(rawValue: raw) else {
                return fail(op: op, json: args.json, code: .usage,
                            message: LF("未知平台「%@」", raw), hint: knownPlatformsList())
            }
            targetPlatforms = [platform]
        } else {
            // 缺 --platform：按「我在用的软件」（PreferredPlatforms，与 App 首次引导同一套）
            targetPlatforms = PreferredPlatforms.current.compactMap { AgentPlatform(rawValue: $0) }
            if targetPlatforms.isEmpty { targetPlatforms = [.claude] }
        }

        guard AtlasLock.acquire(timeout: 5) else {
            return fail(op: op, json: args.json, code: .locked,
                        message: L("技能库正在被另一个 Skill Atlas 进程写入，请稍后再试。"))
        }
        defer { AtlasLock.release() }

        guard let directory = resolveDirectory(token) else {
            return fail(op: op, json: args.json, code: .notFound,
                        message: LF("找不到技能「%@」", token), hint: L("用 atlas list 查看库内技能"))
        }
        if directory == MetaSkill.directory {
            return fail(op: op, json: args.json, code: .conflict,
                        message: L("由本应用生成并挂到所有平台，不能单独停用。"))
        }

        var detailParts: [String] = []
        var firstFailure: Error?
        for platform in targetPlatforms {
            do {
                try SkillActions.setPlatform(directory: directory, platform: platform, enabled: enabled)
                detailParts.append("\(platform.rawValue):ok")
            } catch {
                detailParts.append("\(platform.rawValue):\(error.localizedDescription)")
                if firstFailure == nil { firstFailure = error }
            }
        }
        Oplog.record(
            actor: "cli", op: op, target: directory,
            ok: firstFailure == nil, detail: detailParts.joined(separator: "; ")
        )

        if let error = firstFailure {
            let code: ExitCode
            if error is SkillActions.NotFound { code = .notFound }
            else if error is SkillActions.Conflict { code = .conflict }
            else { code = .general }
            return fail(op: op, json: args.json, code: code, message: error.localizedDescription)
        }

        let record = AtlasCatalog.load().skills[directory]
        var platformsJSON: [String: Any] = [:]
        for platform in AgentPlatform.allCases {
            platformsJSON[platform.rawValue] = record?.isEnabled(platform) ?? false
        }
        let data: [String: Any] = ["dir": directory, "platforms": platformsJSON]
        return succeed(op: op, json: args.json, data: data) {
            say(LF("已更新「%@」", directory))
            for platform in targetPlatforms {
                say("\(platform.rawValue): \(enabled ? L("已启用") : L("已停用"))")
            }
        }
    }
}
