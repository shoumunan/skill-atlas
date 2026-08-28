import Foundation

// MARK: - 创作脚手架（WP-D）
//
// `atlas new` 与创作页共用的 core 逻辑：App 不 shell 出去，CLI 不复制粘贴。
// 只 scaffold 不生成内容——LLM 就在旁边（宿主 agent），不在 App 里再塞一个（ADR-8）。

package enum SkillScaffold {
    package enum ScaffoldError: Error {
        case invalidName(String)
        case conflict(String)
        case locked
        case io(Error)

        package var message: String {
            switch self {
            case .invalidName(let raw):
                return LF("技能名「%@」不合法。用小写字母、数字和连字符。", raw)
            case .conflict(let name):
                return LF("已有同名技能「%@」", name)
            case .locked:
                return L("技能库正在被另一个 Skill Atlas 进程写入，请稍后再试。")
            case .io(let error):
                return error.localizedDescription
            }
        }
    }

    package struct Created {
        package var directory: String
        package var path: URL
    }

    package static func sanitize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let kept = lowered.unicodeScalars.map { scalar -> Character? in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            if scalar == "-" || scalar == "_" { return "-" }
            return nil
        }.compactMap { $0 }
        return String(kept).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// 建骨架：目录 + SKILL.md 模板 + catalog 记录 + 首选平台软链。锁语义与 CLI 一致。
    package static func create(rawName: String, extra: String, actor: String) throws -> Created {
        let name = sanitize(rawName)
        guard name != MetaSkill.directory, name.count >= 2 else {
            throw ScaffoldError.invalidName(rawName)
        }
        let dest = AtlasPaths.libraryRoot.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) || AtlasCatalog.load().skills[name] != nil {
            throw ScaffoldError.conflict(name)
        }
        guard AtlasLock.acquire(timeout: 5) else { throw ScaffoldError.locked }
        defer { AtlasLock.release() }

        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let body = scaffoldBody(name: name, extra: extra)
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
            Oplog.record(actor: actor, op: "new", target: name, ok: true, detail: dest.path)
            return Created(directory: name, path: dest)
        } catch {
            Oplog.record(actor: actor, op: "new", target: name, ok: false, detail: error.localizedDescription)
            throw ScaffoldError.io(error)
        }
    }

    package static func scaffoldBody(name: String, extra: String) -> String {
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
