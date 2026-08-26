import Foundation

// MARK: - 我在用的软件（默认点亮哪些平台）
//
// 空库勾一次，之后新装默认点亮这些。没勾过就看本机有没有
// ~/.claude / ~/.cursor / ~/.codex 这类目录，都没有则只预勾 Claude。
// 从 BeginnerLoop.swift 挪到 core：InstallerModel 的默认勾选依赖它。

package enum PreferredPlatforms {
    package static let storageKey = "atlasPreferredPlatforms"
    package static let chosenKey = "atlasPreferredPlatformsChosen"

    package static var current: Set<String> {
        if UserDefaults.standard.bool(forKey: chosenKey),
           let stored = UserDefaults.standard.stringArray(forKey: storageKey) {
            let cleaned = Set(stored).intersection(allowed)
            if !cleaned.isEmpty { return cleaned }
        }
        return inferred
    }

    package static var inferred: Set<String> {
        var found = Set<String>()
        let home = AtlasPaths.home
        for raw in allowed {
            guard let platform = AgentPlatform(rawValue: raw) else { continue }
            let folder = platform.root(home: home).deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: folder.path) {
                found.insert(raw)
            }
        }
        if found.isEmpty { found.insert(AgentPlatform.claude.rawValue) }
        return found
    }

    package static func save(_ raw: Set<String>) {
        let cleaned = raw.intersection(allowed)
        let value = cleaned.isEmpty ? inferred : cleaned
        UserDefaults.standard.set(Array(value), forKey: storageKey)
        UserDefaults.standard.set(true, forKey: chosenKey)
    }

    private static let allowed: Set<String> = [
        AgentPlatform.claude.rawValue,
        AgentPlatform.codex.rawValue,
        AgentPlatform.gemini.rawValue,
        AgentPlatform.grokbuild.rawValue,
        AgentPlatform.cursor.rawValue,
        AgentPlatform.workbuddy.rawValue,
    ]
}
