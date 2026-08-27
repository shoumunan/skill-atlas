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
        let name = sanitize(raw)
        guard name != MetaSkill.directory, name.count >= 2 else {
            return fail(op: "new", json: args.json, code: .usage,
                        message: LF("技能名「%@」不合法。用小写字母、数字和连字符。", raw))
        }
        let dest = AtlasPaths.libraryRoot.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) || AtlasCatalog.load().skills[name] != nil {
            return fail(op: "new", json: args.json, code: .conflict,
                        message: LF("已有同名技能「%@」", name))
        }

        guard AtlasLock.acquire(timeout: 5) else {
            return fail(op: "new", json: args.json, code: .locked,
                        message: L("技能库正在被另一个 Skill Atlas 进程写入，请稍后再试。"))
        }
        defer { AtlasLock.release() }

        var extra = ""
        if args.flags.contains("from-clipboard") {
            extra = pbpaste()
        }

        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let body = scaffold(name: name, extra: extra)
            try body.write(to: dest.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            var enabled: [String: Bool] = [:]
            let platforms = PreferredPlatforms.current
            for platform in AgentPlatform.allCases {
                enabled[platform.rawValue] = platforms.contains(platform.rawValue)
            }
            let now = Int(Date().timeIntervalSince1970)
            try AtlasCatalog.upsert(AtlasSkillRecord(
                directory: name,
                enabled: enabled,
                repoOwner: "",
                repoName: "",
                repoBranch: "main",
                installedAt: now,
                updatedAt: now,
                managed: false
            ))
            for platform in AgentPlatform.allCases where platforms.contains(platform.rawValue) {
                let root = platform.resolvedRoot(home: AtlasPaths.home)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let link = root.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: link.path) {
                    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dest)
                }
            }
            Oplog.record(actor: "cli", op: "new", target: name, ok: true, detail: dest.path)
        } catch {
            Oplog.record(actor: "cli", op: "new", target: name, ok: false, detail: error.localizedDescription)
            return fail(op: "new", json: args.json, code: .general, message: error.localizedDescription)
        }

        let data: [String: Any] = [
            "dir": name,
            "path": dest.path,
            "next": LF("用 atlas simulate \"%@ 场景句\" 验证会不会排到第一；再 atlas sandbox %@ 试跑。", name, name),
        ]
        return succeed(op: "new", json: args.json, data: data) {
            say(dest.path)
            say(L("已建空技能。把触发三元组写进 description，再用 atlas simulate 验证。"))
        }
    }

    private static func sanitize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let kept = lowered.unicodeScalars.map { scalar -> Character? in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            if scalar == "-" || scalar == "_" { return "-" }
            return nil
        }.compactMap { $0 }
        return String(kept).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
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

    private static func scaffold(name: String, extra: String) -> String {
        let extraBlock = extra.isEmpty ? "" : "\n\n## 剪贴板草稿\n\n\(extra)\n"
        return """
        ---
        name: \(name)
        description: >
          一句话能力。把用户会说的触发短语用「」括起来，全部写在前 250 字符内。
          # 触发三元组：① 能力句（动词+对象）② 「用户原话」③ 可选负向排除
          # 总长建议 ≤200 字，自己先过 ContextDoctor 口径。
        ---

        # \(name)

        把步骤写在这里。这是脚手架，内容由宿主 agent 填写。
        \(extraBlock)
        """
    }
}
