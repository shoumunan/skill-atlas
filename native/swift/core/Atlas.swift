import Foundation
import Darwin

// MARK: - Skill Atlas 自己的技能库
//
// 全部收在 ~/.skill-atlas/（对标 CC Switch 的 ~/.cc-switch/）：
//   atlas.json          元数据
//   skills/             技能源目录（平台软链指向这里）
//   skill-backups/      卸载前备份，保留最近 20 个
//   migration.json      回滚清单
//   usage-index.json    使用统计缓存
//   security-index.json 安全复扫缓存（逐文件 path/mtime/size）
// 启动时若 Application Support 里还有旧 atlas.json，一次性搬进来后删除。
// 禁止写入 CC Switch 的数据库和 ~/.cc-switch/skills 原目录。

package struct AtlasError: LocalizedError {
    package let message: String
    package var errorDescription: String? { message }
    package init(_ message: String) { self.message = message }
}

package enum AgentPlatform: String, CaseIterable, Identifiable, Codable, Hashable {
    case claude, codex, gemini, opencode, hermes, grokbuild, cursor, workbuddy, openclaw, qwenwork, doubao

    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .opencode: return "OpenCode"
        case .hermes: return "Hermes"
        case .grokbuild: return "GrokBuild"
        case .cursor: return "Cursor"
        case .workbuddy: return "WorkBuddy"
        case .openclaw: return "OpenClaw"
        case .qwenwork: return "QwenWork"
        case .doubao: return "Doubao"
        }
    }

    /// 界面展示名（`label` 是 skills.platforms 的存储键，不能改）。
    /// 从 PlatformIcon.swift 挪到 core：Atlas / Installer 的人话报错也要用。
    package var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .grokbuild: return "Grok"
        case .cursor: return "Cursor"
        case .workbuddy: return "WorkBuddy"
        case .openclaw: return "OpenClaw"
        case .opencode: return "OpenCode"
        case .hermes: return "Hermes"
        case .qwenwork: return "千问办公"
        case .doubao: return "豆包"
        }
    }

    package var dbColumn: String { "enabled_\(rawValue)" }

    package func root(home: URL) -> URL {
        // 用户覆盖优先（PlatformRoots）：不是所有 agent 都用固定的 ~/.<name>/skills
        if let custom = PlatformRoots.override(for: self) { return custom }
        return defaultRoot(home: home)
    }

    /// 内置默认路径。设置页要拿它做占位与「恢复默认」。
    package func defaultRoot(home: URL) -> URL {
        switch self {
        case .claude: return home.appendingPathComponent(".claude/skills")
        case .codex: return home.appendingPathComponent(".codex/skills")
        case .gemini: return home.appendingPathComponent(".gemini/skills")
        case .opencode:
            let known = home.appendingPathComponent(".config/opencode/skills")
            if FileManager.default.fileExists(atPath: known.path) { return known }
            return home.appendingPathComponent(".opencode/skills")
        case .hermes: return home.appendingPathComponent(".hermes/skills")
        case .grokbuild: return home.appendingPathComponent(".grok/skills")
        case .cursor: return home.appendingPathComponent(".cursor/skills")
        case .workbuddy: return home.appendingPathComponent(".workbuddy/skills")
        case .openclaw: return home.appendingPathComponent(".openclaw/skills")
        // 千问办公：阿里云官方文档与 qwenwork.cn 文档一致写明 ~/.qwenworkcn/skills（2026-08-28 核对）
        case .qwenwork: return home.appendingPathComponent(".qwenworkcn/skills")
        // 豆包办公模式读的是用户在它里面指定的文件夹，没有官方固定路径。
        // 这里给一个约定俗成的默认值，设置页可改（PlatformRoots）。
        case .doubao: return home.appendingPathComponent(".doubao/skills")
        }
    }

    /// 目录路径是否由用户改过（设置页显示「已自定义」）
    package var hasCustomRoot: Bool { PlatformRoots.override(for: self) != nil }

    /// 该平台的默认路径是否只是约定、需要用户确认（豆包）
    package var rootNeedsConfirmation: Bool { self == .doubao }

    /// 写软链的真实目录：根本身是软链时（~/.claude/skills → ~/.mirasim/skills）先 resolve
    package func resolvedRoot(home: URL) -> URL {
        let raw = root(home: home)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: raw.path, isDirectory: &isDir) {
            return raw.resolvingSymlinksInPath()
        }
        return raw
    }
}

package enum AtlasPaths {
    package static var home: URL { SkillScanner.home }

    package static var root: URL {
        home.appendingPathComponent(".skill-atlas")
    }

    package static var libraryRoot: URL {
        root.appendingPathComponent("skills")
    }

    package static var disabledRoot: URL {
        libraryRoot.appendingPathComponent(".disabled")
    }

    package static var backupsRoot: URL {
        root.appendingPathComponent("skill-backups")
    }

    package static var migrationLog: URL {
        root.appendingPathComponent("migration.json")
    }

    /// 更新时本地改动的补丁存档（G1：本地补丁保护的审计留痕）
    package static var patchesRoot: URL {
        root.appendingPathComponent("skill-patches")
    }

    package static var catalogURL: URL {
        root.appendingPathComponent("atlas.json")
    }

    package static var usageIndexURL: URL {
        root.appendingPathComponent("usage-index.json")
    }

    package static var securityIndexURL: URL {
        root.appendingPathComponent("security-index.json")
    }

    package static var legacySupportDir: URL {
        home.appendingPathComponent("Library/Application Support/Skill Atlas")
    }

    package static var legacyCatalogURL: URL {
        legacySupportDir.appendingPathComponent("atlas.json")
    }

    package static var legacyUsageIndexURL: URL {
        legacySupportDir.appendingPathComponent("usage-index.json")
    }
}

/// **改这个结构体前必读**：新增字段一律用 Optional（或手写 decodeIfPresent）。
/// Swift 合成的 init(from:) 不使用属性默认值——加一个非 Optional 字段，老 atlas.json
/// 解码就抛 keyNotFound，而 AtlasCatalog.load() 是 `try?` 兜底成空目录：
/// 结果是全库 enabled 位当场清零，下一次 save() 把空表落盘固化。数据毁灭级。
package struct AtlasSkillRecord: Codable, Equatable {
    package var directory: String
    package var enabled: [String: Bool]
    package var repoOwner: String
    package var repoName: String
    package var repoBranch: String
    package var installedAt: Int
    package var updatedAt: Int
    /// meta-skill 等由 App 管理的条目（WP2）。Optional：老 catalog 没有这个键。
    package var managed: Bool?
    /// 非 GitHub 来源的溯源（ADR-16）：如 "skillhub"。Optional：老 catalog 没有这个键。
    package var sourceKind: String?
    /// 来源侧版本号（SkillHub 的 version 字段），供以后的更新轮询比对。Optional。
    package var sourceVersion: String?

    /// 合成的 memberwise init 是 internal，CLI target 看不见。package 显式写出。
    package init(
        directory: String,
        enabled: [String: Bool],
        repoOwner: String,
        repoName: String,
        repoBranch: String,
        installedAt: Int,
        updatedAt: Int,
        managed: Bool? = nil,
        sourceKind: String? = nil,
        sourceVersion: String? = nil
    ) {
        self.directory = directory
        self.enabled = enabled
        self.repoOwner = repoOwner
        self.repoName = repoName
        self.repoBranch = repoBranch
        self.installedAt = installedAt
        self.updatedAt = updatedAt
        self.managed = managed
        self.sourceKind = sourceKind
        self.sourceVersion = sourceVersion
    }

    package func isEnabled(_ platform: AgentPlatform) -> Bool {
        enabled[platform.rawValue] ?? false
    }

    package var repoDisplay: String {
        let owner = repoOwner.trimmingCharacters(in: .whitespaces)
        let name = repoName.trimmingCharacters(in: .whitespaces)
        if owner.isEmpty || name.isEmpty { return "Skill Atlas" }
        return "\(owner)/\(name)"
    }
}

package struct AtlasCatalogFile: Codable {
    package var version: Int = 1
    package var migratedFromCCSwitch: Bool = false
    package var migrationSkipped: Bool = false
    package var migratedAt: Int?
    package var skills: [String: AtlasSkillRecord] = [:]
}

package enum AtlasCatalog {
    package static func load() -> AtlasCatalogFile {
        migrateLegacyIfNeeded()
        guard let data = try? Data(contentsOf: AtlasPaths.catalogURL),
              let file = try? JSONDecoder().decode(AtlasCatalogFile.self, from: data) else {
            return AtlasCatalogFile()
        }
        return file
    }

    package static func save(_ file: AtlasCatalogFile) throws {
        try FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: AtlasPaths.catalogURL, options: .atomic)
    }

    package static func upsert(_ record: AtlasSkillRecord) throws {
        var file = load()
        file.skills[record.directory] = record
        try save(file)
    }

    /// 旧版写在 Application Support。一次性搬进 ~/.skill-atlas/ 后删除旧文件。
    package static func migrateLegacyIfNeeded() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: AtlasPaths.libraryRoot, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: AtlasPaths.backupsRoot, withIntermediateDirectories: true)

        func moveIfNeeded(from old: URL, to new: URL) {
            guard fileManager.fileExists(atPath: old.path) else { return }
            if !fileManager.fileExists(atPath: new.path) {
                try? fileManager.copyItem(at: old, to: new)
            }
            try? fileManager.removeItem(at: old)
        }
        moveIfNeeded(from: AtlasPaths.legacyCatalogURL, to: AtlasPaths.catalogURL)
        moveIfNeeded(from: AtlasPaths.legacyUsageIndexURL, to: AtlasPaths.usageIndexURL)

        if let leftovers = try? fileManager.contentsOfDirectory(atPath: AtlasPaths.legacySupportDir.path),
           leftovers.isEmpty {
            try? fileManager.removeItem(at: AtlasPaths.legacySupportDir)
        }
    }
}

package struct MigrationLink: Codable {
    package var platform: String
    package var linkPath: String
    package var originalTarget: String
}

package struct MigrationLog: Codable {
    package var createdAt: Int
    package var links: [MigrationLink]
    package var cloned: [String]
}

package enum FileClone {
    /// APFS clonefile（`cp -cR`）。目标已存在则跳过。失败不回退成普通拷贝。
    package static func cloneDirectory(from: URL, to: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: to.path) { return }
        try fileManager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = ["-cR", from.path, to.path]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw AtlasError("clonefile 失败（\(from.lastPathComponent)）\(detail.isEmpty ? "" : "：\(detail)")")
        }
        guard fileManager.fileExists(atPath: to.path) else {
            throw AtlasError("clonefile 后目标不存在：\(to.path)")
        }
    }
}

package enum LinkTool {
    package static func destination(of url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else { return "" }
            var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
            let count = readlink(pointer, &buffer, buffer.count)
            guard count > 0 else { return "" }
            return String(bytes: buffer.prefix(count).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
        }
    }

    package static func isSymlink(_ url: URL) -> Bool {
        !destination(of: url).isEmpty || {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
        }()
    }

    /// 只替换软链；真实目录不动（可能是未迁的本地直装）
    package static func replaceSymlink(at link: URL, pointingTo dest: URL) throws {
        let fileManager = FileManager.default
        if isSymlink(link) || !destination(of: link).isEmpty {
            try? fileManager.removeItem(at: link)
        } else if fileManager.fileExists(atPath: link.path) {
            return
        }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: dest)
    }

    package static func removeOurSymlink(at link: URL) throws {
        let dest = destination(of: link)
        guard !dest.isEmpty else { return }
        // 相对目标必须按软链所在目录解析——fileURLWithPath 裸解析基于进程 CWD，会误判。
        // 归属只认解析后落在本库/停用区前缀内的；不做子串兜底（"contains(.skill-atlas/skills)"
        // 会把指向 /Volumes/Backup/.skill-atlas/skills-old/x 之类的用户软链也删掉）。
        let target = dest.hasPrefix("/")
            ? URL(fileURLWithPath: dest)
            : URL(fileURLWithPath: dest, relativeTo: link.deletingLastPathComponent())
        let resolved = target.resolvingSymlinksInPath().standardizedFileURL.path
        let library = AtlasPaths.libraryRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let parked = AtlasPaths.disabledRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let ours = resolved == library || resolved.hasPrefix(library + "/")
            || resolved == parked || resolved.hasPrefix(parked + "/")
        if ours { try FileManager.default.removeItem(at: link) }
    }
}

package enum SkillMigrator {
    package static func shouldOffer(hasCCSwitch: Bool) -> Bool {
        let catalog = AtlasCatalog.load()
        return hasCCSwitch && !catalog.migratedFromCCSwitch && !catalog.migrationSkipped
    }

    package static func canMigrate(hasCCSwitch: Bool) -> Bool {
        hasCCSwitch && !AtlasCatalog.load().migratedFromCCSwitch
    }

    package static func canRollback() -> Bool {
        FileManager.default.fileExists(atPath: AtlasPaths.migrationLog.path)
    }

    package static func skip() throws {
        var catalog = AtlasCatalog.load()
        catalog.migrationSkipped = true
        try AtlasCatalog.save(catalog)
    }

    package struct Plan {
        package var total: Int
        package var alreadyInLibrary: Int
        package var toClone: Int
        package var destination: String
    }

    package static func plan() -> Plan {
        let rows = (try? SkillScanner.readSkillRows()) ?? []
        var already = 0
        var toClone = 0
        for row in rows {
            let directory = row.text("directory")
            guard !directory.isEmpty else { continue }
            let dest = AtlasPaths.libraryRoot.appendingPathComponent(directory)
            if FileManager.default.fileExists(atPath: dest.path) {
                already += 1
            } else {
                toClone += 1
            }
        }
        return Plan(
            total: already + toClone,
            alreadyInLibrary: already,
            toClone: toClone,
            destination: AtlasPaths.libraryRoot.path
        )
    }

    package static func migrate(onProgress: @escaping @Sendable (String) -> Void) throws {
        if AtlasCatalog.load().migratedFromCCSwitch {
            onProgress("已经迁出，无需重复迁移")
            return
        }
        let fileManager = FileManager.default
        let hasDB = fileManager.fileExists(atPath: SkillScanner.databaseURL.path)
        guard hasDB else { throw AtlasError(L("没有发现 CC Switch 数据库，无需迁移。")) }

        onProgress("读取 CC Switch（只读）…")
        let rows = try SkillScanner.readSkillRows()
        try fileManager.createDirectory(at: AtlasPaths.libraryRoot, withIntermediateDirectories: true)

        var catalog = AtlasCatalog.load()
        var cloned: [String] = []
        let total = max(1, rows.count)

        for (index, row) in rows.enumerated() {
            let directory = row.text("directory")
            guard !directory.isEmpty else { continue }
            onProgress("克隆 \(directory)（\(index + 1)/\(total)）")
            let source = SkillScanner.sourceRoot.appendingPathComponent(directory)
            let dest = AtlasPaths.libraryRoot.appendingPathComponent(directory)
            if fileManager.fileExists(atPath: dest.path) {
                onProgress("已在库中 \(directory)（\(index + 1)/\(total)），跳过克隆")
            } else if fileManager.fileExists(atPath: source.path) {
                try FileClone.cloneDirectory(from: source, to: dest)
                cloned.append(directory)
            }
            var enabled: [String: Bool] = [:]
            for platform in AgentPlatform.allCases {
                enabled[platform.rawValue] = row.int(platform.dbColumn) != 0
            }
            catalog.skills[directory] = AtlasSkillRecord(
                directory: directory,
                enabled: enabled,
                repoOwner: row.text("repo_owner"),
                repoName: row.text("repo_name"),
                repoBranch: {
                    let branch = row.text("repo_branch")
                    return branch.isEmpty ? "main" : branch
                }(),
                installedAt: row.int("installed_at"),
                updatedAt: row.int("updated_at")
            )
        }

        var links: [MigrationLink] = []
        let previousLog = loadLog()
        func persistLog() {
            let log = MigrationLog(
                createdAt: Int(Date().timeIntervalSince1970),
                links: links,
                cloned: cloned
            )
            try? writeLog(log)
        }

        onProgress("重建平台软链…")
        struct Plan {
            var platform: AgentPlatform
            var directory: String
            var link: URL
            var original: String
            var dest: URL
        }
        var plan: [Plan] = []
        for (directory, record) in catalog.skills {
            let atlasSource = AtlasPaths.libraryRoot.appendingPathComponent(directory)
            guard fileManager.fileExists(atPath: atlasSource.path) else { continue }
            for platform in AgentPlatform.allCases where record.isEnabled(platform) {
                let root = platform.resolvedRoot(home: AtlasPaths.home)
                try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
                let link = root.appendingPathComponent(directory)
                var original = LinkTool.destination(of: link)
                let atlasPrefix = AtlasPaths.libraryRoot.path
                if original.hasPrefix(atlasPrefix),
                   let prior = previousLog?.links.first(where: { $0.linkPath == link.path }) {
                    original = prior.originalTarget
                }
                plan.append(Plan(platform: platform, directory: directory, link: link, original: original, dest: atlasSource))
            }
        }
        for item in plan {
            links.append(MigrationLink(
                platform: item.platform.rawValue,
                linkPath: item.link.path,
                originalTarget: item.original
            ))
            try LinkTool.replaceSymlink(at: item.link, pointingTo: item.dest)
        }
        persistLog()
        guard fileManager.fileExists(atPath: AtlasPaths.migrationLog.path) else {
            throw AtlasError(L("回滚清单写入失败，已中止（软链可能部分改动，请用「撤销迁移」恢复）。"))
        }

        catalog.migratedFromCCSwitch = true
        catalog.migrationSkipped = false
        catalog.migratedAt = Int(Date().timeIntervalSince1970)
        try AtlasCatalog.save(catalog)
        onProgress("完成")
    }

    package static func rollback() throws {
        guard let log = loadLog() else {
            throw AtlasError(LF("找不到回滚清单：%@", AtlasPaths.migrationLog.path))
        }
        let fileManager = FileManager.default
        for item in log.links {
            let link = URL(fileURLWithPath: item.linkPath)
            if item.originalTarget.isEmpty {
                if let attributes = try? fileManager.attributesOfItem(atPath: link.path),
                   (attributes[.type] as? FileAttributeType) == .typeSymbolicLink {
                    try? fileManager.removeItem(at: link)
                }
            } else {
                try LinkTool.replaceSymlink(
                    at: link,
                    pointingTo: URL(fileURLWithPath: item.originalTarget)
                )
            }
        }
        var catalog = AtlasCatalog.load()
        catalog.migratedFromCCSwitch = false
        try AtlasCatalog.save(catalog)
    }

    private static func writeLog(_ log: MigrationLog) throws {
        try FileManager.default.createDirectory(
            at: AtlasPaths.migrationLog.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(log).write(to: AtlasPaths.migrationLog, options: .atomic)
    }

    package static func loadLog() -> MigrationLog? {
        guard let data = try? Data(contentsOf: AtlasPaths.migrationLog) else { return nil }
        return try? JSONDecoder().decode(MigrationLog.self, from: data)
    }

    // MARK: 清理 CC Switch 副本（迁移完成后回收磁盘）
    //
    // 迁移用 clonefile 复制，CC Switch 原目录会留一份副本。清理 = 把已迁入
    // 且校验通过的原目录移入废纸篓。数据库 cc-switch.db 永远不动。
    // 校验三关：已在本库、库内 SKILL.md 可读非空、启用平台的挂载都指进本库。

    package struct CleanupItem: Identifiable {
        package var directory: String
        package var ok: Bool
        package var reason: String
        package var sizeBytes: Int64
        package var id: String { directory }
    }

    /// CC Switch 源目录里是否还留着技能副本（决定设置页是否出清理入口）
    package static func hasSourceLeftovers() -> Bool {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: SkillScanner.sourceRoot.path) else {
            return false
        }
        return names.contains { name in
            guard !name.hasPrefix(".") else { return false }
            var isDir: ObjCBool = false
            let path = SkillScanner.sourceRoot.appendingPathComponent(name).path
            return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    /// 逐目录校验：通过的可清理，不通过的保留并给出原因
    package static func cleanupCandidates() -> [CleanupItem] {
        let fileManager = FileManager.default
        let catalog = AtlasCatalog.load()
        guard catalog.migratedFromCCSwitch else { return [] }
        guard let names = try? fileManager.contentsOfDirectory(atPath: SkillScanner.sourceRoot.path) else {
            return []
        }
        let libraryPrefix = AtlasPaths.libraryRoot.resolvingSymlinksInPath().path
        var items: [CleanupItem] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let source = SkillScanner.sourceRoot.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let size = directorySize(source)

            let library = AtlasPaths.libraryRoot.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: library.path) else {
                items.append(CleanupItem(directory: name, ok: false, reason: L("未迁入本库"), sizeBytes: size))
                continue
            }
            let skillFile = library.appendingPathComponent("SKILL.md")
            let skillSize = (try? fileManager.attributesOfItem(atPath: skillFile.path))?[.size] as? Int64 ?? 0
            guard skillSize > 0, fileManager.isReadableFile(atPath: skillFile.path) else {
                items.append(CleanupItem(directory: name, ok: false, reason: L("库内 SKILL.md 缺失或不可读"), sizeBytes: size))
                continue
            }
            var badLink: String?
            if let record = catalog.skills[name] {
                for platform in AgentPlatform.allCases where record.isEnabled(platform) {
                    let link = platform.resolvedRoot(home: AtlasPaths.home).appendingPathComponent(name)
                    let resolved = link.resolvingSymlinksInPath().path
                    if !fileManager.fileExists(atPath: resolved) {
                        badLink = LF("%@ 挂载缺失", platform.displayName)
                        break
                    }
                    if !resolved.hasPrefix(libraryPrefix + "/") && resolved != libraryPrefix {
                        badLink = LF("%@ 挂载没有指向本库", platform.displayName)
                        break
                    }
                }
            }
            if let badLink {
                items.append(CleanupItem(directory: name, ok: false, reason: badLink, sizeBytes: size))
                continue
            }
            items.append(CleanupItem(directory: name, ok: true, reason: "", sizeBytes: size))
        }
        return items
    }

    /// 把校验通过的原目录移入废纸篓；成功后删除回滚清单（回滚目标已不存在）
    package static func cleanup(_ directories: [String]) throws -> Int {
        let fileManager = FileManager.default
        var trashed = 0
        var failures: [String] = []
        for name in directories {
            let source = SkillScanner.sourceRoot.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            do {
                try fileManager.trashItem(at: source, resultingItemURL: nil)
                trashed += 1
            } catch {
                failures.append(name)
            }
        }
        if trashed > 0 {
            try? fileManager.removeItem(at: AtlasPaths.migrationLog)
        }
        if !failures.isEmpty {
            throw AtlasError(LF("已清理 %d 个；%d 个移入废纸篓失败：%@", trashed, failures.count, failures.prefix(3).joined(separator: "、") + (failures.count > 3 ? "…" : "")))
        }
        return trashed
    }

    package static func directorySize(_ url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [],
            errorHandler: nil
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }
}

package enum SkillActions {
    package static func setPlatform(directory: String, platform: AgentPlatform, enabled: Bool) throws {
        var catalog = AtlasCatalog.load()
        guard var record = catalog.skills[directory] else {
            throw NotFound(directory)
        }
        let source = activeSource(directory: directory)
        let root = platform.resolvedRoot(home: AtlasPaths.home)
        let link = root.appendingPathComponent(directory)
        // 先做链上动作、成功才落 enabled 位——占位是普通目录时明确报错（多半是这技能
        // 在该平台的旧物理拷贝），不静默留下「enabled 但挂载是 .directory」的警告态
        if enabled {
            if !LinkTool.isSymlink(link), FileManager.default.fileExists(atPath: link.path) {
                throw Conflict(LF("%@ 的技能目录里已有同名普通目录「%@」，不会覆盖。若它是这技能的旧拷贝，先手动移除再开启。", platform.displayName, directory))
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try LinkTool.replaceSymlink(at: link, pointingTo: source)
        } else {
            try LinkTool.removeOurSymlink(at: link)
        }
        record.enabled[platform.rawValue] = enabled
        catalog.skills[directory] = record
        try AtlasCatalog.save(catalog)
    }

    /// CLI 退出码 7：目标不在库里
    package struct NotFound: LocalizedError {
        package let directory: String
        package init(_ directory: String) { self.directory = directory }
        package var errorDescription: String? { LF("找不到技能「%@」", directory) }
    }

    /// CLI 退出码 5：占位冲突
    package struct Conflict: LocalizedError {
        package let message: String
        package init(_ message: String) { self.message = message }
        package var errorDescription: String? { message }
    }

    package static func setDisabled(directory: String, disabled: Bool) throws {
        let fileManager = FileManager.default
        let active = AtlasPaths.libraryRoot.appendingPathComponent(directory)
        let parked = AtlasPaths.disabledRoot.appendingPathComponent(directory)
        let from = disabled ? active : parked
        let to = disabled ? parked : active
        guard fileManager.fileExists(atPath: from.path) else {
            throw AtlasError(LF("找不到技能目录「%@」", directory))
        }
        guard !fileManager.fileExists(atPath: to.path) else {
            throw AtlasError(LF("目标位置已有同名目录「%@」，不会覆盖。", directory))
        }
        try fileManager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: from, to: to)

        let record = AtlasCatalog.load().skills[directory]
        for platform in AgentPlatform.allCases {
            let link = platform.resolvedRoot(home: AtlasPaths.home).appendingPathComponent(directory)
            if disabled {
                try LinkTool.removeOurSymlink(at: link)
            } else if record?.isEnabled(platform) == true {
                try LinkTool.replaceSymlink(at: link, pointingTo: to)
            }
        }
    }

    package static func activeSource(directory: String) -> URL {
        let active = AtlasPaths.libraryRoot.appendingPathComponent(directory)
        if FileManager.default.fileExists(atPath: active.path) { return active }
        return AtlasPaths.disabledRoot.appendingPathComponent(directory)
    }

    // MARK: 收编本地直装（散装技能 → 本库接管）
    //
    // 场景：技能直接装在 ~/.claude/skills 等平台根（origin == .local），只能看不能管。
    // 收编三步：① clonefile 拷入 ~/.skill-atlas/skills/<dir>；② 写 catalog，
    // enabled = 扫描发现它所在的各平台；③ 原散装入口替换成指向本库的软链。
    // ③ 必须做：留普通目录的话，重扫后挂载状态是 .directory 警告态，且安装流程的
    // 「已存在同名目录，跳过」「建链时 fileExists 即跳过」也会永远绕开它。
    // 不写 migration.json——那是 CC Switch 迁移的回滚清单；收编写进去会让从未用过
    // CC Switch 的用户凭空出现「撤销迁移」入口。收编后的反向操作走常规卸载。
    package static func adoptLocal(skill: Skill) throws {
        guard skill.origin == .local else {
            throw AtlasError(LF("「%@」不是本地直装技能，无需收编。", skill.name))
        }
        guard !skill.disabled else {
            throw AtlasError(LF("「%@」已停用。先恢复，再收进本库。", skill.name))
        }
        let fileManager = FileManager.default
        let directory = skill.directory
        let source = URL(fileURLWithPath: skill.sourcePath, isDirectory: true)
        let sourceReal = source.resolvingSymlinksInPath().standardizedFileURL.path
        guard fileManager.fileExists(atPath: source.path) else {
            throw AtlasError(LF("找不到源目录：%@", source.path))
        }
        let dest = AtlasPaths.libraryRoot.appendingPathComponent(directory)
        guard !fileManager.fileExists(atPath: dest.path) else {
            throw AtlasError(LF("本库已有同名目录「%@」，不会覆盖。先处理库内同名目录再收编。", directory))
        }

        // ① 拷入本库。clonefile 已校验目标存在；SKILL.md 再核一遍，防半拉子拷贝后删源
        try FileClone.cloneDirectory(from: source, to: dest)
        if fileManager.fileExists(atPath: source.appendingPathComponent("SKILL.md").path),
           !fileManager.fileExists(atPath: dest.appendingPathComponent("SKILL.md").path) {
            try? fileManager.removeItem(at: dest)
            throw AtlasError(LF("拷贝校验失败：库内 %@/SKILL.md 缺失，已回退收编。", directory))
        }

        // ② 写 catalog：enabled = 它现在实际所在的平台（platforms 来自 scanLocalSkills）
        var enabled: [String: Bool] = [:]
        for platform in AgentPlatform.allCases {
            enabled[platform.rawValue] = skill.platforms.contains(platform.label)
        }
        let now = Int(Date().timeIntervalSince1970)
        try AtlasCatalog.upsert(AtlasSkillRecord(
            directory: directory,
            enabled: enabled,
            repoOwner: "",
            repoName: "",
            repoBranch: "main",
            installedAt: skill.installedAt != 0 ? skill.installedAt : now,
            updatedAt: now
        ))

        // ③ 各平台入口换成指向本库的软链。散装入口可能是真实目录（就是刚拷的源）
        //    或指向任意开发目录的软链；真实目录只删 resolve 后确为本次源的，防同名异物。
        for platform in AgentPlatform.allCases where enabled[platform.rawValue] == true {
            let root = platform.resolvedRoot(home: AtlasPaths.home)
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let link = root.appendingPathComponent(directory)
            if LinkTool.isSymlink(link) {
                try LinkTool.replaceSymlink(at: link, pointingTo: dest)
            } else if fileManager.fileExists(atPath: link.path) {
                let real = link.resolvingSymlinksInPath().standardizedFileURL.path
                guard real == sourceReal else { continue }
                try fileManager.removeItem(at: link)
                try fileManager.createSymbolicLink(at: link, withDestinationURL: dest)
            } else {
                try fileManager.createSymbolicLink(at: link, withDestinationURL: dest)
            }
        }
    }

    /// 技能实体是否在所有平台技能根之外（散装入口是指向开发目录/CC 源等处的软链）。
    /// 这类技能收编 = 拷贝快照：之后编辑原目录不再对平台生效，收编前要提醒。
    package static func isExternalSource(_ skill: Skill) -> Bool {
        let real = URL(fileURLWithPath: skill.sourcePath, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL.path
        for platform in AgentPlatform.allCases {
            let root = platform.resolvedRoot(home: AtlasPaths.home).standardizedFileURL.path
            if real == root || real.hasPrefix(root + "/") { return false }
        }
        return true
    }

    /// 卸载：先移走本应用建的平台软链。
    /// trashLibrary = false 只摘挂载，库内目录与记录保留（全部平台标为关闭）。
    /// trashLibrary = true 再把源目录移入废纸篓（可还原），并去掉库记录。
    /// CC Switch 原目录永不删除。
    package static func uninstall(skill: Skill, trashLibrary: Bool) throws {
        guard skill.origin != .ccSwitch else {
            throw AtlasError(LF("「%@」由 CC Switch 管理。先执行迁移，再在这里卸载。", skill.name))
        }
        let fileManager = FileManager.default
        let source = URL(fileURLWithPath: skill.sourcePath, isDirectory: true)
        let sourceReal = source.resolvingSymlinksInPath().standardizedFileURL.path

        for platform in AgentPlatform.allCases {
            let link = platform.resolvedRoot(home: AtlasPaths.home).appendingPathComponent(skill.directory)
            if skill.origin == .atlas {
                try LinkTool.removeOurSymlink(at: link)
            } else {
                let dest = LinkTool.destination(of: link)
                if !dest.isEmpty,
                   URL(fileURLWithPath: dest).resolvingSymlinksInPath().standardizedFileURL.path == sourceReal {
                    try? fileManager.removeItem(at: link)
                }
            }
        }

        if skill.origin == .atlas {
            var catalog = AtlasCatalog.load()
            if trashLibrary {
                catalog.skills.removeValue(forKey: skill.directory)
            } else if var record = catalog.skills[skill.directory] {
                for platform in AgentPlatform.allCases {
                    record.enabled[platform.rawValue] = false
                }
                catalog.skills[skill.directory] = record
            }
            try AtlasCatalog.save(catalog)
        }

        if trashLibrary, fileManager.fileExists(atPath: source.path) {
            try SkillBackup.snapshot(source: source, directory: skill.directory)
            try fileManager.trashItem(at: source, resultingItemURL: nil)
        }
    }

    // MARK: 带保护的更新（G1）
    //
    // 顺序固定：① 全量备份 → ② 本地 tracked 改动导出补丁并还原工作区 →
    // ③ git pull --ff-only → ④ git apply --check 通过才重放补丁。
    // 重放不干净时保持纯上游状态——绝不留冲突标记；本地版本三处可寻：
    // 备份（可回滚）、补丁文件（可审计）、报告文案（明说没重放）。
    // untracked 新文件 pull 本就不动，不进补丁流程。
    package struct UpdateApplyResult {
        package var dirtyFiles: [String]
        package var patchFile: String?
        /// 本地补丁是否已重放回工作区（false = 补丁存档但未重放）
        package var replayed: Bool
        package var backupName: String
    }

    package static func applyUpdate(skill: Skill) throws -> UpdateApplyResult {
        guard skill.origin == .atlas else {
            throw AtlasError(LF("「%@」不由本库管理，不能在这里更新。", skill.name))
        }
        let source = URL(fileURLWithPath: skill.sourcePath, isDirectory: true)
        let dirty = SkillGit.localChanges(source: source)
        let backupName = try SkillBackup.snapshot(source: source, directory: skill.directory)

        var patchFile: String? = nil
        let trackedPatch = SkillGit.trackedDiff(source: source)
        if !trackedPatch.isEmpty {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: AtlasPaths.patchesRoot, withIntermediateDirectories: true)
            let url = AtlasPaths.patchesRoot.appendingPathComponent("\(backupName).patch")
            let header = dirty.map { "# \($0)" }.joined(separator: "\n")
            try "# Skill Atlas 更新前本地改动（\(skill.directory)）\n\(header)\n\(trackedPatch)\n"
                .write(to: url, atomically: true, encoding: .utf8)
            patchFile = url.path
            SkillGit.discardTracked(source: source)
        }

        do {
            try SkillGit.pullFF(source: source)
        } catch {
            // pull 失败则把刚还原的本地改动补回去，保持更新前原状；
            // 补不回去必须明说（此时工作区没有本地改动，只有备份和补丁文件里有）
            if patchFile != nil, !SkillGit.applyPatch(source: source, diff: trackedPatch) {
                throw AtlasError(LF(
                    "快进更新失败，且本地改动未能自动恢复到工作区。完整快照在备份 %@，补丁在 skill-patches。原始错误：%@",
                    backupName, error.localizedDescription
                ))
            }
            throw error
        }

        var replayed = true
        if patchFile != nil {
            replayed = SkillGit.applyPatch(source: source, diff: trackedPatch)
        }
        return UpdateApplyResult(
            dirtyFiles: dirty, patchFile: patchFile, replayed: replayed, backupName: backupName
        )
    }

    /// 回滚到最近一次备份（更新前/卸载前快照同源）。
    /// 先给当前状态拍快照再换装，回滚本身可再回滚；临时目录就位校验后才动源目录。
    package static func rollback(skill: Skill) throws -> String {
        guard skill.origin == .atlas else {
            throw AtlasError(LF("「%@」不由本库管理，不能回滚。", skill.name))
        }
        guard let backup = SkillBackup.latest(directory: skill.directory) else {
            throw AtlasError(LF("「%@」没有可用备份。", skill.name))
        }
        let fileManager = FileManager.default
        let source = URL(fileURLWithPath: skill.sourcePath, isDirectory: true)
        let staging = source.deletingLastPathComponent()
            .appendingPathComponent(".\(skill.directory).rollback-tmp")
        if fileManager.fileExists(atPath: staging.path) { try? fileManager.removeItem(at: staging) }
        do {
            try FileClone.cloneDirectory(from: backup, to: staging)
        } catch {
            try? fileManager.removeItem(at: staging)
            try fileManager.copyItem(at: backup, to: staging)
        }
        guard fileManager.fileExists(atPath: staging.appendingPathComponent("SKILL.md").path) else {
            try? fileManager.removeItem(at: staging)
            throw AtlasError(LF("备份 %@ 校验失败（SKILL.md 缺失），已放弃回滚。", backup.lastPathComponent))
        }
        _ = try SkillBackup.snapshot(source: source, directory: skill.directory)
        // 换装用「移开而非删除」：staging 就位失败时把原目录移回去，任何一步失败都不留空洞
        let displaced = source.deletingLastPathComponent()
            .appendingPathComponent(".\(skill.directory).pre-rollback")
        if fileManager.fileExists(atPath: displaced.path) { try? fileManager.removeItem(at: displaced) }
        try fileManager.moveItem(at: source, to: displaced)
        do {
            try fileManager.moveItem(at: staging, to: source)
        } catch {
            try? fileManager.moveItem(at: displaced, to: source)
            try? fileManager.removeItem(at: staging)
            throw error
        }
        try? fileManager.removeItem(at: displaced)
        return backup.lastPathComponent
    }
}

package enum SkillBackup {
    package static let keep = 20

    /// 卸载/更新/回滚前备份到 ~/.skill-atlas/skill-backups/，保留最近 20 个。
    /// 返回备份目录名（<directory>-yyyyMMdd-HHmmss），补丁文件与其同名配对。
    @discardableResult
    package static func snapshot(source: URL, directory: String) throws -> String {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: AtlasPaths.backupsRoot, withIntermediateDirectories: true)
        // 备份戳只有秒级精度；同秒二次备份必须换名——cloneDirectory 对已存在目标
        // 静默跳过，同名会让「更新后马上回滚」丢掉当前状态的快照（回滚不可再回滚）。
        let stamp = backupStamp.string(from: Date())
        var name = "\(directory)-\(stamp)"
        var sequence = 2
        while fileManager.fileExists(atPath: AtlasPaths.backupsRoot.appendingPathComponent(name).path) {
            name = "\(directory)-\(stamp)-\(sequence)"
            sequence += 1
        }
        let dest = AtlasPaths.backupsRoot.appendingPathComponent(name)
        do {
            try FileClone.cloneDirectory(from: source, to: dest)
        } catch {
            if fileManager.fileExists(atPath: dest.path) { try? fileManager.removeItem(at: dest) }
            try fileManager.copyItem(at: source, to: dest)
        }
        prune()
        return dest.lastPathComponent
    }

    /// 该技能最近一次备份（yyyyMMdd-HHmmss 时间戳 + 可选同秒序号 -n，字典序即时间序）。
    /// 目录名本身可含连字符，所以校验后缀格式而不是简单前缀切分。
    package static func latest(directory: String) -> URL? {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: AtlasPaths.backupsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        let prefix = directory + "-"
        return entries.filter { url in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix) else { return false }
            let rest = name.dropFirst(prefix.count)
            let stamp = rest.prefix(15)
            guard stamp.count == 15, stamp.dropFirst(8).first == "-",
                  stamp.allSatisfy({ $0.isNumber || $0 == "-" }) else { return false }
            let suffix = rest.dropFirst(15)
            return suffix.isEmpty
                || (suffix.first == "-" && suffix.count >= 2 && suffix.dropFirst().allSatisfy(\.isNumber))
        }
        .max { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static let backupStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    package static func prune() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: AtlasPaths.backupsRoot,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let ranked = entries.compactMap { url -> (URL, Date)? in
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            return (url, date)
        }
        .sorted { $0.1 > $1.1 }
        for extra in ranked.dropFirst(keep) {
            try? fileManager.removeItem(at: extra.0)
        }
    }
}

package enum SkillGit {
    package struct Status {
        package var available: Bool
        package var detail: String
    }

    package static func check(source: URL, branch: String) -> Status {
        let gitDir = source.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            return Status(available: false, detail: "无 git")
        }
        let fetch = run(["fetch", "origin"], in: source)
        guard fetch.status == 0 else {
            return Status(available: false, detail: "fetch 失败")
        }
        let head = run(["rev-parse", "HEAD"], in: source).stdout
        let remote = run(["rev-parse", "origin/\(branch)"], in: source).stdout
        guard !head.isEmpty, !remote.isEmpty else {
            return Status(available: false, detail: "无法比较")
        }
        if head == remote {
            return Status(available: false, detail: "已最新")
        }
        return Status(available: true, detail: "可更新")
    }

    /// 更新前 diff 预览：--stat 概览 + SKILL.md 全文 diff（合规场景：技能文本变更 = 行为变更）
    package static func upstreamDiff(source: URL, branch: String) -> (stat: String, skillDiff: String) {
        _ = run(["fetch", "origin"], in: source)
        let range = "HEAD..origin/\(branch)"
        let stat = run(["diff", "--stat", range], in: source).stdout
        var skillDiff = run(["diff", range, "--", "SKILL.md"], in: source).stdout
        if skillDiff.isEmpty {
            // SKILL.md 没变时给全量 diff（截断到 400 行防爆）
            let full = run(["diff", range], in: source).stdout
            skillDiff = full.split(separator: "\n").prefix(400).joined(separator: "\n")
        }
        return (stat, skillDiff)
    }

    package static func pullFF(source: URL) throws {
        let result = run(["pull", "--ff-only"], in: source)
        guard result.status == 0 else {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw AtlasError(LF("快进更新失败：%@", detail.isEmpty ? L("git pull --ff-only 未成功") : detail))
        }
    }

    /// 本地改动清单（git status --porcelain；含 untracked）。空数组 = 工作区干净。
    package static func localChanges(source: URL) -> [String] {
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent(".git").path) else { return [] }
        let result = run(["status", "--porcelain"], in: source)
        guard result.status == 0, !result.stdout.isEmpty else { return [] }
        return result.stdout.split(separator: "\n").map(String.init)
    }

    /// tracked 文件的本地未提交改动（更新前导出为补丁）。
    /// 必须走 raw 输出：run() 的 trim 会剪掉 diff 末尾的空白上下文行，让补丁 corrupt。
    package static func trackedDiff(source: URL) -> String {
        run(["diff"], in: source, trimStdout: false).stdout
    }

    /// 丢弃 tracked 文件的工作区改动（调用前必须已备份 + 已导出补丁）
    package static func discardTracked(source: URL) {
        _ = run(["checkout", "--", "."], in: source)
    }

    /// 把补丁重放回工作区：--check 预检通过才真正 apply，绝不留冲突标记。
    /// run() 的输出统一 trim 过，diff 末尾换行会被剪掉——git apply 会判 corrupt，必须补回。
    package static func applyPatch(source: URL, diff: String) -> Bool {
        guard !diff.isEmpty else { return true }
        let content = diff.hasSuffix("\n") ? diff : diff + "\n"
        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory
            .appendingPathComponent("skill-atlas-replay-\(UUID().uuidString).patch")
        defer { try? fileManager.removeItem(at: temp) }
        guard (try? content.write(to: temp, atomically: true, encoding: .utf8)) != nil else { return false }
        guard run(["apply", "--check", temp.path], in: source).status == 0 else { return false }
        return run(["apply", temp.path], in: source).status == 0
    }

    private static func run(
        _ arguments: [String], in directory: URL, trimStdout: Bool = true
    ) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, "", error.localizedDescription)
        }
        func read(_ pipe: Pipe, trim: Bool) -> String {
            let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return trim ? text.trimmingCharacters(in: .whitespacesAndNewlines) : text
        }
        return (process.terminationStatus, read(out, trim: trimStdout), read(err, trim: true))
    }
}
