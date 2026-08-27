import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas simulate "<句子>" [--json]

enum SimulateCommand {
    static func run(_ args: Args) -> Int32 {
        let phrase = args.positionals.joined(separator: " ")
        guard !phrase.trimmingCharacters(in: .whitespaces).isEmpty else {
            return fail(op: "simulate", json: args.json, code: .usage, message: L("用法：atlas simulate <一句话任务>"))
        }

        let scanData: AtlasData
        do {
            scanData = try SkillScanner.scan()
        } catch {
            return fail(op: "simulate", json: args.json, code: .general, message: error.localizedDescription)
        }
        let usage = UsageIndexer.loadCached()
        let stale = staleDirectories(skills: scanData.skills, usage: usage)
        let window = contextWindowTokensDefault()
        let report = ContextDoctor.report(
            skills: scanData.skills, usage: usage, staleDirectories: stale, contextWindowTokens: window
        )
        let atRiskNames = Set(report.atRisk.map { $0.skill.name })
        let candidates = TriggerLab.simulate(phrase: phrase, skills: scanData.skills, usage: usage, atRiskNames: atRiskNames)

        let data: [String: Any] = [
            "phrase": phrase,
            "candidates": candidates.map { candidate -> [String: Any] in
                [
                    "name": candidate.skill.name,
                    "dir": candidate.skill.directory,
                    "score": candidate.score,
                    "matched": candidate.matched,
                    "buried": candidate.buried,
                    "atRisk": candidate.atRisk,
                    "disabled": candidate.disabled,
                    "usageCount": candidate.usageCount,
                ]
            },
        ]
        return succeed(op: "simulate", json: args.json, data: data) {
            say(LF("触发模拟「%@」", phrase))
            for candidate in candidates {
                say("\(candidate.score)\t\(candidate.skill.name)\t\(candidate.matched.joined(separator: ","))")
            }
        }
    }
}
