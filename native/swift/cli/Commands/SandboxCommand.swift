import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas sandbox <name> [--json]
//
// materialize 后打印可复制的启动命令。不开 Terminal——agent 自己就在终端里。

enum SandboxCommand {
    static func run(_ args: Args) -> Int32 {
        guard let token = args.positionals.first, !token.isEmpty else {
            return fail(op: "sandbox", json: args.json, code: .usage,
                        message: L("用法：atlas sandbox <name>"))
        }
        let scanData: AtlasData
        do {
            scanData = try SkillScanner.scan()
        } catch {
            return fail(op: "sandbox", json: args.json, code: .general, message: error.localizedDescription)
        }
        guard let skill = scanData.skills.first(where: {
            $0.directory == token || $0.name.lowercased() == token.lowercased()
        }) else {
            return fail(op: "sandbox", json: args.json, code: .notFound,
                        message: LF("找不到技能「%@」", token))
        }
        let plan = SkillSandbox.plan(for: skill)
        do {
            try SkillSandbox.materialize(plan, skill: skill)
        } catch {
            return fail(op: "sandbox", json: args.json, code: .general, message: error.localizedDescription)
        }
        let data: [String: Any] = [
            "dir": skill.directory,
            "root": plan.root.path,
            "command": plan.command,
            "caveats": plan.caveats,
        ]
        return succeed(op: "sandbox", json: args.json, data: data) {
            say(plan.command)
            for line in plan.caveats { say(line) }
        }
    }
}
