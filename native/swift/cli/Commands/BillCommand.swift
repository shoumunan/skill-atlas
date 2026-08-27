import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas bill [--platform claude] [--json]

enum BillCommand {
    static func run(_ args: Args) -> Int32 {
        var platformFilter: AgentPlatform?
        if let raw = args.platform {
            guard let platform = AgentPlatform(rawValue: raw) else {
                return fail(op: "bill", json: args.json, code: .usage,
                            message: LF("未知平台「%@」", raw), hint: knownPlatformsList())
            }
            platformFilter = platform
        }

        let scanData: AtlasData
        do {
            scanData = try SkillScanner.scan()
        } catch {
            return fail(op: "bill", json: args.json, code: .general, message: error.localizedDescription)
        }
        var skills = scanData.skills.filter { !$0.disabled }
        if let platformFilter {
            skills = skills.filter { $0.platforms.contains(platformFilter.label) }
        }
        let usage = UsageIndexer.loadCached()
        let stale = staleDirectories(skills: skills, usage: usage)
        let window = contextWindowTokensDefault()
        let report = ContextDoctor.report(
            skills: skills, usage: usage, staleDirectories: stale, contextWindowTokens: window
        )
        let atRiskDirs = Set(report.atRisk.map { $0.skill.directory })
        let overlongDirs = Set(report.overlong.map { $0.skill.directory })

        let perSkill = report.entries.map { entry -> [String: Any] in
            let tier: String
            if overlongDirs.contains(entry.skill.directory) { tier = "overlong" }
            else if atRiskDirs.contains(entry.skill.directory) { tier = "at_risk" }
            else { tier = "core" }
            return ["name": entry.skill.name, "dir": entry.skill.directory, "chars": entry.chars,
                    "tokens": entry.tokens, "tier": tier]
        }
        let totalChars = report.entries.reduce(0) { $0 + $1.chars }

        let data: [String: Any] = [
            "platform": jsonOrNull(platformFilter?.rawValue),
            "total": ["chars": totalChars, "tokens": report.totalTokens],
            "perSkill": perSkill,
        ]
        return succeed(op: "bill", json: args.json, data: data) {
            say(LF("当前每个会话开场约花 %d token 读技能清单（估算）", report.totalTokens))
        }
    }
}
