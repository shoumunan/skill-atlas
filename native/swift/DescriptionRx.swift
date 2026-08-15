import Foundation

// MARK: - 描述医生「开药」（三期 G2）
//
// 体检只诊断（埋深/超长/丢弃风险），这里负责治疗，且只开保守药：
// 改写 = 重排句子——把含「」触发词的句子前置进 250 字符可见窗，
// 一个字不增删，可审计、零编造。疗效用试触发 before/after 名次验证。
// 机器改不动的（无触发词可前置、单句长文）诚实说改不动，
// 逃生门是「复制 Claude 改写指令」让模型按 Trigger Triad 重写后人工贴回。

struct DescriptionPrescription: Identifiable {
    var skill: Skill
    var original: String
    var rewritten: String
    /// 动了什么（人话逐条，含改不动的原因）
    var moves: [String]
    /// 改写前后仍埋在 250 字符之外的「」触发词
    var beforeBuried: [String]
    var afterBuried: [String]
    /// 描述超过 1536 单条截断线（重排解决不了，要人删）
    var overCap: Bool
    /// 机器无从下手（rewritten == original）
    var noop: Bool { rewritten == original }
    var id: String { skill.name }
}

enum DescriptionRx {
    /// 生成处方。纯函数：不读盘不写盘。
    static func prescribe(skill: Skill) -> DescriptionPrescription {
        let original = skill.description
        var moves: [String] = []
        var rewritten = original

        let sentences = splitSentences(original)
        if sentences.count > 1 {
            let head = sentences[0]
            let rest = Array(sentences.dropFirst())
            let scored = rest.enumerated().map { (index: $0.offset, text: $0.element, hits: triggerCount($0.element)) }
            let promoted = scored.filter { $0.hits > 0 && isBuried($0.text, in: original) }
                .sorted { $0.hits != $1.hits ? $0.hits > $1.hits : $0.index < $1.index }
            if !promoted.isEmpty {
                let promotedIndexes = Set(promoted.map(\.index))
                let remaining = scored.filter { !promotedIndexes.contains($0.index) }
                let candidate = ([head] + promoted.map(\.text) + remaining.map(\.text)).joined()
                if candidate != original {
                    rewritten = candidate
                    moves.append(LF("前置了 %d 个含「」触发词的句子（能力句仍居首，其余保持原序，未增删一字）", promoted.count))
                }
            }
        }

        let beforeBuried = buriedPhrases(in: original)
        let afterBuried = buriedPhrases(in: rewritten)
        if rewritten != original {
            moves.append(LF("前 250 字符可见触发词：%d 个 → %d 个", visibleCount(in: original), visibleCount(in: rewritten)))
        } else {
            if sentences.count <= 1 {
                moves.append(L("整段只有一句，机器不拆句改写。用下方指令让 Claude 按 Trigger Triad 重写"))
            } else if beforeBuried.isEmpty {
                moves.append(L("没有埋深的「」触发词可前置。问题不在语序，考虑缩短或补触发词"))
            } else {
                moves.append(L("触发词与能力句纠缠在同批句子里，重排无收益。用下方指令让 Claude 重写"))
            }
        }
        let overCap = original.count > ContextDoctor.perEntryCap
        if overCap {
            moves.append(LF("描述 %d 字符超过 1,536 单条截断线。重排救不了超长，需要人工删减尾部", original.count))
        }

        return DescriptionPrescription(
            skill: skill, original: original, rewritten: rewritten, moves: moves,
            beforeBuried: beforeBuried, afterBuried: afterBuried, overCap: overCap
        )
    }

    /// 给 Claude 的改写指令（逃生门）：Trigger Triad + 原文，用户贴进任意会话
    static func rewritePrompt(skill: Skill) -> String {
        """
        请按「Trigger Triad」重写这个 skill 的 description（中文）：
        1) 首句 = 能力句（动词+对象，说清它做什么）；
        2) 紧跟显式触发短语，用「」括起（用户会怎么说就写什么，全部落在前 250 字符内）；
        3) 结尾可加一句负向排除（什么情况不要触发）。
        硬约束：总长 ≤ 400 字符；不编造原文没有的能力；保留原文的边界声明。
        技能名：\(skill.name)
        原 description：
        \(skill.description)
        只输出重写后的 description 文本，不要解释。
        """
    }

    /// 写回 SKILL.md frontmatter 的 description 键。
    /// 只动这一个键的值；多行块格式会被写成单行（YAML 语义等价，move 里已提示）。
    static func writeBack(skill: Skill, newDescription: String) throws {
        guard skill.origin != .ccSwitch else {
            throw AtlasError(L("CC Switch 技能只读。先迁移进本库，再开药写回。"))
        }
        let file = URL(fileURLWithPath: skill.skillFile)
        guard var text = try? String(contentsOf: file, encoding: .utf8), text.hasPrefix("---") else {
            throw AtlasError(LF("读不到「%@」的 frontmatter，未写回。", skill.name))
        }
        let searchStart = text.index(text.startIndex, offsetBy: 3)
        // 结束线必须是整行 "---"（后随换行或文件尾）——值内行首出现 "---" 时不误判边界
        guard let endRange = text.range(
            of: #"\n---[ \t]*(\n|$)"#, options: .regularExpression, range: searchStart..<text.endIndex
        ) else {
            throw AtlasError(LF("「%@」的 frontmatter 没有结束线，未写回。", skill.name))
        }
        let fmRange = searchStart..<endRange.lowerBound
        let frontmatter = String(text[fmRange])
        guard let regex = try? NSRegularExpression(pattern: "(?ms)^description:\\s*.*?(?=\\n[a-zA-Z_-]+:|\\z)"),
              let match = regex.firstMatch(in: frontmatter, range: NSRange(frontmatter.startIndex..., in: frontmatter)),
              let matchRange = Range(match.range, in: frontmatter) else {
            throw AtlasError(LF("「%@」的 frontmatter 里找不到 description 键，未写回。", skill.name))
        }
        // 值内换行一律折叠为空格——description 是单行语义，含 \n 直接写出会产出
        // 非法 frontmatter（第二行无缩进被 YAML 当新键/语法错），技能触发直接失效
        let singleLine = newDescription
            .replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = frontmatter
        updated.replaceSubrange(matchRange, with: "description: \(yamlSafe(singleLine))")
        text.replaceSubrange(fmRange, with: updated)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// YAML 普通标量装不下的值加双引号（ASCII 冒号+空格、# 注释、特殊首字符）
    static func yamlSafe(_ value: String) -> String {
        let specialHead: Set<Character> = ["\"", "'", ">", "|", "&", "*", "!", "?", "{", "}", "[", "]", "@", "`", "%", "-"]
        let needsQuote = value.contains(": ") || value.contains(" #")
            || value.first.map { specialHead.contains($0) } == true
        guard needsQuote else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // MARK: 内部口径（与 TriggerLab/ContextDoctor 对齐）

    /// 按中文/英文句读切句，分隔符保留在句尾，joined() 可无损还原
    static func splitSentences(_ text: String) -> [String] {
        let delimiters: Set<Character> = ["。", "！", "？", "；", "!", "?", ";"]
        var result: [String] = []
        var current = ""
        for char in text {
            current.append(char)
            if delimiters.contains(char) {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func triggerCount(_ sentence: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "「([^」]{1,24})」") else { return 0 }
        return regex.numberOfMatches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence))
    }

    /// 句子里的触发词在全文中的首次出现是否埋在可见窗之外
    private static func isBuried(_ sentence: String, in full: String) -> Bool {
        guard let range = full.range(of: sentence) else { return false }
        let position = full.distance(from: full.startIndex, to: range.lowerBound)
        return position + sentenceTriggerOffset(sentence) > TriggerLab.visibleWindow
    }

    /// 句内第一个「」的偏移（句子起点可见但触发词在句尾仍算埋）
    private static func sentenceTriggerOffset(_ sentence: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "「"),
              let match = regex.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
              let range = Range(match.range, in: sentence) else { return 0 }
        return sentence.distance(from: sentence.startIndex, to: range.lowerBound)
    }

    static func buriedPhrases(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "「([^」]{1,24})」") else { return [] }
        var buried: [String] = []
        var seen = Set<String>()
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range(at: 1), in: text) else { continue }
            let phrase = String(text[swiftRange])
            guard seen.insert(phrase).inserted else { continue }
            let position = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
            if position > TriggerLab.visibleWindow { buried.append(phrase) }
        }
        return buried
    }

    static func visibleCount(in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "「([^」]{1,24})」") else { return 0 }
        var count = 0
        var seen = Set<String>()
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range(at: 1), in: text) else { continue }
            let phrase = String(text[swiftRange])
            guard seen.insert(phrase).inserted else { continue }
            let position = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
            if position <= TriggerLab.visibleWindow { count += 1 }
        }
        return count
    }
}
