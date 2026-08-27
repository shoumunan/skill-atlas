import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas list [--platform p] [--json]

enum ListCommand {
    static func run(_ args: Args) -> Int32 {
        var platformFilter: AgentPlatform?
        if let raw = args.platform {
            guard let platform = AgentPlatform(rawValue: raw) else {
                return fail(op: "list", json: args.json, code: .usage,
                            message: LF("未知平台「%@」", raw), hint: knownPlatformsList())
            }
            platformFilter = platform
        }

        let started = Date()
        let scanData: AtlasData
        do {
            scanData = try SkillScanner.scan()
        } catch {
            return fail(op: "list", json: args.json, code: .general, message: error.localizedDescription)
        }
        let elapsed = Date().timeIntervalSince(started)

        var skills = scanData.skills
        if let platformFilter {
            skills = skills.filter { $0.platforms.contains(platformFilter.label) }
        }
        let usage = UsageIndexer.loadCached()
        let entries = skills.map { listEntryJSON($0, usage: usage) }

        let data: [String: Any] = [
            "skills": entries,
            "count": entries.count,
            "scanSeconds": elapsed,
        ]
        return succeed(op: "list", json: args.json, data: data) {
            say(LF("扫描 %d 个技能，%.3f 秒", scanData.skills.count, elapsed))
            for skill in skills {
                let plats = AgentPlatform.allCases
                    .filter { skill.platforms.contains($0.label) }
                    .map(\.rawValue)
                    .joined(separator: ",")
                let mark = skill.disabled ? " [\(L("已停用"))]" : ""
                say("\(skill.name)\t\(skill.directory)\t[\(plats)]\(mark)")
            }
        }
    }
}
