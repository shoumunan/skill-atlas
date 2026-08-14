import Foundation

// MARK: - 上下文预算体检（DESIGN.md §10.5）
//
// 依据（2026 实测文章，帮助气泡引用）：
// - Claude Code 启动时把「所有技能的名称 + 描述」注入上下文，单条 description 截断于 1,536 字符
// - 整个清单的预算 ≈ 上下文窗口的 1%（200k 窗口 ≈ 2,000 token）
// - 超额后按「调用频率最低优先」静默丢弃描述——技能还在，但模型看不到它能干什么
// 本应用同时掌握描述长度与真实使用频率，可以精确模拟丢弃顺序。全部数字标注「估算」。

struct ListingEntry: Identifiable {
    var skill: Skill
    /// 上架的描述字符数（截断于 1536）
    var chars: Int
    /// 估算 token：CJK×0.7 + 其他/4 + 15 条目开销
    var tokens: Int
    /// 使用会话数（丢弃顺序的排序键）
    var sessions: Int
    /// 描述原文超过单条截断线
    var overCap: Bool

    var id: String { skill.name }
}

struct VerboseEntry: Identifiable {
    var skill: Skill
    var chars: Int
    var sentences: Int
    var suggestion: String
    var id: String { skill.name }
}

struct DoctorReport {
    var entries: [ListingEntry] = []
    var budgetTokens = 0
    var totalTokens = 0
    var atRisk: [ListingEntry] = []
    var overlong: [ListingEntry] = []
    var verbose: [VerboseEntry] = []
    /// 「」触发词全部/大半埋在前 250 字符之外的技能（TriggerLab 口径）
    var buried: [BuriedTriggerEntry] = []
    var reclaimableTokens = 0

    var overBudget: Bool { totalTokens > budgetTokens }
    var usageFraction: Double {
        budgetTokens > 0 ? Double(totalTokens) / Double(budgetTokens) : 0
    }
}

enum ContextDoctor {
    static let perEntryCap = 1536
    static let listingSoftCap = 40
    static let verboseCharLimit = 200

    /// token 估算：CJK 字符 ×0.7，其余 ÷4，再加每条 ~15 token 的名称与格式开销
    static func tokenEstimate(chars text: String) -> Int {
        var cjk = 0
        var other = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3000...0x303F, 0xFF00...0xFFEF:
                cjk += 1
            default:
                other += 1
            }
        }
        return Int((Double(cjk) * 0.7 + Double(other) / 4).rounded(.up))
    }

    static func sentenceCount(_ text: String) -> Int {
        text.components(separatedBy: CharacterSet(charactersIn: "。！？.!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 }
            .count
    }

    static func shortenSuggestion(_ text: String) -> String {
        let first = text.split(whereSeparator: { "。！？.!?\n".contains($0) }).first.map(String.init) ?? text
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(80)) + "…"
    }

    static func report(
        skills: [Skill],
        usage: [String: SkillUsage],
        staleDirectories: Set<String>,
        contextWindowTokens: Int
    ) -> DoctorReport {
        var report = DoctorReport()
        report.budgetTokens = contextWindowTokens / 100  // 1%

        for skill in skills where !skill.disabled {
            let raw = skill.description
            let capped = String(raw.prefix(perEntryCap))
            let entry = ListingEntry(
                skill: skill,
                chars: capped.count,
                tokens: tokenEstimate(chars: capped) + 15,
                sessions: usage[skill.directory]?.total ?? 0,
                overCap: raw.count > perEntryCap
            )
            report.entries.append(entry)
        }

        report.totalTokens = report.entries.reduce(0) { $0 + $1.tokens }
        report.overlong = report.entries.filter(\.overCap)
            .sorted { $0.chars > $1.chars }

        // 丢弃模拟：用得多的先保住预算，累计超出预算的（= 最少用的）被丢弃
        let keepersFirst = report.entries.sorted {
            $0.sessions != $1.sessions
                ? $0.sessions > $1.sessions
                : $0.skill.name.lowercased() < $1.skill.name.lowercased()
        }
        var cumulative = 0
        var dropped: [ListingEntry] = []
        for entry in keepersFirst {
            cumulative += entry.tokens
            if cumulative > report.budgetTokens {
                dropped.append(entry)
            }
        }
        // 展示时最先被丢的（用得最少的）排最前
        report.atRisk = dropped.sorted {
            $0.sessions != $1.sessions
                ? $0.sessions < $1.sessions
                : $0.skill.name.lowercased() < $1.skill.name.lowercased()
        }

        report.reclaimableTokens = report.entries
            .filter { staleDirectories.contains($0.skill.directory) }
            .reduce(0) { $0 + $1.tokens }

        report.verbose = skills.filter { skill in
            guard !skill.disabled else { return false }
            let text = skill.description
            return text.count > verboseCharLimit || sentenceCount(text) > 1
        }
        .map { skill in
            VerboseEntry(
                skill: skill,
                chars: skill.description.count,
                sentences: sentenceCount(skill.description),
                suggestion: shortenSuggestion(skill.description)
            )
        }
        .sorted { $0.chars > $1.chars }

        report.buried = buriedTriggers(skills: skills)

        return report
    }
}
