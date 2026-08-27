import Foundation

// MARK: - 瘦身草案（WP3）
//
// 三档：完整挂载 / 仅用户可调 / 不挂载。一个 Profile 只能给非成员写同一种
// exclusion，所以混合三档不能走 ProfileWriter.apply，直接写 skillOverrides。

package enum SlimRules {
    package static let coreMinSessions = 5
    package static let staleDays = 90
}

package enum SlimTier: String, CaseIterable, Hashable {
    case core, userInvocable, off

    package var title: String {
        switch self {
        case .core: return L("完整挂载")
        case .userInvocable: return L("仅用户可调")
        case .off: return L("不挂载")
        }
    }
}

package struct SlimRow: Identifiable, Equatable {
    package var directory: String
    package var name: String
    package var sessions: Int
    package var lastUsed: Date?
    package var tier: SlimTier
    package var id: String { directory }
}

package enum SlimPlanner {
    package static func draft(
        skills: [Skill],
        usage: [String: SkillUsage],
        favorites: Set<String>
    ) -> [SlimRow] {
        let cutoff = Date().addingTimeInterval(TimeInterval(-SlimRules.staleDays * 24 * 3600))
        return skills
            .filter { !$0.disabled && $0.directory != MetaSkill.directory }
            .map { skill -> SlimRow in
                let record = usage[skill.directory]
                let sessions = record?.total ?? 0
                let last = record?.lastUsed
                let tier: SlimTier
                if favorites.contains(skill.name) || sessions >= SlimRules.coreMinSessions {
                    tier = .core
                } else if last == nil || last! < cutoff {
                    tier = .off
                } else {
                    tier = .userInvocable
                }
                return SlimRow(
                    directory: skill.directory, name: skill.name,
                    sessions: sessions, lastUsed: last, tier: tier
                )
            }
            .sorted { $0.sessions > $1.sessions }
    }

    /// 把草案写进 Claude 的 skillOverrides。meta-skill 永不进排除集。
    package static func apply(_ rows: [SlimRow], target: URL) throws {
        var settings = try ProfileWriter.readSettings(at: target)
        var overrides = settings["skillOverrides"] as? [String: Any] ?? [:]
        let ourValues = Set(ProfileExclusion.allCases.map(\.rawValue))
        for row in rows {
            if row.directory == MetaSkill.directory { continue }
            switch row.tier {
            case .core:
                if let text = overrides[row.name] as? String, ourValues.contains(text) {
                    overrides.removeValue(forKey: row.name)
                }
            case .userInvocable:
                overrides[row.name] = ProfileExclusion.userInvocableOnly.rawValue
            case .off:
                overrides[row.name] = ProfileExclusion.off.rawValue
            }
        }
        if overrides.isEmpty {
            settings.removeValue(forKey: "skillOverrides")
        } else {
            settings["skillOverrides"] = overrides
        }
        try ProfileWriter.writeSettings(settings, to: target)
    }
}
