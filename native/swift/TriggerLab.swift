import Foundation

// MARK: - 触发模拟器（二期 F1）：「这句话会唤醒谁」
//
// 技能没触发的真实原因（描述被截断 / 被预算丢弃 / 被同类抢走）在会话里完全不可见。
// 本引擎用与体检一致的口径做离线预演：
//   信号 = 描述里「」引号短语 + 技能名分词 + 任务别名（Rules.recommendAliases）
//   截断口径 = 社区实测 listing 前 250 字符——触发词埋在后面等于没写
// 结果是近似（真实匹配是模型语义行为），但足以回答「为什么跑去了别人家」。

struct TriggerCandidate: Identifiable {
    var skill: Skill
    var score: Int
    /// 命中的信号词（按贡献降序）
    var matched: [String]
    /// 命中但首次出现在前 250 字符之外的信号（等于对模型不可见）
    var buried: [String]
    /// 描述在当前预算的丢弃名单里
    var atRisk: Bool
    var disabled: Bool
    var usageCount: Int

    var id: String { skill.name }
}

enum TriggerLab {
    /// 社区实测 listing 截断口径：核心触发词必须落在前 250 字符
    static let visibleWindow = 250
    static let quotedPhrase = try! NSRegularExpression(pattern: "「([^」]{1,24})」")

    /// 技能的触发信号：短语 → 在描述里的首次位置（nil = 只在技能名里）
    static func signals(of skill: Skill) -> [(phrase: String, position: Int?)] {
        var result: [(String, Int?)] = []
        var seen = Set<String>()
        let description = skill.description
        let lowered = description.lowercased()

        // 「」引号短语（描述作者显式声明的触发词）
        let range = NSRange(description.startIndex..., in: description)
        for match in quotedPhrase.matches(in: description, range: range) {
            guard let swiftRange = Range(match.range(at: 1), in: description) else { continue }
            let phrase = String(description[swiftRange])
            guard seen.insert(phrase.lowercased()).inserted else { continue }
            let position = description.distance(
                from: description.startIndex, to: swiftRange.lowerBound
            )
            result.append((phrase, position))
        }

        // 技能名分词（名称永远可见，position = nil 表示不受截断影响）
        let stopWords: Set<String> = ["skill", "skills", "the", "and", "for", "with", "expert", "writer", "use", "new"]
        for token in skill.name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        where token.count >= 3 && !stopWords.contains(token) && seen.insert(token).inserted {
            result.append((token, nil))
        }

        // 描述里出现的任务别名值（做个PPT → ppt/slide/deck…）
        for values in Rules.recommendAliases.values {
            for value in values {
                let lower = value.lowercased()
                guard seen.insert(lower).inserted else { continue }
                if let range = lowered.range(of: lower) {
                    result.append((value, lowered.distance(from: lowered.startIndex, to: range.lowerBound)))
                }
            }
        }
        return result
    }

    /// 预演：这句话会唤醒谁。返回按得分降序的候选（最多 8 个）。
    static func simulate(
        phrase: String,
        skills: [Skill],
        usage: [String: SkillUsage],
        atRiskNames: Set<String>
    ) -> [TriggerCandidate] {
        let input = phrase.trimmingCharacters(in: .whitespaces).lowercased()
        guard input.count >= 2 else { return [] }

        // 输入经任务别名扩展（搜「做个PPT」也命中 slide/deck）
        var probes = [input]
        for (key, values) in Rules.recommendAliases where input.contains(key.lowercased()) {
            probes.append(contentsOf: values.map { $0.lowercased() })
        }

        var candidates: [TriggerCandidate] = []
        for skill in skills {
            let skillSignals = signals(of: skill)
            var matched: [(String, Int)] = []  // (词, 贡献分)
            var buried: [String] = []

            for (signal, position) in skillSignals {
                let lower = signal.lowercased()
                // 双向包含：输入含信号词（做个PPT ⊃ ppt），或信号短语含整个输入
                let hit = probes.contains { probe in
                    probe.contains(lower) || (lower.count >= 4 && lower.contains(input))
                }
                guard hit else { continue }
                // 长词贡献大；埋在 250 字符之外的贡献减半并标记
                var weight = max(2, signal.count)
                if let position, position > visibleWindow {
                    weight = max(1, weight / 2)
                    buried.append(signal)
                }
                matched.append((signal, weight))
            }
            guard !matched.isEmpty else { continue }

            let usageCount = usage[skill.directory]?.total ?? 0
            var score = matched.reduce(0) { $0 + $1.1 }
            // 被预算丢弃 = 模型看不到描述，只剩名字硬撑；分数重挫
            if atRiskNames.contains(skill.name) { score = max(1, score / 3) }
            if skill.disabled { score = 0 }

            candidates.append(TriggerCandidate(
                skill: skill,
                score: score,
                matched: matched.sorted { $0.1 > $1.1 }.map(\.0),
                buried: buried,
                atRisk: atRiskNames.contains(skill.name),
                disabled: skill.disabled,
                usageCount: usageCount
            ))
        }

        return Array(
            candidates.sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.usageCount != $1.usageCount { return $0.usageCount > $1.usageCount }
                return $0.skill.name.lowercased() < $1.skill.name.lowercased()
            }
            .prefix(8)
        )
    }
}

// MARK: - 体检扩展：触发词埋深检查（250 字符口径）

struct BuriedTriggerEntry: Identifiable {
    var skill: Skill
    /// 首次出现在 250 字符之外的「」触发短语
    var phrases: [String]
    var id: String { skill.name }
}

extension ContextDoctor {
    /// 「」显式触发词首次出现在前 250 字符之外 → 对 listing 里的模型不可见
    static func buriedTriggers(skills: [Skill]) -> [BuriedTriggerEntry] {
        let regex = TriggerLab.quotedPhrase
        var entries: [BuriedTriggerEntry] = []
        for skill in skills where !skill.disabled {
            let description = skill.description
            guard description.count > TriggerLab.visibleWindow else { continue }
            let range = NSRange(description.startIndex..., in: description)
            var buried: [String] = []
            var anyVisible = false
            var seen = Set<String>()
            for match in regex.matches(in: description, range: range) {
                guard let swiftRange = Range(match.range(at: 1), in: description) else { continue }
                let phrase = String(description[swiftRange])
                guard seen.insert(phrase).inserted else { continue }
                let position = description.distance(from: description.startIndex, to: swiftRange.lowerBound)
                if position > TriggerLab.visibleWindow {
                    buried.append(phrase)
                } else {
                    anyVisible = true
                }
            }
            // 只有当「有触发词但全埋在后面」或「埋掉的占多数」才算问题
            if !buried.isEmpty && (!anyVisible || buried.count >= 3) {
                entries.append(BuriedTriggerEntry(skill: skill, phrases: buried))
            }
        }
        return entries.sorted { $0.phrases.count > $1.phrases.count }
    }
}
