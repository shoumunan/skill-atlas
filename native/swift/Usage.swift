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

struct SkillUsage {
    var claudeSessions = 0
    var codexSessions = 0
    var lastUsed: Date?
    var total: Int { claudeSessions + codexSessions }
}

enum UsageIndexer {
    // MARK: 缓存结构（~/.skill-atlas/usage-index.json）

    struct FileEntry: Codable {
        var mtime: Double
        var size: Int
        /// 目录名 → 该会话内最后引用的 unix 时间戳
        var skills: [String: Double]
    }

    struct Cache: Codable {
        var version: Int = 2
        /// 平台 → (会话文件路径 → 解析结果)
        var files: [String: [String: FileEntry]] = [:]
    }

    static var cacheURL: URL { AtlasPaths.usageIndexURL }

    struct Result {
        var usage: [String: SkillUsage]
        var scannedFiles: Int
        var reparsedFiles: Int
        var duration: TimeInterval
    }

    /// 全量/增量索引。`progress` 以 0–1 回调（按文件数）。
    static func index(knownDirs: Set<String>, progress: @escaping @Sendable (Double) -> Void) -> Result {
        let started = Date()
        let fileManager = FileManager.default
        var cache = (try? JSONDecoder().decode(Cache.self, from: Data(contentsOf: cacheURL))) ?? Cache()
        if cache.version != 2 { cache = Cache() }

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
            } else {
                let skills = parseFile(
                    at: job.path,
                    platform: job.platform,
                    knownDirs: knownDirs,
                    fallbackTime: job.mtime
                )
                newCache.files[job.platform, default: [:]][job.path] = FileEntry(
                    mtime: job.mtime, size: job.size, skills: skills
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
        fallbackTime: Double
    ) -> [String: Double] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              !data.isEmpty else { return [:] }

        var result: [String: Double] = [:]
        var searchStart = data.startIndex
        var lineRange: Range<Data.Index>?  // 当前已定位的行（避免同行多命中重复扫描）
        var lineAccepted = false
        var lineTime: Double = 0

        while let match = data.range(of: needle, in: searchStart..<data.endIndex) {
            searchStart = match.upperBound

            if lineRange == nil || !(lineRange!.contains(match.lowerBound)) {
                // 定位新行边界
                let lineStart = data[..<match.lowerBound].lastIndex(of: newline).map { data.index(after: $0) }
                    ?? data.startIndex
                let lineEnd = data[match.upperBound...].firstIndex(of: newline) ?? data.endIndex
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
        return result
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
