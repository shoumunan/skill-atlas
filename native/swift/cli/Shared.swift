import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 各子命令共用的小工具
//
// 全部是「包装已有 core 引擎的输出」，不重新实现扫描/触发/计费逻辑
// （PLAN.md §6 WP1 要点：CLI 层只是包装成命令行接口 + JSON 序列化）。

/// `<name>` 既可能是目录名也可能是技能显示名：先按目录（catalog 主键）精确匹配，
/// 找不到再退回全库扫描按 name 大小写不敏感匹配。只认本库（origin == .atlas）技能——
/// CC Switch/本地散装技能不在 catalog 里，setPlatform 本来就管不了它们。
func resolveDirectory(_ token: String) -> String? {
    if AtlasCatalog.load().skills[token] != nil { return token }
    guard let data = try? SkillScanner.scan() else { return nil }
    if let hit = data.skills.first(where: { $0.origin == .atlas && $0.directory == token }) {
        return hit.directory
    }
    if let hit = data.skills.first(where: { $0.origin == .atlas && $0.name.lowercased() == token.lowercased() }) {
        return hit.directory
    }
    return nil
}

/// 长期未用目录集合：与 app/Store.swift 的 `staleSkills`（90 天未用 + 14 天新装观察期）
/// 同一口径，独立实现是因为那是 AppStore 的实例方法，cli target 不链 app target。
func staleDirectories(skills: [Skill], usage: [String: SkillUsage]) -> Set<String> {
    let now = Date()
    let cutoff = now.addingTimeInterval(-90 * 86400)
    let grace: TimeInterval = 14 * 86400
    let stale = skills.filter { skill in
        guard !skill.disabled else { return false }
        if skill.installedAt > 0,
           now.timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(skill.installedAt))) < grace {
            return false
        }
        guard let record = usage[skill.directory] else { return true }
        guard let last = record.lastUsed else { return true }
        return last < cutoff
    }
    return Set(stale.map(\.directory))
}

/// 与 app/Store.swift 的 `contextWindowTokens` 同一读取口径（UserDefaults 键
/// "atlasContextWindow"，未设置或非正数时回退 200_000）。CLI 与 App 各自的
/// UserDefaults persistent domain 不同（不同可执行文件），互不干扰、也互不共享。
func contextWindowTokensDefault() -> Int {
    let window = UserDefaults.standard.integer(forKey: "atlasContextWindow")
    return window > 0 ? window : 200_000
}

func knownPlatformsList() -> String {
    AgentPlatform.allCases.map(\.rawValue).joined(separator: ", ")
}

func platformsDict(_ skill: Skill) -> [String: Any] {
    var dict: [String: Any] = [:]
    for platform in AgentPlatform.allCases {
        dict[platform.rawValue] = skill.platforms.contains(platform.label)
    }
    return dict
}

func usageDict(_ directory: String, usage: [String: SkillUsage]) -> [String: Any] {
    let record = usage[directory]
    return [
        "sessions": record?.total ?? 0,
        "last": jsonOrNull(record?.lastUsed.map { Int($0.timeIntervalSince1970) }),
    ]
}

func truncatedDescription(_ text: String, limit: Int = 120) -> String {
    text.count <= limit ? text : String(text.prefix(limit))
}

func severityName(_ severity: SecurityFinding.Severity) -> String {
    switch severity {
    case .critical: return "critical"
    case .warning: return "warning"
    case .info: return "info"
    }
}

func jsonOrNull(_ value: Int?) -> Any {
    value.map { $0 as Any } ?? NSNull()
}

func jsonOrNull(_ value: String?) -> Any {
    value.map { $0 as Any } ?? NSNull()
}

/// `list`/`search` 共用的单条技能载荷：PLAN.md §4.1 `atlas list` 行冻结的字段集
/// name/dir/desc(≤120)/platforms/origin/disabled/updateAvailable/usage。
func listEntryJSON(_ skill: Skill, usage: [String: SkillUsage]) -> [String: Any] {
    [
        "name": skill.name,
        "dir": skill.directory,
        "desc": truncatedDescription(skill.description),
        "platforms": platformsDict(skill),
        "origin": skill.origin.rawValue,
        "disabled": skill.disabled,
        "managed": skill.managed,
        "updateAvailable": skill.updateAvailable,
        "usage": usageDict(skill.directory, usage: usage),
    ]
}

func expandInstallSource(_ raw: String) -> String {
    let text = raw.trimmingCharacters(in: .whitespaces)
    if text.contains("://") || text.hasPrefix("/") || text.hasPrefix("~") || text.hasPrefix(".") {
        return text
    }
    let parts = text.split(separator: "/")
    if parts.count == 2, !text.contains(" ") {
        return "https://github.com/\(text)"
    }
    return text
}

func parsePlatformList(_ raw: String?) -> (platforms: Set<String>?, error: String?) {
    guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
        return (PreferredPlatforms.current, nil)
    }
    var result: Set<String> = []
    for token in raw.split(separator: ",") {
        let name = token.trimmingCharacters(in: .whitespaces).lowercased()
        guard let platform = AgentPlatform(rawValue: name) else {
            return (nil, LF("未知平台「%@」", String(token)))
        }
        result.insert(platform.rawValue)
    }
    if result.isEmpty { return (PreferredPlatforms.current, nil) }
    return (result, nil)
}
