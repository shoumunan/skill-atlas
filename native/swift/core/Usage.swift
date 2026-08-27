import Foundation

// MARK: - 使用频率统计（只读扫描会话日志，增量索引）
//
// 数据源：~/.claude/projects/**/*.jsonl 与 ~/.codex/sessions/**/*.jsonl（合计可超 1 GB）。
// 判定规则（2026-08-13 实证，见 DESIGN.md）：
// - 一次「使用」的证据 = 会话日志行里出现 `skills/<已知目录名>` 的路径引用；
//   同一会话内同一技能只计 1 次（按会话计数）。
// - Claude 的子代理转录在 `projects/<项目>/<会话UUID>/subagents/**.jsonl`，
//   与主转录 `<会话UUID>.jsonl` 同属一个会话——聚合时按「项目/会话UUID」分组，
//   否则一次跑多个子代理的技能会被虚增几倍。
// - Claude：任意行匹配即算（会话里只出现真正用到的技能）。
// - Codex：**只认 `"type":"custom_tool_call"` / `"type":"function_call"` 行**——
//   Codex 会把全量技能目录内嵌进 developer 指令和 world_state，
//   不过滤会把所有技能误判为每个会话都用过。
// - 时间取该文件内最后一次引用行的 "timestamp"（ISO8601），取不到用文件 mtime。
//
// 性能：不做逐行 JSON 解码。mmap 文件后字节级搜索 "skills/"，
// 只对命中行做类型核对与时间戳提取；缓存按 (路径, mtime, size) 命中直接复用。

package struct SkillUsage: Equatable {
    package var claudeSessions = 0
    package var codexSessions = 0
    package var lastUsed: Date?
    package var total: Int { claudeSessions + codexSessions }

    package init(claudeSessions: Int = 0, codexSessions: Int = 0, lastUsed: Date? = nil) {
        self.claudeSessions = claudeSessions
        self.codexSessions = codexSessions
        self.lastUsed = lastUsed
    }
}

package enum UsageIndexer {
    // MARK: 缓存结构（~/.skill-atlas/usage-index.json）

    package struct FileEntry: Codable {
        var mtime: Double
        var size: Int
        /// 目录名 → 该会话内最后引用的 unix 时间戳
        var skills: [String: Double]
        /// 已消化到的字节偏移（对齐到完整行末）。jsonl 追加时只读尾巴。
        var bytesRead: Int = 0
        /// 首轮用户消息前 500 字符（v4）。Optional：老缓存没有。
        var firstPrompt: String?
    }

    package struct Cache: Codable {
        var version: Int = 4
        /// 平台 → (会话文件路径 → 解析结果)
        var files: [String: [String: FileEntry]] = [:]
    }

    package static let currentVersion = 4

    package struct SessionSnapshot {
        package var key: String
        package var platform: String
        package var lastTs: Double
        package var firstPrompt: String
        package var used: Set<String>
    }

    package static var cacheURL: URL { AtlasPaths.usageIndexURL }

    /// 只读已落盘的索引，不扫会话目录。CLI 每次冷启动不能去啃 1 GB jsonl。
    package static func loadCached() -> [String: SkillUsage] {
        guard let cache = try? JSONDecoder().decode(Cache.self, from: Data(contentsOf: cacheURL)),
              cache.version == currentVersion else { return [:] }
        let roots: [(platform: String, url: URL)] = [
            ("claude", SkillScanner.home.appendingPathComponent(".claude/projects")),
            ("codex", SkillScanner.home.appendingPathComponent(".codex/sessions")),
        ]
        var usage: [String: SkillUsage] = [:]
        for (platform, entries) in cache.files {
            let root = roots.first { $0.platform == platform }?.url.path ?? ""
            var sessions: [String: [String: Double]] = [:]
            for (path, entry) in entries {
                let key = sessionKey(for: path, platform: platform, root: root)
                for (dir, timestamp) in entry.skills {
                    sessions[key, default: [:]][dir] = max(sessions[key]?[dir] ?? 0, timestamp)
                }
            }
            for skillTimes in sessions.values {
                for (dir, timestamp) in skillTimes {
                    var record = usage[dir] ?? SkillUsage()
                    if platform == "claude" { record.claudeSessions += 1 } else { record.codexSessions += 1 }
                    if timestamp > 0 {
                        let date = Date(timeIntervalSince1970: timestamp)
                        if record.lastUsed == nil || date > record.lastUsed! { record.lastUsed = date }
                    }
                    usage[dir] = record
                }
            }
        }
        return usage
    }

    package struct Result {
        package var usage: [String: SkillUsage]
        package var scannedFiles: Int
        package var reparsedFiles: Int
        package var duration: TimeInterval
    }

    /// 全量/增量索引。`progress` 以 0–1 回调（按文件数）。
    package static func index(knownDirs: Set<String>, progress: @escaping @Sendable (Double) -> Void) -> Result {
        let started = Date()
        let fileManager = FileManager.default
        var cache = (try? JSONDecoder().decode(Cache.self, from: Data(contentsOf: cacheURL))) ?? Cache()
        if cache.version != currentVersion { cache = Cache() }

        let roots: [(platform: String, url: URL)] = [
            ("claude", SkillScanner.home.appendingPathComponent(".claude/projects")),
            ("codex", SkillScanner.home.appendingPathComponent(".codex/sessions")),
        ]

        // 收集所有会话文件
        var jobs: [(platform: String, path: String, mtime: Double, size: Int)] = []
        for (platform, root) in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                jobs.append((
                    platform,
                    url.path,
                    values?.contentModificationDate?.timeIntervalSince1970 ?? 0,
                    values?.fileSize ?? 0
                ))
            }
        }

        var newCache = Cache()
        var reparsed = 0
        for (index, job) in jobs.enumerated() {
            if let hit = cache.files[job.platform]?[job.path],
               hit.mtime == job.mtime, hit.size == job.size {
                newCache.files[job.platform, default: [:]][job.path] = hit
            } else if let hit = cache.files[job.platform]?[job.path],
                      job.size > hit.size, hit.bytesRead > 0, hit.bytesRead <= hit.size {
                // jsonl 追加：只读上次完整行之后的尾巴，技能计数与旧结果合并
                let added = parseFile(
                    at: job.path,
                    platform: job.platform,
                    knownDirs: knownDirs,
                    fallbackTime: job.mtime,
                    startOffset: hit.bytesRead
                )
                var merged = hit.skills
                for (name, time) in added.skills {
                    merged[name] = max(merged[name] ?? 0, time)
                }
                newCache.files[job.platform, default: [:]][job.path] = FileEntry(
                    mtime: job.mtime,
                    size: job.size,
                    skills: merged,
                    bytesRead: added.bytesRead,
                    firstPrompt: hit.firstPrompt ?? added.firstPrompt
                )
                reparsed += 1
            } else {
                let parsed = parseFile(
                    at: job.path,
                    platform: job.platform,
                    knownDirs: knownDirs,
                    fallbackTime: job.mtime
                )
                newCache.files[job.platform, default: [:]][job.path] = FileEntry(
                    mtime: job.mtime, size: job.size, skills: parsed.skills,
                    bytesRead: parsed.bytesRead, firstPrompt: parsed.firstPrompt
                )
                reparsed += 1
            }
            if index % 32 == 0 || index == jobs.count - 1 {
                progress(Double(index + 1) / Double(max(1, jobs.count)))
            }
        }

        // 聚合：先把文件归并到会话（Claude 子代理文件归并进主会话），再按会话计数
        var usage: [String: SkillUsage] = [:]
        for (platform, entries) in newCache.files {
            let root = roots.first { $0.platform == platform }!.url.path
            var sessions: [String: [String: Double]] = [:]  // 会话键 → (技能 → 最后时间)
            for (path, entry) in entries {
                let key = sessionKey(for: path, platform: platform, root: root)
                for (dir, timestamp) in entry.skills {
                    sessions[key, default: [:]][dir] = max(sessions[key]?[dir] ?? 0, timestamp)
                }
            }
            for skillTimes in sessions.values {
                for (dir, timestamp) in skillTimes {
                    var record = usage[dir] ?? SkillUsage()
                    if platform == "claude" { record.claudeSessions += 1 } else { record.codexSessions += 1 }
                    if timestamp > 0 {
                        let date = Date(timeIntervalSince1970: timestamp)
                        if record.lastUsed == nil || date > record.lastUsed! { record.lastUsed = date }
                    }
                    usage[dir] = record
                }
            }
        }

        // 落盘（失败不致命，下次重扫）
        if let data = try? JSONEncoder().encode(newCache) {
            try? fileManager.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: cacheURL, options: .atomic)
        }

        return Result(
            usage: usage,
            scannedFiles: jobs.count,
            reparsedFiles: reparsed,
            duration: Date().timeIntervalSince(started)
        )
    }

    /// miss 检测用：按会话聚合 firstPrompt + 已用技能。只读缓存，不扫盘。
    package static func sessionSnapshots(windowDays: Int = 7) -> [SessionSnapshot] {
        guard let cache = try? JSONDecoder().decode(Cache.self, from: Data(contentsOf: cacheURL)),
              cache.version == currentVersion else { return [] }
        let cutoff = Date().addingTimeInterval(TimeInterval(-windowDays * 24 * 3600)).timeIntervalSince1970
        let roots: [(platform: String, url: URL)] = [
            ("claude", SkillScanner.home.appendingPathComponent(".claude/projects")),
            ("codex", SkillScanner.home.appendingPathComponent(".codex/sessions")),
        ]
        var grouped: [String: SessionSnapshot] = [:]
        for (platform, entries) in cache.files {
            let root = roots.first { $0.platform == platform }?.url.path ?? ""
            for (path, entry) in entries {
                let key = "\(platform)|\(sessionKey(for: path, platform: platform, root: root))"
                var snap = grouped[key] ?? SessionSnapshot(
                    key: key, platform: platform, lastTs: 0, firstPrompt: "", used: []
                )
                snap.used.formUnion(entry.skills.keys)
                if let prompt = entry.firstPrompt, snap.firstPrompt.isEmpty, !prompt.isEmpty {
                    snap.firstPrompt = prompt
                }
                let newest = entry.skills.values.max() ?? 0
                if newest > snap.lastTs { snap.lastTs = newest }
                grouped[key] = snap
            }
        }
        return grouped.values.filter { $0.lastTs >= cutoff || $0.lastTs == 0 }
    }

    /// 会话键：Claude 取「项目/会话UUID」（主转录与其 subagents 目录同键）；Codex 每文件一会话
    private static func sessionKey(for path: String, platform: String, root: String) -> String {
        guard platform == "claude", path.hasPrefix(root) else { return path }
        let relative = String(path.dropFirst(root.count + 1))
        let parts = relative.split(separator: "/", maxSplits: 2)
        guard parts.count >= 2 else { return path }
        var session = String(parts[1])
        if session.hasSuffix(".jsonl") { session = String(session.dropLast(6)) }
        return "\(parts[0])/\(session)"
    }

    // MARK: 单文件解析（字节级，不做逐行 JSON 解码）

    private static let needle = Data("skills/".utf8)
    private static let newline = UInt8(ascii: "\n")
    private static let codexCallMarkers = [
        Data("\"type\":\"custom_tool_call\"".utf8),
        Data("\"type\":\"function_call\"".utf8),
    ]
    private static let timestampKey = Data("\"timestamp\":\"".utf8)

    private static let isoWithMillis: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let isoPlain = ISO8601DateFormatter()

    /// 返回：目录名 → 该文件内最后引用的 unix 时间戳（0 = 未知，调用方回退 mtime）
    private static func parseFile(
        at path: String,
        platform: String,
        knownDirs: Set<String>,
        fallbackTime: Double,
        startOffset: Int = 0
    ) -> (skills: [String: Double], bytesRead: Int, firstPrompt: String?) {
        let url = URL(fileURLWithPath: path)
        let data: Data
        let baseOffset: Int
        if startOffset > 0 {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return ([:], startOffset, nil) }
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: UInt64(startOffset))
                let tail = try handle.readToEnd() ?? Data()
                guard !tail.isEmpty else { return ([:], startOffset, nil) }
                data = tail
                baseOffset = startOffset
            } catch {
                return ([:], startOffset, nil)
            }
        } else {
            guard let mapped = try? Data(contentsOf: url, options: .mappedIfSafe),
                  !mapped.isEmpty else { return ([:], 0, nil) }
            data = mapped
            baseOffset = 0
        }
        let firstPrompt = startOffset == 0 ? extractFirstPrompt(from: data) : nil

        var result: [String: Double] = [:]
        var searchStart = data.startIndex
        var lineRange: Range<Data.Index>?  // 当前已定位的行（避免同行多命中重复扫描）
        var lineAccepted = false
        var lineTime: Double = 0

        while let match = data.range(of: needle, in: searchStart..<data.endIndex) {
            searchStart = match.upperBound

            if lineRange == nil || !(lineRange!.contains(match.lowerBound)) {
                // 定位新行边界；没有换行的尾巴不算一行，留给下次续读
                guard let lineEnd = data[match.upperBound...].firstIndex(of: newline) else { break }
                let lineStart = data[..<match.lowerBound].lastIndex(of: newline).map { data.index(after: $0) }
                    ?? data.startIndex
                lineRange = lineStart..<lineEnd

                // Codex：只认工具调用行（目录清单/世界状态行全部排除）
                if platform == "codex" {
                    lineAccepted = codexCallMarkers.contains {
                        data.range(of: $0, in: lineStart..<lineEnd) != nil
                    }
                } else {
                    lineAccepted = true
                }
                lineTime = lineAccepted ? extractTimestamp(data, in: lineStart..<lineEnd) : 0
            }
            guard lineAccepted else { continue }

            // 提取目录名 [A-Za-z0-9._-]+ 并核对已知全集
            var cursor = match.upperBound
            var nameBytes: [UInt8] = []
            while cursor < data.endIndex, nameBytes.count < 64 {
                let byte = data[cursor]
                let ok = (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A)
                    || (byte >= 0x30 && byte <= 0x39) || byte == 0x2D || byte == 0x5F || byte == 0x2E
                guard ok else { break }
                nameBytes.append(byte)
                cursor = data.index(after: cursor)
            }
            guard !nameBytes.isEmpty, nameBytes[0] != UInt8(ascii: ".") else { continue }
            guard let name = String(bytes: nameBytes, encoding: .utf8), knownDirs.contains(name) else { continue }

            let time = lineTime > 0 ? lineTime : fallbackTime
            result[name] = max(result[name] ?? 0, time)
        }
        return (result, baseOffset + completeBytes(in: data), firstPrompt)
    }

    /// 只看文件头部约 50 行，取第一条 user 消息，截 500 字符。不做全文 JSON 解码。
    private static func extractFirstPrompt(from data: Data) -> String? {
        var cursor = data.startIndex
        var lines = 0
        while lines < 50, cursor < data.endIndex {
            let end = data[cursor...].firstIndex(of: newline) ?? data.endIndex
            let line = data[cursor..<end]
            if let text = decodeUserLine(line) {
                return String(text.prefix(500))
            }
            if end == data.endIndex { break }
            cursor = data.index(after: end)
            lines += 1
        }
        return nil
    }

    private static func decodeUserLine(_ line: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        let type = (object["type"] as? String)?.lowercased() ?? ""
        let role = ((object["message"] as? [String: Any])?["role"] as? String)?.lowercased()
            ?? (object["role"] as? String)?.lowercased()
            ?? ""
        let isUser = type == "user" || type == "human" || role == "user" || role == "human"
        guard isUser else { return nil }
        if let message = object["message"] as? [String: Any] {
            if let text = flattenContent(message["content"]) { return text }
        }
        if let text = flattenContent(object["content"]) { return text }
        if let text = object["text"] as? String { return text }
        return nil
    }

    private static func flattenContent(_ raw: Any?) -> String? {
        if let text = raw as? String, !text.isEmpty { return text }
        if let parts = raw as? [[String: Any]] {
            let texts = parts.compactMap { $0["text"] as? String }
            let joined = texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    /// 已对齐到完整行末的字节数。文件末尾没有换行时停在上一行，下次续读会再带上半截。
    private static func completeBytes(in data: Data) -> Int {
        if data.isEmpty { return 0 }
        if data[data.index(before: data.endIndex)] == newline {
            return data.count
        }
        if let last = data.lastIndex(of: newline) {
            return data.distance(from: data.startIndex, to: data.index(after: last))
        }
        return 0
    }

    private static func extractTimestamp(_ data: Data, in range: Range<Data.Index>) -> Double {
        guard let key = data.range(of: timestampKey, in: range) else { return 0 }
        var end = key.upperBound
        var bytes: [UInt8] = []
        while end < range.upperBound, data[end] != UInt8(ascii: "\""), bytes.count < 40 {
            bytes.append(data[end])
            end = data.index(after: end)
        }
        guard let text = String(bytes: bytes, encoding: .utf8) else { return 0 }
        let date = isoWithMillis.date(from: text) ?? isoPlain.date(from: text)
        return date?.timeIntervalSince1970 ?? 0
    }
}
