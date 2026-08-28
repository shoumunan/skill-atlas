import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas new <name> [--from-clipboard] [--json]
//
// 只 scaffold，不生成内容。内容交给宿主 agent。

enum NewCommand {
    static func run(_ args: Args) -> Int32 {
        guard let raw = args.positionals.first, !raw.isEmpty else {
            return fail(op: "new", json: args.json, code: .usage,
                        message: L("用法：atlas new <name> [--from-clipboard]"))
        }

        var extra = ""
        if args.flags.contains("from-clipboard") {
            extra = pbpaste()
        }

        // 全流程在 core（WP-D 下沉：创作页与 CLI 共用同一份逻辑，锁与 oplog 语义不变）
        let created: SkillScaffold.Created
        do {
            created = try SkillScaffold.create(rawName: raw, extra: extra, actor: "cli")
        } catch let error as SkillScaffold.ScaffoldError {
            let code: ExitCode
            switch error {
            case .invalidName: code = .usage
            case .conflict: code = .conflict
            case .locked: code = .locked
            case .io: code = .general
            }
            return fail(op: "new", json: args.json, code: code, message: error.message)
        } catch {
            return fail(op: "new", json: args.json, code: .general, message: error.localizedDescription)
        }

        let data: [String: Any] = [
            "dir": created.directory,
            "path": created.path.path,
            "next": LF("用 atlas simulate \"%@ 场景句\" 验证会不会排到第一；再 atlas sandbox %@ 试跑。",
                       created.directory, created.directory),
        ]
        return succeed(op: "new", json: args.json, data: data) {
            say(created.path.path)
            say(L("已建空技能。把触发三元组写进 description，再用 atlas simulate 验证。"))
        }
    }

    private static func pbpaste() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbpaste")
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
