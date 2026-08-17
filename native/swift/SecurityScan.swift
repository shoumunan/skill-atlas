import Foundation

// MARK: - 装前安全扫描（二期 F3，入向红线）
//
// 依据 2026 公开测量（Snyk ToxicSkills、NVIDIA SkillSpector、Datadog、SlowMist）：
// 公开市场约 1/4 技能有漏洞、1/20 疑似恶意。已知手法全部入规则：
//   动态上下文 !`cmd`（命令在模型看到内容之前执行）· curl|sh 管道 · Base64 藏命令
//   隐藏 Unicode（零宽/双向控制/标签字符）· allowed-tools 全权声明（解析但不强制=安全幻觉）
//   硬编码密钥 · 外链清单
// 纯静态、离线、毫秒级；安装时强制过闸，已装技能由体检页复扫。

struct SecurityFinding: Identifiable, Hashable, Codable {
    enum Severity: Int, Comparable, Codable {
        case critical = 0, warning = 1, info = 2
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var severity: Severity
    /// 规则名（中文键，界面经 L() 本地化）
    var rule: String
    /// 命中文件（相对技能目录）
    var file: String
    /// 1 起行号；0 = 整文件级
    var line: Int
    /// 命中行原文（截断）
    var excerpt: String

    var id: String { "\(file):\(line):\(rule):\(excerpt.hashValue)" }
}

enum SecurityScanner {
    /// 缓存版本：规则或 Finding 形态变了就 +1，避免读到过期命中
    private static let cacheVersion = 1

    private struct FileEntry: Codable {
        var mtime: Double
        var size: Int
        var findings: [SecurityFinding]
    }

    private struct Cache: Codable {
        var version: Int
        var files: [String: FileEntry]
    }

    /// 单技能目录静态扫描。只读，最多 200 个文本文件、单文件 ≤ 1 MB、深度 ≤ 3。
    /// 按逐文件 (path, mtime, size) 命中 `security-index.json`，未变的文件不重读。
    static func scan(directory: URL) -> [SecurityFinding] {
        var cache = loadCache()
        var liveFiles = Set<String>()
        let findings = scanDirectory(directory, cache: &cache, liveFiles: &liveFiles)
        saveCache(cache)
        return findings
    }

    /// 已装技能增量复扫：一次载入/落盘缓存，按目录归并发现。
    static func scanInstalled(targets: [(directory: String, path: String)]) -> [String: [SecurityFinding]] {
        var cache = loadCache()
        var result: [String: [SecurityFinding]] = [:]
        var liveFiles = Set<String>()
        let prefixes = targets.map { $0.path.hasSuffix("/") ? $0.path : $0.path + "/" }
        for target in targets {
            let url = URL(fileURLWithPath: target.path, isDirectory: true)
            let findings = scanDirectory(url, cache: &cache, liveFiles: &liveFiles)
            if !findings.isEmpty { result[target.directory] = findings }
        }
        cache.files = cache.files.filter { key, _ in
            liveFiles.contains(key) || !prefixes.contains(where: { key.hasPrefix($0) })
        }
        saveCache(cache)
        return result
    }

    private static func loadCache() -> Cache {
        guard let data = try? Data(contentsOf: AtlasPaths.securityIndexURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.version == cacheVersion else {
            return Cache(version: cacheVersion, files: [:])
        }
        return cache
    }

    private static func saveCache(_ cache: Cache) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: AtlasPaths.securityIndexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: AtlasPaths.securityIndexURL, options: .atomic)
        }
    }

    private static let textExtensions: Set<String> = [
        "md", "sh", "bash", "zsh", "py", "js", "ts", "rb", "pl", "swift", "txt", "json", "yaml", "yml", "toml",
    ]
    private static let scriptExtensions: Set<String> = ["sh", "bash", "zsh", "py", "js", "ts", "rb", "pl"]

    private static func scanDirectory(
        _ directory: URL,
        cache: inout Cache,
        liveFiles: inout Set<String>
    ) -> [SecurityFinding] {
        var findings: [SecurityFinding] = []
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var scanned = 0
        for case let url as URL in enumerator {
            if enumerator.level > 3 { enumerator.skipDescendants(); continue }
            let ext = url.pathExtension.lowercased()
            guard textExtensions.contains(ext) else { continue }
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
            ])
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) <= 1_048_576 else { continue }
            guard scanned < 200 else { break }
            scanned += 1

            let path = url.path
            liveFiles.insert(path)
            let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = values?.fileSize ?? 0
            if let hit = cache.files[path], hit.mtime == mtime, hit.size == size {
                findings.append(contentsOf: hit.findings)
            } else {
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let relative = path.replacingOccurrences(of: directory.path + "/", with: "")
                let fileFindings = scanFile(
                    content: content,
                    relativePath: relative,
                    isMarkdown: ext == "md",
                    isScript: scriptExtensions.contains(ext)
                )
                cache.files[path] = FileEntry(mtime: mtime, size: size, findings: fileFindings)
                findings.append(contentsOf: fileFindings)
            }
            if findings.count > 60 { break }
        }
        return Array(findings.sorted { $0.severity < $1.severity }.prefix(60))
    }

    /// 目录里是否存在关键级发现（安装闸门用）
    static func hasCritical(_ findings: [SecurityFinding]) -> Bool {
        findings.contains { $0.severity == .critical }
    }

    // MARK: 规则

    private static let pipeToShell = try! NSRegularExpression(
        pattern: #"\b(curl|wget)\b[^\n|]*\|\s*(sudo\s+)?(ba|z|da)?sh\b"#
    )
    private static let base64Exec = try! NSRegularExpression(
        pattern: #"base64\s+(-d|-D|--decode)[^\n]*\|\s*(sudo\s+)?(ba|z)?sh|echo\s+[A-Za-z0-9+/=]{24,}[^\n]*\|\s*base64"#
    )
    private static let base64Blob = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9+/]{60,}={0,2}"#
    )
    private static let dynamicContext = try! NSRegularExpression(
        pattern: #"(^|\n)\s*!`[^`]+`"#
    )
    private static let evalCall = try! NSRegularExpression(
        pattern: #"\beval\b|\bexec\s*\(|child_process|os\.system\s*\(|subprocess\.(run|call|Popen)"#
    )
    private static let secretPattern = try! NSRegularExpression(
        pattern: #"sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_\-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----"#
    )
    private static let urlPattern = try! NSRegularExpression(
        pattern: #"https?://[A-Za-z0-9.\-]+(:\d+)?[^\s"'`)\]>，。）]*"#
    )
    // 三种全权形态：裸星号（allowed-tools: *）、Bash(*) / Bash(*:*)、清单里夹裸星号（[Read, *]）。
    // 旧版 bug：前缀 \s*:\s* 吃掉唯一冒号后，各分支再要求行首/逗号/二次冒号，裸星号反而漏报。
    private static let fullGrant = try! NSRegularExpression(
        pattern: #"allowed-tools\s*:\s*(\*\s*$|.*Bash\(\*(\:\*)?\)|.*[,\[]\s*\*\s*([,\]]|$))"#,
        options: [.anchorsMatchLines]
    )

    /// 域名白名单：出现在这些域的外链不计入 info 清单
    private static let trustedHosts: Set<String> = [
        "github.com", "raw.githubusercontent.com", "gist.github.com",
        "docs.anthropic.com", "anthropic.com", "claude.ai", "claude.com",
        "developer.apple.com", "apple.com",
        "npmjs.com", "pypi.org", "crates.io",
        "en.wikipedia.org", "zh.wikipedia.org",
    ]

    private static func scanFile(
        content: String,
        relativePath: String,
        isMarkdown: Bool,
        isScript: Bool
    ) -> [SecurityFinding] {
        var findings: [SecurityFinding] = []
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let lineStarts = lineStartOffsets(in: nsContent)

        func lineNumber(at location: Int) -> Int {
            lineAt(starts: lineStarts, location: location)
        }

        func excerpt(at location: Int) -> String {
            let lineRange = nsContent.lineRange(for: NSRange(location: location, length: 0))
            let raw = nsContent.substring(with: lineRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.count > 160 ? String(raw.prefix(160)) + "…" : raw
        }

        func add(_ severity: SecurityFinding.Severity, _ rule: String, _ regex: NSRegularExpression, limit: Int = 5) {
            var count = 0
            regex.enumerateMatches(in: content, range: fullRange) { match, _, stop in
                guard let match else { return }
                findings.append(SecurityFinding(
                    severity: severity, rule: rule, file: relativePath,
                    line: lineNumber(at: match.range.location),
                    excerpt: excerpt(at: match.range.location)
                ))
                count += 1
                if count >= limit { stop.pointee = true }
            }
        }

        // 1. 隐藏 Unicode（任何文件都算关键级）。
        // 良性格式字符不计：U+200C/200D（ZWNJ/ZWJ，组合 emoji 与部分文种的正常成分）；
        // U+FEFF 仅在非文件开头才算（开头是 UTF-8 BOM，良性）——否则干净技能被误拦。
        var hiddenScalars: Set<UInt32> = []
        var isFirstScalar = true
        for scalar in content.unicodeScalars {
            switch scalar.value {
            case 0x200B, 0x200E, 0x200F, 0x202A...0x202E, 0x2060...0x2064, 0xE0000...0xE007F:
                hiddenScalars.insert(scalar.value)
            case 0xFEFF where !isFirstScalar:
                hiddenScalars.insert(scalar.value)
            default: break
            }
            isFirstScalar = false
        }
        if !hiddenScalars.isEmpty {
            let codes = hiddenScalars.sorted().prefix(6)
                .map { String(format: "U+%04X", $0) }.joined(separator: " ")
            findings.append(SecurityFinding(
                severity: .critical, rule: "隐藏 Unicode 字符（可携带对模型的隐形指令）",
                file: relativePath, line: 0, excerpt: codes
            ))
        }

        // 2. 动态上下文（仅 Markdown 有意义：!`cmd` 在模型读到内容前执行）
        if isMarkdown {
            add(.critical, "动态上下文命令（模型看到内容之前就会执行）", dynamicContext)
            add(.warning, "全权工具声明（allowed-tools 只被解析、不被强制执行）", fullGrant, limit: 2)
        }

        // 3. 管道执行 / Base64
        add(.critical, "下载后直接进 shell 执行（curl/wget | sh）", pipeToShell)
        add(.critical, "Base64 解码后执行", base64Exec)
        if isScript || isMarkdown {
            // 长 Base64 数据块：单文件只报一次，避免刷屏
            if let match = base64Blob.firstMatch(in: content, range: fullRange),
               !content.contains("data:image") {
                findings.append(SecurityFinding(
                    severity: .warning, rule: "长 Base64 数据块（可能隐藏命令或载荷）",
                    file: relativePath, line: lineNumber(at: match.range.location),
                    excerpt: excerpt(at: match.range.location)
                ))
            }
        }

        // 4. eval/exec 家族（脚本文件；合法用途多，降为警告）
        if isScript {
            add(.warning, "动态执行调用（eval / exec / subprocess）", evalCall, limit: 3)
        }

        // 5. 硬编码密钥
        add(.critical, "疑似硬编码密钥", secretPattern, limit: 3)

        // 6. 外链清单（非白名单域，info 级）
        var seenHosts: Set<String> = []
        urlPattern.enumerateMatches(in: content, range: fullRange) { match, _, stop in
            guard let match else { return }
            let urlText = nsContent.substring(with: match.range)
            guard let host = URL(string: urlText)?.host?.lowercased() else { return }
            let trusted = trustedHosts.contains(host)
                || trustedHosts.contains(where: { host.hasSuffix("." + $0) })
            guard !trusted, !seenHosts.contains(host) else { return }
            seenHosts.insert(host)
            findings.append(SecurityFinding(
                severity: .info, rule: "外链 URL（核对域名是否可信）",
                file: relativePath, line: lineNumber(at: match.range.location),
                excerpt: urlText.count > 120 ? String(urlText.prefix(120)) + "…" : urlText
            ))
            if seenHosts.count >= 8 { stop.pointee = true }
        }

        return findings
    }

    /// 单遍记下每个换行位置，命中行号用二分，避免按命中从文件头重数（O(n²)）。
    private static func lineStartOffsets(in nsContent: NSString) -> [Int] {
        var starts = [0]
        let length = nsContent.length
        var index = 0
        while index < length {
            if nsContent.character(at: index) == 10 { starts.append(index + 1) }
            index += 1
        }
        return starts
    }

    private static func lineAt(starts: [Int], location: Int) -> Int {
        var low = 0
        var high = starts.count
        while low + 1 < high {
            let mid = (low + high) / 2
            if starts[mid] <= location { low = mid } else { high = mid }
        }
        return low + 1
    }
}


// MARK: - 外链存活探测（防「几个月后变恶意/端点悄悄死掉」，md2card 教训）

struct DeadLink {
    var url: String
    var reason: String
}

enum LinkProber {
    /// 只把「确定死了」算死：DNS/超时/连接错误、404/410、5xx。
    /// 403/405/429 多是反爬或方法限制，不误报。
    static func probe(urls: [String]) async -> [String: String] {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        var dead: [String: String] = [:]
        // 并发 4 路，避免打爆网络
        await withTaskGroup(of: (String, String?).self) { group in
            var iterator = urls.makeIterator()
            var active = 0
            func addNext() {
                guard let url = iterator.next() else { return }
                active += 1
                group.addTask {
                    (url, await Self.probeOne(url, session: session))
                }
            }
            for _ in 0..<4 { addNext() }
            for await (url, reason) in group {
                active -= 1
                if let reason { dead[url] = reason }
                addNext()
            }
        }
        return dead
    }

    private static func probeOne(_ urlText: String, session: URLSession) async -> String? {
        guard let url = URL(string: urlText) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            switch http.statusCode {
            case 404, 410: return "HTTP \(http.statusCode)"
            case 500...599: return "HTTP \(http.statusCode)"
            default: return nil
            }
        } catch {
            let nsError = error as NSError
            // 取消/无网不算链接死
            if nsError.code == NSURLErrorNotConnectedToInternet { return nil }
            return nsError.localizedDescription
        }
    }
}
