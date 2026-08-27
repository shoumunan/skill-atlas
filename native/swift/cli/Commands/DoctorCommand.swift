import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas doctor [--json]
//
// §4.1: DoctorReport + 挂载失败 + 安全汇总 + 触发重叠 top。四块全部包已有引擎：
// ContextDoctor.report / SecurityScanner.scanInstalled / skill.problems / TriggerLab.overlapPairs。

enum DoctorCommand {
    static func run(_ args: Args) -> Int32 {
        let started = Date()
        let scanData: AtlasData
        do {
            scanData = try SkillScanner.scan()
        } catch {
            return fail(op: "doctor", json: args.json, code: .general, message: error.localizedDescription)
        }
        let skills = scanData.skills
        let usage = UsageIndexer.loadCached()
        let stale = staleDirectories(skills: skills, usage: usage)
        let window = contextWindowTokensDefault()
        let report = ContextDoctor.report(
            skills: skills, usage: usage, staleDirectories: stale, contextWindowTokens: window
        )

        // 安全汇总：只复扫本库/本地技能（CC Switch 只读来源跳过，与 App 的 rescanSecurity 一致）
        let targets = skills.filter { $0.origin != .ccSwitch && !$0.disabled }
            .map { (directory: $0.directory, path: $0.sourcePath) }
        let securityScan = SecurityScanner.scanInstalled(targets: targets)
        var critical = 0, warning = 0, info = 0
        var offenders: [(dir: String, critical: Int, warning: Int, info: Int)] = []
        for (dir, findings) in securityScan {
            let c = findings.filter { $0.severity == .critical }.count
            let w = findings.filter { $0.severity == .warning }.count
            let i = findings.filter { $0.severity == .info }.count
            critical += c; warning += w; info += i
            if c + w + i > 0 { offenders.append((dir, c, w, i)) }
        }
        offenders.sort { ($0.critical + $0.warning) > ($1.critical + $1.warning) }
        let topOffenders = offenders.prefix(5).map { entry -> [String: Any] in
            ["dir": entry.dir, "critical": entry.critical, "warning": entry.warning, "info": entry.info]
        }

        // 挂载失败：从 problems 里挑「挂载」相关的（Scanner 生成时已按平台写好中文短语）
        let mountFailures = skills.filter { skill in
            !skill.disabled && skill.problems.contains { $0.contains("挂载") }
        }.map { skill -> [String: Any] in
            [
                "name": skill.name,
                "dir": skill.directory,
                "problems": skill.problems.filter { $0.contains("挂载") },
            ]
        }

        let overlaps = TriggerLab.overlapPairs(skills)
        let overlapsJSON = overlaps.map { pair -> [String: Any] in
            ["first": pair.first.name, "second": pair.second.name, "shared": pair.shared]
        }

        let misses = MissDetect.report(skills: skills)
        let elapsed = Date().timeIntervalSince(started)
        let data: [String: Any] = [
            "budgetTokens": report.budgetTokens,
            "totalTokens": report.totalTokens,
            "overBudget": report.overBudget,
            "usageFraction": report.usageFraction,
            "reclaimableTokens": report.reclaimableTokens,
            "atRisk": report.atRisk.map { entry -> [String: Any] in
                ["name": entry.skill.name, "dir": entry.skill.directory, "chars": entry.chars,
                 "tokens": entry.tokens, "sessions": entry.sessions]
            },
            "overlong": report.overlong.map { entry -> [String: Any] in
                ["name": entry.skill.name, "dir": entry.skill.directory, "chars": entry.chars]
            },
            "verbose": report.verbose.prefix(20).map { entry -> [String: Any] in
                ["name": entry.skill.name, "dir": entry.skill.directory, "chars": entry.chars,
                 "sentences": entry.sentences, "suggestion": entry.suggestion]
            },
            "buriedTriggers": report.buried.map { entry -> [String: Any] in
                ["name": entry.skill.name, "dir": entry.skill.directory, "phrases": entry.phrases]
            },
            "mountFailures": mountFailures,
            "security": ["critical": critical, "warning": warning, "info": info, "topOffenders": Array(topOffenders)],
            "triggerOverlapsTop": overlapsJSON,
            "misses": misses.map { hit -> [String: Any] in
                [
                    "name": hit.name, "dir": hit.directory,
                    "occurrences": hit.occurrences, "score": hit.score,
                    "userInvocableOnly": hit.userInvocableOnly,
                    "samplePrompt": hit.samplePrompt,
                ]
            },
            "scanSeconds": elapsed,
        ]
        return succeed(op: "doctor", json: args.json, data: data) {
            say(LF("扫描 %d 个技能，%.3f 秒", skills.count, elapsed))
            say(LF("技能 %d · 估算 %d / %d token · 挂载问题 %d", skills.count, report.totalTokens, report.budgetTokens, mountFailures.count))
        }
    }
}
