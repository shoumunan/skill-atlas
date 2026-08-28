import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas profile list|show|apply <name> [--project DIR] [--json]

enum ProfileCommand {
    static func run(_ args: Args) -> Int32 {
        let sub = args.positionals.first ?? "list"
        switch sub {
        case "list": return list(args)
        case "show": return show(args)
        case "apply": return apply(args)
        default:
            return fail(op: "profile", json: args.json, code: .usage,
                        message: L("用法：atlas profile list|show|apply <name> [--project DIR]"))
        }
    }

    private static func list(_ args: Args) -> Int32 {
        let file = ProfileStore.load()
        let data: [String: Any] = [
            "active": jsonOrNull(file.profiles.first { $0.id == file.activeProfileID }?.name),
            "profiles": file.profiles.map { profile -> [String: Any] in
                [
                    "name": profile.name,
                    "id": profile.id,
                    "members": profile.members.count,
                    "exclusion": profile.exclusion.rawValue,
                    "active": profile.id == file.activeProfileID,
                ]
            },
        ]
        return succeed(op: "profile", json: args.json, data: data) {
            if file.profiles.isEmpty {
                say(L("还没有场景。"))
                return
            }
            for profile in file.profiles {
                let mark = profile.id == file.activeProfileID ? "*" : " "
                say("\(mark) \(profile.name)\t\(profile.members.count)\t\(profile.exclusion.rawValue)")
            }
        }
    }

    private static func show(_ args: Args) -> Int32 {
        guard let name = args.positionals.dropFirst().first else {
            return fail(op: "profile", json: args.json, code: .usage,
                        message: L("用法：atlas profile show <name>"))
        }
        let file = ProfileStore.load()
        guard let profile = file.profiles.first(where: { $0.name == name || $0.id == name }) else {
            return fail(op: "profile", json: args.json, code: .notFound,
                        message: LF("找不到场景「%@」", name))
        }
        let data: [String: Any] = [
            "name": profile.name,
            "id": profile.id,
            "members": profile.members,
            "exclusion": profile.exclusion.rawValue,
            "active": profile.id == file.activeProfileID,
        ]
        return succeed(op: "profile", json: args.json, data: data) {
            say("\(profile.name)\t\(profile.exclusion.rawValue)")
            for member in profile.members { say(member) }
        }
    }

    private static func apply(_ args: Args) -> Int32 {
        guard let name = args.positionals.dropFirst().first else {
            return fail(op: "profile", json: args.json, code: .usage,
                        message: L("用法：atlas profile apply <name> [--project DIR]"))
        }
        var file = ProfileStore.load()
        guard let profile = file.profiles.first(where: { $0.name == name || $0.id == name }) else {
            return fail(op: "profile", json: args.json, code: .notFound,
                        message: LF("找不到场景「%@」", name))
        }
        let scanData: AtlasData
        do {
            scanData = try SkillScanner.scan()
        } catch {
            return fail(op: "profile", json: args.json, code: .general, message: error.localizedDescription)
        }

        let target: URL
        if let project = args.project {
            target = ProfileWriter.projectSettingsURL(for: URL(fileURLWithPath: (project as NSString).expandingTildeInPath))
        } else {
            target = ProfileWriter.userSettingsURL
        }

        guard AtlasLock.acquire(timeout: 5) else {
            return fail(op: "profile", json: args.json, code: .locked,
                        message: L("技能库正在被另一个 Skill Atlas 进程写入，请稍后再试。"))
        }
        defer { AtlasLock.release() }

        do {
            let previous = args.project == nil ? file.activeAppliedKeys : []
            let applied = try ProfileWriter.apply(
                profile: profile, skills: scanData.skills, target: target, previousKeys: previous
            )
            // 非 Claude 平台没有「装着但不进清单」这一档，只能摘软链（账记在
            // scenario-mounts.json，catalog 的意图位不动）。只在全局场景时做：
            // 软链是全机唯一的，跟着某个项目目录翻会影响所有会话。
            var unmounted = 0
            if args.project == nil {
                unmounted = try ScenarioMounts.apply(profile: profile, skills: scanData.skills)
                file.activeProfileID = profile.id
                file.activeAppliedKeys = applied
                try ProfileStore.save(file)
            }
            Oplog.record(actor: "cli", op: "profile-apply", target: profile.name, ok: true,
                         detail: "excluded \(applied.count) @ \(target.path)")
            let data: [String: Any] = [
                "name": profile.name,
                "target": target.path,
                "excluded": applied.count,
            ]
            // data 的形状不动（ADR-12 CLI ABI 冻结）：多摘的软链只写进人读的那行，
            // JSON 消费方拿到的键与 2.3 一致
            return succeed(op: "profile", json: args.json, data: data) {
                if unmounted > 0 {
                    say(LF("已应用场景「%@」：Claude Code 里 %d 个技能不再进自动清单，另外 %d 处在别的软件里先摘下来了。",
                           profile.name, applied.count, unmounted))
                } else {
                    say(LF("已应用场景「%@」：%d 个技能不再进自动清单。这个场景只管 Claude Code。", profile.name, applied.count))
                }
                say(target.path)
            }
        } catch {
            Oplog.record(actor: "cli", op: "profile-apply", target: profile.name, ok: false,
                         detail: error.localizedDescription)
            return fail(op: "profile", json: args.json, code: .general, message: error.localizedDescription)
        }
    }
}
