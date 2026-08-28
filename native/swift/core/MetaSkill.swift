import Foundation

// MARK: - meta-skill skill-atlas（ADR-3）
//
// App 启动时生成并挂到所有平台。description ≤120 字符，自己不交清单税。
// SKILL.md 把 atlas 绝对路径写死，agent 零配置。路径变化则重写。

package enum MetaSkill {
    package static let directory = "skill-atlas"
    package static let name = "skill-atlas"

    package static func atlasBinaryURL() -> URL {
        let bundle = Bundle.main.bundleURL
        let bundled = bundle.appendingPathComponent("Contents/MacOS/atlas")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        return URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    }

    package static func ensure() {
        let dest = AtlasPaths.libraryRoot.appendingPathComponent(directory)
        let skillFile = dest.appendingPathComponent("SKILL.md")
        let binary = atlasBinaryURL().path
        let body = render(binary: binary)
        let current = (try? String(contentsOf: skillFile, encoding: .utf8)) ?? ""
        if current == body { return }
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try? body.write(to: skillFile, atomically: true, encoding: .utf8)

        var enabled: [String: Bool] = [:]
        for platform in AgentPlatform.allCases {
            enabled[platform.rawValue] = true
        }
        let now = Int(Date().timeIntervalSince1970)
        try? AtlasCatalog.upsert(AtlasSkillRecord(
            directory: directory,
            enabled: enabled,
            repoOwner: "skill-atlas",
            repoName: "meta",
            repoBranch: "main",
            installedAt: now,
            updatedAt: now,
            managed: true
        ))
        for platform in AgentPlatform.allCases {
            let root = platform.resolvedRoot(home: AtlasPaths.home)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let link = root.appendingPathComponent(directory)
            try? LinkTool.replaceSymlink(at: link, pointingTo: dest)
        }
    }

    private static func render(binary: String) -> String {
        // description 必须 ≤120 字符（自己先过 ContextDoctor 口径）。
        """
        ---
        name: \(name)
        description: 本地技能库的搜索、安装、启停、触发诊断与沉淀。用户要找技能、装技能、技能没触发、或要把流程写成技能时调用。
        metadata:
          managed-by: skill-atlas
          version: \(AtlasVersion.string)
        ---

        # Skill Atlas

        这是本机 Skill Atlas 的入口。用下面的命令，不要改用 curl|sh 或其他安装器绕过安全扫描。

        二进制（绝对路径，不要依赖 PATH）：

        `\(binary)`

        ## 什么时候用哪个命令

        - 用户要的能力库里可能已有：`\(binary) search <关键词> --json`
        - 库里没有、要去市场找：`\(binary) search <关键词> --remote --source all --json`（结果里 repoURL 非空的可直接 install）
        - 用户明确要装：`\(binary) install <github-url|owner/repo> --json`
        - 用户抱怨技能没触发：`\(binary) simulate "<用户原话>" --json`
        - 用户要把流程沉淀下来：`\(binary) new <name> --json`，装完可用 `\(binary) sandbox <name>` 隔离试跑
        - 诊断挂载/安全/重叠：`\(binary) doctor --json`
        - 看库存：`\(binary) list --json`

        ## 安全规则

        `install` 若退出码 3，stdout JSON 里有 `reviewURL`。必须把这个链接交给用户，停下等待人在 Skill Atlas 里批准，然后重跑同一条 install。不得改用其他安装途径绕过。

        `--json` 时 stdout 恰好一个 JSON 对象：`ok`、`code`、`op`、`data`、`error`。
        """
    }
}
