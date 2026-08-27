import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas info <name> [--json]

enum InfoCommand {
    static func run(_ args: Args) -> Int32 {
        guard let token = args.positionals.first, !token.isEmpty else {
            return fail(op: "info", json: args.json, code: .usage, message: L("用法：atlas info <name>"))
        }

        let scanData: AtlasData
        do {
            scanData = try SkillScanner.scan()
        } catch {
            return fail(op: "info", json: args.json, code: .general, message: error.localizedDescription)
        }
        guard let skill = scanData.skills.first(where: { $0.directory == token })
            ?? scanData.skills.first(where: { $0.name.lowercased() == token.lowercased() }) else {
            return fail(op: "info", json: args.json, code: .notFound,
                        message: LF("找不到技能「%@」", token), hint: L("用 atlas list 查看库内技能"))
        }

        let usage = UsageIndexer.loadCached()
        let capped = String(skill.description.prefix(ContextDoctor.perEntryCap))
        let chars = capped.count
        let tokens = ContextDoctor.tokenEstimate(chars: capped) + 15

        let signals = TriggerLab.signals(of: skill).map { signal -> [String: Any] in
            [
                "phrase": signal.phrase,
                "position": jsonOrNull(signal.position),
                "buried": (signal.position ?? 0) > TriggerLab.visibleWindow,
            ]
        }

        let findings = SecurityScanner.scan(directory: URL(fileURLWithPath: skill.sourcePath, isDirectory: true))
        let findingsJSON = findings.map { finding -> [String: Any] in
            [
                "severity": severityName(finding.severity),
                "rule": finding.rule,
                "file": finding.file,
                "line": finding.line,
                "excerpt": finding.excerpt,
            ]
        }

        let data: [String: Any] = [
            "name": skill.name,
            "dir": skill.directory,
            "description": skill.description,
            "whenToUse": skill.whenToUse,
            "examplePrompts": skill.examplePrompts,
            "platforms": platformsDict(skill),
            "origin": skill.origin.rawValue,
            "disabled": skill.disabled,
            "updateAvailable": skill.updateAvailable,
            "installedAt": skill.installedAt,
            "updatedAt": skill.updatedAt,
            "sourcePath": skill.sourcePath,
            "skillFile": skill.skillFile,
            "repo": skill.repo,
            "usage": usageDict(skill.directory, usage: usage),
            "bill": [
                "chars": chars,
                "tokens": tokens,
                "overCap": skill.description.count > ContextDoctor.perEntryCap,
            ],
            "triggers": signals,
            "security": [
                "critical": findings.filter { $0.severity == .critical }.count,
                "warning": findings.filter { $0.severity == .warning }.count,
                "info": findings.filter { $0.severity == .info }.count,
                "findings": findingsJSON,
            ],
        ]
        return succeed(op: "info", json: args.json, data: data) {
            say("\(skill.name) (\(skill.directory))")
            say(skill.description)
            say(skill.whenToUse)
        }
    }
}
