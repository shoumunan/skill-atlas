import Foundation

// MARK: - 供给单写者（2.1 ADR-11）
//
// skillOverrides 曾有两个写者：ProfileWriter.apply（非成员统一一档 + 旧键回收）与
// SlimPlanner.apply（逐技能三档），语义不一致且各自直改 settings。本文件收拢为唯一
// 写入口：所有写 skillOverrides 的路径必须经 SupplyWriter.write / .revert（护栏 §7-14）。
// 备份、坏 JSON 拒写、meta-skill 豁免、「只动我们写过的键」在此集中执行。
// 读与算（ProfileWriter.plan / SlimPlanner.draft）不在这里，保持原位。

/// 逐技能三档目标态。core 表示撤掉我们的覆盖——不写 "on"，
/// "on" 本身也是一条覆盖，会压住用户自己在 /skills 里的选择。
package enum SupplyAssignment: Equatable {
    case core
    case userInvocable
    case off

    var overrideValue: String? {
        switch self {
        case .core: return nil
        case .userInvocable: return ProfileExclusion.userInvocableOnly.rawValue
        case .off: return ProfileExclusion.off.rawValue
        }
    }
}

package enum SupplyWriter {
    /// 写操作回执（v15 ReceiptLine 的数据源；token 前后对比由调用方按 ContextDoctor 口径计算）
    package struct Receipt {
        /// 实际写入覆盖的 技能名 → 档位值
        package var written: [String: String]
        /// 被撤掉覆盖的技能名
        package var cleared: [String]
        package var targetPath: String
    }

    /// 唯一写入口。assignments 键 = 技能名（skillOverrides 按名索引）。
    /// previousKeys：场景包上一次写入的键，先回收再落新值（成员变了旧键要退场）。
    /// 只增删「值是我们三档之一」的键；用户自己写的覆盖（含 "on"）一律不动。
    @discardableResult
    package static func write(
        assignments: [String: SupplyAssignment],
        target: URL,
        previousKeys: [String] = []
    ) throws -> Receipt {
        var settings = try ProfileWriter.readSettings(at: target)
        var overrides = settings["skillOverrides"] as? [String: Any] ?? [:]
        let ourValues = Set(ProfileExclusion.allCases.map(\.rawValue))

        var written: [String: String] = [:]
        var cleared: [String] = []

        for key in previousKeys where assignments[key] == nil {
            if let text = overrides[key] as? String, ourValues.contains(text) {
                overrides.removeValue(forKey: key)
                cleared.append(key)
            }
        }

        for (name, assignment) in assignments {
            // meta-skill 永不进排除集（ADR-3 纪律，集中在唯一写者执行）
            if name == MetaSkill.name { continue }
            if let value = assignment.overrideValue {
                overrides[name] = value
                written[name] = value
            } else if let text = overrides[name] as? String, ourValues.contains(text) {
                overrides.removeValue(forKey: name)
                cleared.append(name)
            }
        }

        if overrides.isEmpty {
            settings.removeValue(forKey: "skillOverrides")
        } else {
            settings["skillOverrides"] = overrides
        }
        try ProfileWriter.writeSettings(settings, to: target)
        return Receipt(
            written: written,
            cleared: cleared.sorted(),
            targetPath: target.path.replacingOccurrences(of: AtlasPaths.home.path, with: "~")
        )
    }

    /// 当前 settings 里由我们写的档位键（值是三档之一）。
    /// 「全部技能」与 UI 计数都要它，否则只能看见场景包那一部分。
    package static func ownedKeys(target: URL) -> [String] {
        guard let settings = try? ProfileWriter.readSettings(at: target),
              let overrides = settings["skillOverrides"] as? [String: Any] else { return [] }
        let ourValues = Set(ProfileExclusion.allCases.map(\.rawValue))
        return overrides.compactMap { key, value in
            guard let text = value as? String, ourValues.contains(text) else { return nil }
            return key
        }.sorted()
    }

    /// 撤销：只删我们写过、且值仍是我们三档之一的键（原 ProfileWriter.revert 语义原样搬入）。
    /// 不把键设成 "on"，理由见 SupplyAssignment.core。
    package static func revert(target: URL, appliedKeys: [String]) throws {
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        var settings = try ProfileWriter.readSettings(at: target)
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
        try ProfileWriter.writeSettings(settings, to: target)
    }
}
