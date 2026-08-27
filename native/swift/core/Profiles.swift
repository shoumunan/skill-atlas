import Foundation

// MARK: - 场景 Profile（三期 G8）
//
// 痛点：143 个技能共用一份全局清单，写基金材料的会话里挂着券商工具和个人项目技能。
//
// 实现走 Claude Code 自己的 skillOverrides（2.1.229 实测存在，用户级/项目级/local
// 三层级联）：Profile = 一组「这个场景里该出现的技能」，落地时把**非成员**写成
// "user-invocable-only"（仍可 /名字 手动调用，但不进模型看到的清单）或 "off"。
//
// 为什么不是翻软链：
// - 写一份 JSON 就生效，App 不需要常驻、不需要感知你在哪个目录敲 claude
// - 完全可逆（删键即恢复），不动文件系统，不与 G1 的补丁保护/收编/停用机制打架
// - per-project 绑定天然解决「在 Jung8 目录开会话不要出现基金技能」
// 代价：只对 Claude Code 生效。Codex/Gemini 等平台没有等价机制，UI 必须说清楚。
//
// **存独立文件而不是往 atlas.json 加字段**：老版本 App 的 AtlasCatalog.save() 会把
// 不认识的键整段丢掉，而 ~/.skill-atlas 是 F8 的 git 同步仓库，混版本机器一次保存
// 就把 Profile 清空并提交掉；反向加非 Optional 字段更会让老 atlas.json 解码失败、
// 全库 enabled 位清零（见 AtlasSkillRecord 头上的警告）。

/// Profile 里非成员技能的处置方式
package enum ProfileExclusion: String, Codable, CaseIterable {
    /// 仍能用 /技能名 手动调用，只是不进模型的自动匹配清单——默认，最不容易误伤
    case userInvocableOnly = "user-invocable-only"
    /// 彻底关掉，手动也调不出
    case off

    package var title: String {
        switch self {
        case .userInvocableOnly: return L("留手动调用（不进自动清单）")
        case .off: return L("完全关闭")
        }
    }
}

package struct AtlasProfile: Codable, Identifiable, Equatable {
    /// UUID 字符串：改名不断绑定
    package var id: String
    package var name: String
    package var symbol: String
    /// 成员技能的**目录名**（本 App 的稳定主键；写盘时才翻译成技能名）
    package var members: [String]
    package var exclusion: ProfileExclusion
    package var updatedAt: Int

    package static func new(name: String, symbol: String = "square.grid.2x2") -> AtlasProfile {
        AtlasProfile(
            id: UUID().uuidString, name: name, symbol: symbol, members: [],
            exclusion: .userInvocableOnly, updatedAt: Int(Date().timeIntervalSince1970)
        )
    }
}

/// 把 Profile 钉在某个项目目录上：写 <目录>/.claude/settings.local.json，
/// 之后由 Claude Code 自己的设置级联生效，App 关掉照样管用。
package struct ProfileBinding: Codable, Equatable, Identifiable {
    package var directory: String
    package var profileID: String
    package var boundAt: Int
    /// 本 App 实际写进去的键。解绑时只删这些键里「值仍是我们写的那个」的，
    /// 用户后来自己在 /skills 里改过的不动。
    package var appliedKeys: [String]

    package var id: String { directory }

    package init(directory: String, profileID: String, boundAt: Int, appliedKeys: [String]) {
        self.directory = directory
        self.profileID = profileID
        self.boundAt = boundAt
        self.appliedKeys = appliedKeys
    }
}

package struct ProfilesFile: Codable {
    package var version: Int = 1
    package var profiles: [AtlasProfile] = []
    /// 用户级默认 Profile（写 ~/.claude/settings.json），管所有没绑目录的会话
    package var activeProfileID: String?
    package var activeAppliedKeys: [String] = []
    package var bindings: [ProfileBinding] = []

    // 今后新增字段一律 Optional 或给 decodeIfPresent——理由同 AtlasSkillRecord

    package init(
        version: Int = 1,
        profiles: [AtlasProfile] = [],
        activeProfileID: String? = nil,
        activeAppliedKeys: [String] = [],
        bindings: [ProfileBinding] = []
    ) {
        self.version = version
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.activeAppliedKeys = activeAppliedKeys
        self.bindings = bindings
    }
}

package enum ProfileStore {
    package static var url: URL { AtlasPaths.root.appendingPathComponent("profiles.json") }

    /// 读不到/解不开都返回空表。这里可以放心兜底：profiles.json 的「解码失败=空」
    /// 只会丢 Profile 定义，不像 atlas.json 那样会连带清空 145 条技能的挂载态。
    package static func load() -> ProfilesFile {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ProfilesFile.self, from: data) else {
            return ProfilesFile()
        }
        return file
    }

    package static func save(_ file: ProfilesFile) throws {
        try FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }
}

// MARK: - 落地：读写 Claude Code 的 settings

package enum ProfileWriter {
    /// 写盘计划。UI 必须先把它原样展示给用户确认，再执行——这是「改用户配置文件」
    /// 这类动作的最低门槛。
    package struct Plan {
        package var targetPath: String
        /// 会被摘出自动清单的技能名
        package var excluded: [String]
        /// 留在清单里的技能名
        package var kept: [String]
        /// 因重名而无法表达的技能（skillOverrides 按名索引，同名只能有一个值）
        package var conflicts: [String]
        /// 目标文件已存在的、本 App 之外的 skillOverrides 键（会被保留，不动）
        package var foreignKeys: [String]
        package var exclusion: ProfileExclusion
    }

    /// 用户级默认：~/.claude/settings.json
    package static var userSettingsURL: URL {
        AtlasPaths.home.appendingPathComponent(".claude/settings.json")
    }

    /// 项目级：<目录>/.claude/settings.local.json（Claude Code 的 local 层，优先级最高）
    package static func projectSettingsURL(for directory: URL) -> URL {
        directory.appendingPathComponent(".claude/settings.local.json")
    }

    package static func plan(profile: AtlasProfile, skills: [Skill], target: URL) -> Plan {
        let memberDirs = Set(profile.members)
        let memberNames = Set(skills.filter { memberDirs.contains($0.directory) }.map(\.name))

        var excluded: [String] = []
        var kept: [String] = []
        var conflicts: [String] = []
        for skill in skills where !skill.disabled {
            if skill.directory == MetaSkill.directory {
                kept.append(skill.name)
                continue
            }
            if memberDirs.contains(skill.directory) {
                kept.append(skill.name)
            } else if memberNames.contains(skill.name) {
                // 同名技能一个在 Profile 里一个不在：skillOverrides 按名索引，
                // 写谁都会误伤另一个。保守起见两个都留着，并如实报给用户。
                conflicts.append(skill.name)
            } else {
                excluded.append(skill.name)
            }
        }

        let existing = (try? readSettings(at: target)) ?? [:]
        let existingOverrides = existing["skillOverrides"] as? [String: Any] ?? [:]
        let ourValues = Set(ProfileExclusion.allCases.map(\.rawValue))
        let foreign = existingOverrides.compactMap { key, value -> String? in
            guard let text = value as? String else { return key }
            return ourValues.contains(text) ? nil : key
        }

        return Plan(
            targetPath: target.path.replacingOccurrences(of: AtlasPaths.home.path, with: "~"),
            excluded: excluded.sorted(), kept: kept.sorted(),
            conflicts: conflicts.sorted(), foreignKeys: foreign.sorted(),
            exclusion: profile.exclusion
        )
    }

    /// 应用：把非成员写成 exclusion 值。返回实际写入的键，供解绑时精确回收。
    @discardableResult
    package static func apply(profile: AtlasProfile, skills: [Skill], target: URL, previousKeys: [String]) throws -> [String] {
        var settings = try readSettings(at: target)
        var overrides = settings["skillOverrides"] as? [String: Any] ?? [:]

        // 先撤上一次我们写的（Profile 换了成员，旧键要退场，否则越积越多）
        for key in previousKeys {
            if let text = overrides[key] as? String,
               ProfileExclusion.allCases.map(\.rawValue).contains(text) {
                overrides.removeValue(forKey: key)
            }
        }

        let plan = plan(profile: profile, skills: skills, target: target)
        for name in plan.excluded {
            overrides[name] = profile.exclusion.rawValue
        }
        if overrides.isEmpty {
            settings.removeValue(forKey: "skillOverrides")
        } else {
            settings["skillOverrides"] = overrides
        }
        try writeSettings(settings, to: target)
        return plan.excluded
    }

    /// 撤销：只删我们写过、且值仍是我们写的那个的键。
    /// 不把键设成 "on"——"on" 本身也是一条覆盖，会压住用户自己在 /skills 里的选择。
    package static func revert(target: URL, appliedKeys: [String]) throws {
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        var settings = try readSettings(at: target)
        guard var overrides = settings["skillOverrides"] as? [String: Any] else { return }
        let ourValues = Set(ProfileExclusion.allCases.map(\.rawValue))
        for key in appliedKeys {
            if let text = overrides[key] as? String, ourValues.contains(text) {
                overrides.removeValue(forKey: key)
            }
        }
        if overrides.isEmpty {
            settings.removeValue(forKey: "skillOverrides")
        } else {
            settings["skillOverrides"] = overrides
        }
        try writeSettings(settings, to: target)
    }

    // MARK: 安全读写

    /// 非法 JSON 一律拒写——宁可什么都不做，也不能弄坏用户的配置
    package static func readSettings(at url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AtlasError(LF("%@ 不是合法 JSON。为避免弄坏你的配置，本次不写入。", url.lastPathComponent))
        }
        return object
    }

    package static func writeSettings(_ settings: [String: Any], to url: URL) throws {
        // 写前留一份原文，按来源分域（全局 / 各项目各一格，互不挤占）
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            try? HookTelemetry.backup(data, label: HookTelemetry.label(for: url))
        }
        let out = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try out.write(to: url, options: .atomic)
    }
}
