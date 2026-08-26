import Foundation

// MARK: - Hook 实时遥测（三期 G5）
//
// 现状：使用统计靠 grep 会话转录（Usage.swift），有口径盲区且非实时。
// 本模块把 Claude Code 的 PostToolUse hook 接进来：Skill 工具每次被调用，
// hook 脚本往 ~/.skill-atlas/usage-events.jsonl 追加一行事件，App 读它做精确计量。
//
// 安全边界（动的是用户的 ~/.claude/settings.json，全局配置）：
// - 写入前原文备份到 ~/.skill-atlas/settings-backups/，保留最近 10 份
// - 只增删我们自己的 hook 条目（按脚本绝对路径识别），其余键原样保留
// - settings.json 不是合法 JSON 时拒绝写入，绝不猜
// - hook 脚本永远 exit 0——遥测绝不阻塞用户的工具调用

package enum HookTelemetry {
    package static var eventsURL: URL { AtlasPaths.root.appendingPathComponent("usage-events.jsonl") }
    package static var scriptURL: URL { AtlasPaths.root.appendingPathComponent("hooks/log-skill-use.sh") }
    package static var settingsURL: URL { AtlasPaths.home.appendingPathComponent(".claude/settings.json") }
    package static var backupsDir: URL { AtlasPaths.root.appendingPathComponent("settings-backups") }

    // MARK: 状态

    /// 结构化检查（不做文本 contains——JSONSerialization 写盘会把 / 转义成 \/）
    package static func installed() -> Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooks = settings["hooks"] as? [String: Any],
              let post = hooks["PostToolUse"] as? [[String: Any]] else { return false }
        return containsOurs(post)
    }

    // MARK: 安装 / 卸载

    /// 脚本内容零内插：事件路径由脚本运行时从自身位置（$0）推导——
    /// hooks/log-skill-use.sh 的上一级就是 ~/.skill-atlas，杜绝路径含引号时的
    /// shell/python 注入面，也不依赖 HOME 解析。
    /// 注意：hook 的事件 JSON 走脚本 stdin，python 程序体绝不能也走 stdin
    ///（heredoc 会把 stdin 整个吃掉），所以 bash 先 $(cat) 接住再管道给 python3 -c。
    private static func scriptBody() -> String {
        """
        #!/bin/bash
        # Skill Atlas Hook 遥测：PostToolUse(Skill) → 追加事件行
        # 由 Skill Atlas 生成与管理；永远 exit 0，绝不阻塞工具调用
        ATLAS_ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 0
        export SKILL_ATLAS_EVENTS="$ATLAS_ROOT/usage-events.jsonl"
        INPUT=$(cat)
        printf '%s' "$INPUT" | /usr/bin/python3 -c '
        import json, os, sys, time
        try:
            data = json.load(sys.stdin)
            tool_input = data.get("tool_input") or {}
            name = tool_input.get("skill") or tool_input.get("name") or ""
            path = os.environ.get("SKILL_ATLAS_EVENTS", "")
            if name and path:
                line = json.dumps({"skill": name, "ts": time.time(), "session": data.get("session_id", "")}, ensure_ascii=False)
                with open(path, "a", encoding="utf-8") as f:
                    f.write(line + "\\n")
        except Exception:
            pass
        ' 2>/dev/null
        exit 0
        """
    }

    package static func install() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try scriptBody().write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL) {
            guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw AtlasError(L("~/.claude/settings.json 不是合法 JSON。为避免弄坏你的配置，本次不写入。修好后再试。"))
            }
            settings = parsed
            try backup(data)
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var post = hooks["PostToolUse"] as? [[String: Any]] ?? []
        if !containsOurs(post) {
            post.append([
                "matcher": "Skill",
                "hooks": [["type": "command", "command": scriptURL.path]],
            ])
        }
        hooks["PostToolUse"] = post
        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    package static func uninstall() throws {
        guard let data = try? Data(contentsOf: settingsURL) else { return }
        guard var settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AtlasError(L("~/.claude/settings.json 不是合法 JSON。为避免弄坏你的配置，本次不写入。修好后再试。"))
        }
        try backup(data)
        if var hooks = settings["hooks"] as? [String: Any],
           var post = hooks["PostToolUse"] as? [[String: Any]] {
            post = post.compactMap { entry in
                var inner = (entry["hooks"] as? [[String: Any]]) ?? []
                inner.removeAll { ($0["command"] as? String) == scriptURL.path }
                guard !inner.isEmpty else { return nil }
                var copy = entry
                copy["hooks"] = inner
                return copy
            }
            if post.isEmpty { hooks.removeValue(forKey: "PostToolUse") } else { hooks["PostToolUse"] = post }
            if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
            try writeSettings(settings)
        }
        try? FileManager.default.removeItem(at: scriptURL)
    }

    private static func containsOurs(_ post: [[String: Any]]) -> Bool {
        post.contains { entry in
            ((entry["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String) == scriptURL.path }
        }
    }

    /// 按来源分域备份。label 区分「全局 settings.json」与各项目的 settings.local.json：
    /// 混在一个目录里既分不清是谁的，10 份上限也会让频繁写盘的一方把另一方的唯一
    /// 逃生索挤掉（Profile 每切一次就写一份，能把改 hooks 前的全局备份冲光）。
    /// 同秒二次写盘补序号——否则 write(to:) 静默覆盖，丢的正是先写那份。
    package static func backup(_ data: Data, label: String = "user") throws {
        let fileManager = FileManager.default
        let dir = backupsDir.appendingPathComponent(label.isEmpty ? "user" : label)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        var name = "settings-\(stamp).json"
        var sequence = 2
        while fileManager.fileExists(atPath: dir.appendingPathComponent(name).path) {
            name = "settings-\(stamp)-\(sequence).json"
            sequence += 1
        }
        try data.write(to: dir.appendingPathComponent(name))
        // 每个来源各留最近 10 份
        if let entries = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            let ranked = entries.sorted { $0.lastPathComponent > $1.lastPathComponent }
            for extra in ranked.dropFirst(10) { try? fileManager.removeItem(at: extra) }
        }
    }

    /// 备份目录的可读标签：全局配置一律 user；项目配置取「项目目录名」而不是
    /// 它下面那个 .claude——后者会在备份区里生成一堆同名的隐藏目录，翻不出是谁的。
    package static func label(for url: URL) -> String {
        let settingsDir = url.deletingLastPathComponent()          // …/.claude
        if settingsDir.standardizedFileURL.path
            == AtlasPaths.home.appendingPathComponent(".claude").standardizedFileURL.path {
            return "user"
        }
        let projectDir = settingsDir.deletingLastPathComponent()   // 项目根
        let name = projectDir.lastPathComponent
        let slug = name.trimmingCharacters(in: CharacterSet(charactersIn: "._~/ "))
        return slug.isEmpty ? "project" : String(slug.prefix(60))
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let out = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try out.write(to: settingsURL, options: .atomic)
    }

    // MARK: 事件读取

    package struct HookStats: Equatable {
        package var events = 0
        /// 会话数（与 grep 口径一致：同会话同技能只计一次）
        package var sessions = 0
        package var last: Date?
    }

    /// 事件里存技能名（Skill 工具入参），聚合时映射回目录名与 usage 对齐
    package static func stats(nameToDirectory: [String: String]) -> [String: HookStats] {
        guard let text = try? String(contentsOf: eventsURL, encoding: .utf8), !text.isEmpty else { return [:] }
        var events: [String: Int] = [:]
        var sessions: [String: Set<String>] = [:]
        var last: [String: Double] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let name = object["skill"] as? String, !name.isEmpty else { continue }
            let directory = nameToDirectory[name] ?? name
            events[directory, default: 0] += 1
            let session = (object["session"] as? String) ?? ""
            sessions[directory, default: []].insert(session.isEmpty ? String(line.hashValue) : session)
            if let ts = object["ts"] as? Double {
                last[directory] = max(last[directory] ?? 0, ts)
            }
        }
        var result: [String: HookStats] = [:]
        for (directory, count) in events {
            result[directory] = HookStats(
                events: count,
                sessions: sessions[directory]?.count ?? 0,
                last: last[directory].map { Date(timeIntervalSince1970: $0) }
            )
        }
        return result
    }

    package static var totalEvents: Int {
        guard let text = try? String(contentsOf: eventsURL, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").count
    }
}
