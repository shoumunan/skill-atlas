import Foundation
import SQLite3

/// 扫描：
/// 主源永远是 ~/.skill-atlas/skills。挂载检查看各平台软链是否指向本库。
/// CC Switch 只在尚未迁完时当发现源；平台目录**始终**扫描——发现散装技能
/// （origin == local）供收编，包括迁完 CC Switch 之后手动新装的。已收录的
/// 入口 resolve 后都在 seenPaths 里，不会重复计入。绝不写入 CC Switch。
enum SkillScanner {
    /// 调试钩子：-atlasHome /tmp/fake-home 注入假 HOME（纯本地用户路径测试用）
    static var home: URL {
        if let injected = LaunchArgs.value("atlasHome") ?? UserDefaults.standard.string(forKey: "atlasHome"),
           !injected.isEmpty {
            return URL(fileURLWithPath: injected, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var databaseURL: URL { home.appendingPathComponent(".cc-switch/cc-switch.db") }
    static var sourceRoot: URL { home.appendingPathComponent(".cc-switch/skills") }
    static var codexRoot: URL { home.appendingPathComponent(".codex/skills") }
    static var claudeRoot: URL { home.appendingPathComponent(".claude/skills") }

    struct ScanFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func scan() throws -> AtlasData {
        AtlasCatalog.migrateLegacyIfNeeded()
        let catalog = AtlasCatalog.load()
        let hasCCSwitch = FileManager.default.fileExists(atPath: databaseURL.path)
        let migrated = catalog.migratedFromCCSwitch

        var skills: [Skill] = []
        var healthCounts: [Health: Int] = [.healthy: 0, .warning: 0, .error: 0]
        var verifiedCodex = 0
        var verifiedClaude = 0
        var seenPaths = Set<String>()
        var seenNames = Set<String>()

        // 主源：本库
        let atlasSkills = scanAtlasLibrary(catalog: catalog)
        for skill in atlasSkills {
            if !skill.disabled { healthCounts[skill.health, default: 0] += 1 }
            if skill.mountCodex.status == .ok { verifiedCodex += 1 }
            if skill.mountClaude.status == .ok { verifiedClaude += 1 }
            skills.append(skill)
            seenPaths.insert(URL(fileURLWithPath: skill.sourcePath).resolvingSymlinksInPath().standardizedFileURL.path)
            seenNames.insert(skill.name)
        }

        // CC Switch 只在尚未迁完时当发现源；迁完后不再读它的技能表。
        if !migrated && hasCCSwitch {
            let rows = (try? readSkillRows()) ?? []
            for row in rows {
                let name = row.text("name")
                let directory = row.text("directory")
                let source = sourceRoot.appendingPathComponent(directory)
                let realPath = source.resolvingSymlinksInPath().standardizedFileURL.path
                if seenPaths.contains(realPath) || seenNames.contains(name) { continue }
                let skill = skillFromCCSwitch(row: row)
                if !skill.disabled { healthCounts[skill.health, default: 0] += 1 }
                if skill.mountCodex.status == .ok { verifiedCodex += 1 }
                if skill.mountClaude.status == .ok { verifiedClaude += 1 }
                skills.append(skill)
                seenPaths.insert(realPath)
                seenNames.insert(name)
            }
        }

        // 平台目录始终扫描：发现散装技能供收编——迁完 CC Switch 的用户手动新装的
        // 散装技能也要能看见（否则收编不可达，且体检/安全扫描对它全盲）。
        // 已收进库/CC 已收录的入口 resolve 后都在 seenPaths 里，不会重复计入。
        let localSkills = scanLocalSkills(excluding: seenPaths, usedNames: seenNames)
        for skill in localSkills {
            if !skill.disabled { healthCounts[skill.health, default: 0] += 1 }
            skills.append(skill)
            seenPaths.insert(URL(fileURLWithPath: skill.sourcePath).resolvingSymlinksInPath().standardizedFileURL.path)
            seenNames.insert(skill.name)
        }

        skills.sort {
            if $0.disabled != $1.disabled { return !$0.disabled }
            return $0.name.lowercased() < $1.name.lowercased()
        }

        let atlasCount = skills.filter { $0.origin == .atlas }.count
        let ccSwitchCount = skills.filter { $0.origin == .ccSwitch }.count
        let summary = Summary(
            total: skills.count,
            codexCount: skills.filter { $0.platforms.contains("Codex") && !$0.disabled }.count,
            claudeCount: skills.filter { $0.platforms.contains("Claude") && !$0.disabled }.count,
            enabledCodex: skills.filter { $0.platforms.contains("Codex") && !$0.disabled }.count,
            enabledClaude: skills.filter { $0.platforms.contains("Claude") && !$0.disabled }.count,
            enabledGrokBuild: skills.filter { $0.platforms.contains("GrokBuild") && !$0.disabled }.count,
            verifiedCodex: verifiedCodex,
            verifiedClaude: verifiedClaude,
            ccSwitchCount: ccSwitchCount,
            localCount: skills.filter { $0.origin == .local }.count,
            atlasCount: atlasCount,
            hasCCSwitch: hasCCSwitch,
            migrated: migrated,
            health: healthCounts,
            sourceRoot: AtlasPaths.libraryRoot.path,
            database: databaseURL.path,
            checkedPaths: checkedScanPaths(hasCCSwitch: hasCCSwitch),
            scannedAt: Date()
        )
        return AtlasData(skills: skills, summary: summary)
    }

    /// 设置页「扫描范围」展示的真实路径：本库 + CC Switch 源 + 各平台根。
    /// 根是软链时标注 resolve 后的落点（如 ~/.claude/skills → ~/.mirasim/skills）。
    private static func checkedScanPaths(hasCCSwitch: Bool) -> [String] {
        var paths: [String] = [AtlasPaths.libraryRoot.path]
        if hasCCSwitch {
            paths.append(sourceRoot.path + "（只读）")
        }
        for platform in AgentPlatform.allCases {
            let root = platform.root(home: home)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let resolved = root.resolvingSymlinksInPath().path
            paths.append(resolved == root.path ? root.path : "\(root.path) → \(resolved)")
        }
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }


    private static func skillFromCCSwitch(row: Row) -> Skill {
        let name = row.text("name")
        let directory = row.text("directory")
        let source = sourceRoot.appendingPathComponent(directory)
        let skillFile = source.appendingPathComponent("SKILL.md")
        let metadata = readFrontmatter(skillFile)

        var description = row.text("description")
        if description.isEmpty { description = metadata["description"] ?? "" }
        if description.isEmpty { description = "暂无用途说明" }
        description = description.trimmingCharacters(in: .whitespacesAndNewlines)

        let category = inferCategory(name: name, description: description)
        let enabledCodex = row.int("enabled_codex") != 0
        let enabledClaude = row.int("enabled_claude") != 0
        let mountCodex = mountState(root: codexRoot, directory: directory, enabled: enabledCodex, source: source)
        let mountClaude = mountState(root: claudeRoot, directory: directory, enabled: enabledClaude, source: source)

        var problems: [String] = []
        var severity = Health.healthy
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: source.path) {
            problems.append("源目录缺失")
            severity = .error
        }
        var isDirectory: ObjCBool = false
        let skillFileOK = fileManager.fileExists(atPath: skillFile.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        if !skillFileOK {
            problems.append("SKILL.md 缺失")
            severity = .error
        }
        for (label, mount) in [("Codex", mountCodex), ("Claude", mountClaude)] {
            switch mount.status {
            case .missing, .broken, .wrong:
                let word = [MountStatus.missing: "缺失", .broken: "断链", .wrong: "目标错误"][mount.status]!
                problems.append("\(label) 挂载\(word)")
                severity = .error
            case .directory, .unexpected:
                problems.append("\(label) \(mount.status == .directory ? "是普通目录" : "存在未启用挂载")")
                if severity != .error { severity = .warning }
            case .ok, .disabled:
                break
            }
        }
        if let metaName = metadata["name"], !metaName.isEmpty, metaName != name {
            problems.append("名称元数据不一致")
            if severity != .error { severity = .warning }
        }

        let platformFlags: [(String, String)] = [
            ("enabled_codex", "Codex"), ("enabled_claude", "Claude"),
            ("enabled_gemini", "Gemini"), ("enabled_opencode", "OpenCode"),
            ("enabled_hermes", "Hermes"), ("enabled_grokbuild", "GrokBuild"),
            ("enabled_workbuddy", "WorkBuddy"), ("enabled_openclaw", "OpenClaw"),
        ]
        let platforms = platformFlags.compactMap { key, label in row.int(key) != 0 ? label : nil }

        let modifiedAt: Int
        if let attributes = try? fileManager.attributesOfItem(atPath: skillFile.path),
           let date = attributes[.modificationDate] as? Date {
            modifiedAt = Int(date.timeIntervalSince1970)
        } else {
            modifiedAt = 0
        }

        let repoOwner = row.text("repo_owner")
        let repoName = row.text("repo_name")
        let repoBranch = row.text("repo_branch")
        let repo = [repoOwner, repoName].filter { !$0.isEmpty }.joined(separator: "/")
        let updatedAt = row.int("updated_at")

        return Skill(
            dbId: row.int("id"),
            name: name,
            directory: directory,
            description: description,
            category: category,
            whenToUse: deriveWhen(name: name, description: description, category: category),
            examplePrompts: deriveExamples(name: name, category: category),
            platforms: platforms,
            sourcePath: source.path,
            skillFile: skillFile.path,
            repo: repo.isEmpty ? L("未关联仓库") : repo,
            repoOwner: repoOwner,
            repoName: repoName,
            repoBranch: repoBranch.isEmpty ? "main" : repoBranch,
            installedAt: row.int("installed_at"),
            updatedAt: updatedAt != 0 ? updatedAt : modifiedAt,
            health: severity,
            problems: problems,
            mountCodex: mountCodex,
            mountClaude: mountClaude,
            origin: .ccSwitch,
            searchText: "\(name) \(description) \(category) cc switch".lowercased()
        )
    }

    // MARK: - Skill Atlas 自己的库

    private static func scanAtlasLibrary(catalog: AtlasCatalogFile) -> [Skill] {
        let fileManager = FileManager.default
        let root = AtlasPaths.libraryRoot
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        func collect(from directory: URL, disabled: Bool) -> [(URL, String)] {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: disabled ? [] : [.skipsHiddenFiles]
            ) else { return [] }
            return entries.compactMap { entry in
                guard !entry.lastPathComponent.hasPrefix(".") else { return nil }
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { return nil }
                return (entry, entry.lastPathComponent)
            }
        }

        var hits: [(url: URL, directory: String, disabled: Bool)] = []
        for (url, name) in collect(from: root, disabled: false) {
            hits.append((url, name, false))
        }
        for (url, name) in collect(from: AtlasPaths.disabledRoot, disabled: true) {
            hits.append((url, name, true))
        }

        var result: [Skill] = []
        for hit in hits.sorted(by: { $0.directory < $1.directory }) {
            let record = catalog.skills[hit.directory]
            let source = hit.url
            let skillFile = source.appendingPathComponent("SKILL.md")
            let metadata = readFrontmatter(skillFile)
            let name = metadata["name"].flatMap { $0.isEmpty ? nil : $0 } ?? hit.directory

            var description = (metadata["description"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if description.isEmpty { description = "暂无用途说明" }
            let category = inferCategory(name: name, description: description)

            var problems: [String] = []
            var severity = Health.healthy
            var isFile: ObjCBool = false
            let skillFileOK = fileManager.fileExists(atPath: skillFile.path, isDirectory: &isFile) && !isFile.boolValue
            if !skillFileOK {
                problems.append("SKILL.md 缺失")
                severity = .error
            }

            var platforms: [String] = []
            var mountClaude = Mount(enabled: false, status: .disabled, path: "", isLink: false, target: "")
            var mountCodex = Mount(enabled: false, status: .disabled, path: "", isLink: false, target: "")
            for platform in AgentPlatform.allCases {
                let enabled = (record?.isEnabled(platform) ?? false) && !hit.disabled
                let mount = mountState(
                    root: platform.root(home: home),
                    directory: hit.directory,
                    enabled: enabled,
                    source: source
                )
                if platform == .claude { mountClaude = mount }
                if platform == .codex { mountCodex = mount }
                if enabled { platforms.append(platform.label) }
                guard !hit.disabled else { continue }
                switch mount.status {
                case .missing, .broken, .wrong:
                    let word = [MountStatus.missing: "缺失", .broken: "断链", .wrong: "目标错误"][mount.status]!
                    problems.append("\(platform.label) 挂载\(word)")
                    severity = .error
                case .directory, .unexpected:
                    problems.append("\(platform.label) \(mount.status == .directory ? "是普通目录" : "存在未启用挂载")")
                    if severity != .error { severity = .warning }
                case .ok, .disabled:
                    break
                }
            }

            let attributes = try? fileManager.attributesOfItem(atPath: source.path)
            let filesystemInstalled = (attributes?[.creationDate] as? Date).map { Int($0.timeIntervalSince1970) }
                ?? (attributes?[.modificationDate] as? Date).map { Int($0.timeIntervalSince1970) } ?? 0
            let installedAt = (record?.installedAt).flatMap { $0 != 0 ? $0 : nil } ?? filesystemInstalled
            let modifiedAt = (try? fileManager.attributesOfItem(atPath: skillFile.path))
                .flatMap { $0[.modificationDate] as? Date }
                .map { Int($0.timeIntervalSince1970) } ?? installedAt
            let updatedAt = (record?.updatedAt).flatMap { $0 != 0 ? $0 : nil } ?? modifiedAt

            result.append(Skill(
                dbId: 0,
                name: name,
                directory: hit.directory,
                description: description,
                category: category,
                whenToUse: deriveWhen(name: name, description: description, category: category),
                examplePrompts: deriveExamples(name: name, category: category),
                platforms: platforms,
                sourcePath: source.path,
                skillFile: skillFile.path,
                repo: record?.repoDisplay ?? "Skill Atlas",
                repoOwner: record?.repoOwner ?? "",
                repoName: record?.repoName ?? "",
                repoBranch: record?.repoBranch ?? "main",
                installedAt: installedAt,
                updatedAt: updatedAt,
                health: severity,
                problems: problems,
                mountCodex: mountCodex,
                mountClaude: mountClaude,
                origin: .atlas,
                disabled: hit.disabled,
                searchText: "\(name) \(description) \(category) skill atlas 本地\(hit.disabled ? " 已停用" : "")".lowercased()
            ))
        }
        return result
    }

    // MARK: - 本地安装技能（DB / Atlas 之外的真实目录）

    private static func scanLocalSkills(excluding seenPaths: Set<String>, usedNames: Set<String>) -> [Skill] {
        let fileManager = FileManager.default
        /// 真实源路径 → 在哪些平台根目录发现 + 是否位于 .disabled/（已停用）
        var found: [String: (dirName: String, platforms: Set<String>, disabled: Bool)] = [:]

        func collect(from directory: URL, platform: String, disabled: Bool) {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: disabled ? [] : [.skipsHiddenFiles]
            ) else { return }
            for entry in entries {
                guard !entry.lastPathComponent.hasPrefix(".") else { continue }
                let real = entry.resolvingSymlinksInPath().standardizedFileURL
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: real.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }
                // CC Switch 已收录（直接目录里的软链指回 ~/.cc-switch/skills）→ 不重复计入
                guard !seenPaths.contains(real.path) else { continue }
                found[real.path, default: (entry.lastPathComponent, [], disabled)].platforms.insert(platform)
            }
        }

        for platform in AgentPlatform.allCases {
            collect(from: platform.root(home: home).resolvingSymlinksInPath(), platform: platform.label, disabled: false)
            collect(
                from: platform.root(home: home).resolvingSymlinksInPath().appendingPathComponent(".disabled"),
                platform: platform.label,
                disabled: true
            )
        }

        var names = usedNames
        var result: [Skill] = []
        for (realPath, hit) in found.sorted(by: { $0.value.dirName < $1.value.dirName }) {
            let source = URL(fileURLWithPath: realPath, isDirectory: true)
            let skillFile = source.appendingPathComponent("SKILL.md")
            let metadata = readFrontmatter(skillFile)
            let name = metadata["name"].flatMap { $0.isEmpty ? nil : $0 } ?? hit.dirName
            // 与 DB 技能重名的本地技能跳过（id 以 name 为键；同名不同源极罕见）
            guard !names.contains(name) else { continue }
            names.insert(name)

            var description = (metadata["description"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if description.isEmpty { description = "暂无用途说明" }
            let category = inferCategory(name: name, description: description)

            // 本地技能没有 enable 标志和挂载概念：SKILL.md 可解析即健康，缺失即异常
            var problems: [String] = []
            var severity = Health.healthy
            var isFile: ObjCBool = false
            let skillFileOK = fileManager.fileExists(atPath: skillFile.path, isDirectory: &isFile) && !isFile.boolValue
            if !skillFileOK {
                problems.append("SKILL.md 缺失")
                severity = .error
            }

            let attributes = try? fileManager.attributesOfItem(atPath: realPath)
            let installedAt = (attributes?[.creationDate] as? Date).map { Int($0.timeIntervalSince1970) }
                ?? (attributes?[.modificationDate] as? Date).map { Int($0.timeIntervalSince1970) } ?? 0
            let modifiedAt = (try? fileManager.attributesOfItem(atPath: skillFile.path))
                .flatMap { $0[.modificationDate] as? Date }
                .map { Int($0.timeIntervalSince1970) } ?? installedAt

            let noMount = Mount(enabled: false, status: .disabled, path: "", isLink: false, target: "")
            result.append(Skill(
                dbId: 0,
                name: name,
                directory: hit.dirName,
                description: description,
                category: category,
                whenToUse: deriveWhen(name: name, description: description, category: category),
                examplePrompts: deriveExamples(name: name, category: category),
                platforms: hit.platforms.sorted(),
                sourcePath: realPath,
                skillFile: skillFile.path,
                repo: "本地 Skill",
                installedAt: installedAt,
                updatedAt: modifiedAt,
                health: severity,
                problems: problems,
                mountCodex: noMount,
                mountClaude: noMount,
                origin: .local,
                disabled: hit.disabled,
                searchText: "\(name) \(description) \(category) 本地安装 local\(hit.disabled ? " 已停用" : "")".lowercased()
            ))
        }
        return result
    }

    // MARK: - SQLite（只读打开，任何失败都转成用户可读的中文错误）

    struct Row {
        var values: [String: Any]

        func text(_ key: String) -> String {
            (values[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        func int(_ key: String) -> Int {
            if let number = values[key] as? Int64 { return Int(number) }
            if let number = values[key] as? Double { return Int(number) }
            if let text = values[key] as? String { return Int(text) ?? 0 }
            return 0
        }
    }

    static func readSkillRows() throws -> [Row] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw ScanFailure(message: "找不到 CC Switch 数据库：\(databaseURL.path)")
        }
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            defer { sqlite3_close(database) }
            throw ScanFailure(message: "无法以只读方式打开 CC Switch 数据库")
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let sql = "SELECT * FROM skills ORDER BY name COLLATE NOCASE"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let detail = String(cString: sqlite3_errmsg(database))
            throw ScanFailure(message: "读取 skills 表失败：\(detail)")
        }
        defer { sqlite3_finalize(statement) }

        let columnCount = sqlite3_column_count(statement)
        var columnNames: [String] = []
        for index in 0..<columnCount {
            columnNames.append(String(cString: sqlite3_column_name(statement, index)))
        }

        var rows: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var values: [String: Any] = [:]
            for index in 0..<columnCount {
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    values[columnNames[Int(index)]] = sqlite3_column_int64(statement, index)
                case SQLITE_FLOAT:
                    values[columnNames[Int(index)]] = sqlite3_column_double(statement, index)
                case SQLITE_TEXT:
                    values[columnNames[Int(index)]] = String(cString: sqlite3_column_text(statement, index))
                default:
                    break
                }
            }
            rows.append(Row(values: values))
        }
        return rows
    }

    // MARK: - 逻辑移植

    static func inferCategory(name: String, description: String) -> String {
        let haystack = "\(name) \(description)".lowercased()
        for (category, words) in Rules.categoryRules where words.contains(where: haystack.contains) {
            return category
        }
        return "通用工具"
    }

    /// 解析 SKILL.md 顶部的 YAML frontmatter，仅提取 name / description。
    static func readFrontmatter(_ file: URL) -> [String: String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8), text.hasPrefix("---") else {
            return [:]
        }
        guard let endRange = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else {
            return [:]
        }
        let frontmatter = String(text[text.index(text.startIndex, offsetBy: 3)..<endRange.lowerBound])
        var result: [String: String] = [:]
        for key in ["name", "description"] {
            let pattern = "(?ms)^\(key):\\s*(.*?)(?=\\n[a-zA-Z_-]+:|\\z)"
            guard let match = frontmatter.firstMatch(pattern: pattern) else { continue }
            var value = match.trimmingCharacters(in: .whitespacesAndNewlines)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if value == "|" || value == ">" { value = "" }
            value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { result[key] = value }
        }
        return result
    }

    /// 校验单个平台的软连接状态（不跟随/跟随符号链接的语义与 Python 版一致）。
    static func mountState(root: URL, directory: String, enabled: Bool, source: URL) -> Mount {
        let fileManager = FileManager.default
        let target = root.appendingPathComponent(directory)
        let attributes = try? fileManager.attributesOfItem(atPath: target.path)
        let isLink = (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
        let exists = fileManager.fileExists(atPath: target.path) // 跟随符号链接；断链视为不存在

        let status: MountStatus
        if enabled {
            if !exists {
                status = isLink ? .broken : .missing
            } else if !isLink {
                status = .directory
            } else {
                let resolvedTarget = target.resolvingSymlinksInPath().standardizedFileURL.path
                let resolvedSource = source.resolvingSymlinksInPath().standardizedFileURL.path
                status = resolvedTarget == resolvedSource ? .ok : .wrong
            }
        } else {
            status = (exists || isLink) ? .unexpected : .disabled
        }
        let linkTarget = isLink ? target.resolvingSymlinksInPath().path : ""
        return Mount(enabled: enabled, status: status, path: target.path, isLink: isLink, target: linkTarget)
    }

    static func deriveWhen(name: String, description: String, category: String) -> String {
        let clean = description.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if let match = clean.firstMatch(pattern: "(当用户[^。；]{8,180}[。；]?)") {
            return match.hasSuffix("；") ? String(match.dropLast()) : match
        }
        if let match = clean.firstMatch(pattern: "(?i)(Use (?:this skill )?when[^.]{8,180}\\.)") {
            return match
        }
        return Rules.whenTemplates[category] ?? "当你的任务与 \(name) 描述的能力直接相关时调用。"
    }

    static func deriveExamples(name: String, category: String) -> [String] {
        if let curated = Rules.examplePrompts[name] { return curated }
        let first = Rules.exampleTemplates[category].map { String(format: $0, name) }
            ?? "请使用 \(name) 帮我完成：<描述你的目标、素材和交付格式>"
        return [first, "这个任务适合用 \(name) 吗？请先判断，再按它的流程执行"]
    }
}

private extension String {
    /// 返回第一个匹配的捕获组（无捕获组时返回整个匹配）。
    func firstMatch(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return nil }
        let groupIndex = match.numberOfRanges > 1 ? 1 : 0
        guard let swiftRange = Range(match.range(at: groupIndex), in: self) else { return nil }
        return String(self[swiftRange])
    }
}
