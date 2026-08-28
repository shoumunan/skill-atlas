import Foundation

// MARK: - miss 检测（ADR-6）
//
// 近 7 天会话：TriggerLab.simulate(firstPrompt) 第一名得分 ≥θ、已挂载、
// 可被模型触发、且不在该会话已用集合 → 计一次 miss。同一技能 ≥2 次才进周报。
// user-invocable-only 不进 miss，改成「可以用 /名字 调用」。disabled 排除。

package enum MissRules {
    package static let minScore = 4
    package static let minOccurrences = 2
    package static let windowDays = 7
    package static let digestCap = 3
}

package struct MissHit: Equatable, Identifiable {
    package var directory: String
    package var name: String
    package var occurrences: Int
    package var score: Int
    package var samplePrompt: String
    package var userInvocableOnly: Bool
    package var id: String { directory }
}

package enum MissDetect {
    package static func report(skills: [Skill]) -> [MissHit] {
        let mounted = Dictionary(uniqueKeysWithValues: skills.map { ($0.directory, $0) })
        let overrides = currentOverrides()
        let sessions = UsageIndexer.sessionSnapshots(windowDays: MissRules.windowDays)
        var counts: [String: (n: Int, score: Int, prompt: String)] = [:]
        var invocable: [String: (n: Int, prompt: String)] = [:]

        for session in sessions {
            let prompt = session.firstPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard prompt.count >= 2 else { continue }
            let ranked = TriggerLab.simulate(
                phrase: prompt, skills: skills, usage: [:], atRiskNames: []
            )
            guard let top = ranked.first, top.score >= MissRules.minScore else { continue }
            let skill = top.skill
            guard !skill.disabled else { continue }
            guard skill.mount(.claude).status == .ok || skill.platforms.contains("Claude") else { continue }
            if session.used.contains(skill.directory) { continue }
            if overrides[skill.name] == ProfileExclusion.off.rawValue { continue }
            if overrides[skill.name] == ProfileExclusion.userInvocableOnly.rawValue {
                var rec = invocable[skill.directory] ?? (0, prompt)
                rec.n += 1
                invocable[skill.directory] = rec
                continue
            }
            var rec = counts[skill.directory] ?? (0, top.score, prompt)
            rec.n += 1
            rec.score = max(rec.score, top.score)
            counts[skill.directory] = rec
        }

        var hits: [MissHit] = []
        for (dir, rec) in counts where rec.n >= MissRules.minOccurrences {
            let name = mounted[dir]?.name ?? dir
            hits.append(MissHit(
                directory: dir, name: name, occurrences: rec.n, score: rec.score,
                samplePrompt: rec.prompt, userInvocableOnly: false
            ))
        }
        for (dir, rec) in invocable where rec.n >= MissRules.minOccurrences {
            let name = mounted[dir]?.name ?? dir
            hits.append(MissHit(
                directory: dir, name: name, occurrences: rec.n, score: 0,
                samplePrompt: rec.prompt, userInvocableOnly: true
            ))
        }
        return Array(hits.sorted { $0.occurrences > $1.occurrences }.prefix(MissRules.digestCap))
    }

    private static func currentOverrides() -> [String: String] {
        let settings = (try? ProfileWriter.readSettings(at: ProfileWriter.userSettingsURL)) ?? [:]
        let raw = settings["skillOverrides"] as? [String: Any] ?? [:]
        var result: [String: String] = [:]
        for (key, value) in raw {
            if let text = value as? String { result[key] = text }
        }
        return result
    }
}

package enum RxFollowup {
    package struct Card: Identifiable {
        package var directory: String
        package var writtenAt: Int
        package var ageDays: Int
        package var id: String { directory }
    }

    /// oplog 的解析结果按（修改时间, 大小）缓存：oplog 按 2MB 轮转，
    /// 逐行 JSON 解析放在渲染路径上会随日志增长逐渐拖垮界面。
    private nonisolated(unsafe) static var cache: (key: String, cards: [Card])?

    /// oplog 里 rx-writeback 满 14 天的条目，供收件箱回访卡。
    package static func due(now: Date = Date()) -> [Card] {
        let attributes = try? FileManager.default.attributesOfItem(atPath: Oplog.url.path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes?[.size] as? Int) ?? 0
        // 天数会随时间变化，缓存键带上当天日期，跨天自动重算
        let day = Int(now.timeIntervalSince1970) / 86400
        let key = "\(modified)|\(size)|\(day)"
        if let cache, cache.key == key { return cache.cards }
        let cards = compute(now: now)
        cache = (key, cards)
        return cards
    }

    private static func compute(now: Date) -> [Card] {
        guard let text = try? String(contentsOf: Oplog.url, encoding: .utf8) else { return [] }
        let cutoff = Int(now.timeIntervalSince1970) - 14 * 24 * 3600
        var latest: [String: Int] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (object["op"] as? String) == "rx-writeback",
                  (object["ok"] as? Bool) == true,
                  let target = object["target"] as? String,
                  let ts = object["ts"] as? Int else { continue }
            latest[target] = ts
        }
        return latest.compactMap { dir, ts in
            guard ts <= cutoff else { return nil }
            return Card(directory: dir, writtenAt: ts, ageDays: (Int(now.timeIntervalSince1970) - ts) / 86400)
        }.sorted { $0.writtenAt < $1.writtenAt }
    }
}
