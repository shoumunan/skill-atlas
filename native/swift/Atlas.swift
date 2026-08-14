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
// 启动时若 Application Support 里还有旧 atlas.json，一次性搬进来后删除。
// 禁止写入 CC Switch 的数据库和 ~/.cc-switch/skills 原目录。

struct AtlasError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum AgentPlatform: String, CaseIterable, Identifiable, Codable {
    case claude, codex, gemini, opencode, hermes, grokbuild

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .opencode: return "OpenCode"
        case .hermes: return "Hermes"
        case .grokbuild: return "GrokBuild"
        }
    }

    var dbColumn: String { "enabled_\(rawValue)" }

    func root(home: URL) -> URL {
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
        }
    }

    /// 写软链的真实目录：根本身是软链时（~/.claude/skills → ~/.mirasim/skills）先 resolve
    func resolvedRoot(home: URL) -> URL {
        let raw = root(home: home)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: raw.path, isDirectory: &isDir) {
            return raw.resolvingSymlinksInPath()
        }
        return raw
    }
}

enum AtlasPaths {
    static var home: URL { SkillScanner.home }

    static var root: URL {
        home.appendingPathComponent(".skill-atlas")
    }

    static var libraryRoot: URL {
        root.appendingPathComponent("skills")
    }

    static var disabledRoot: URL {
        libraryRoot.appendingPathComponent(".disabled")
    }

    static var backupsRoot: URL {
        root.appendingPathComponent("skill-backups")
    }

    static var migrationLog: URL {
        root.appendingPathComponent("migration.json")
    }

    static var catalogURL: URL {
        root.appendingPathComponent("atlas.json")
    }

    static var usageIndexURL: URL {
        root.appendingPathComponent("usage-index.json")
    }

    static var legacySupportDir: URL {
        home.appendingPathComponent("Library/Application Support/Skill Atlas")
    }

    static var legacyCatalogURL: URL {
        legacySupportDir.appendingPathComponent("atlas.json")
    }

    static var legacyUsageIndexURL: URL {
        legacySupportDir.appendingPathComponent("usage-index.json")
    }
}

struct AtlasSkillRecord: Codable, Equatable {
    var directory: String
    var enabled: [String: Bool]
    var repoOwner: String
    var repoName: String
    var repoBranch: String
    var installedAt: Int
    var updatedAt: Int

    func isEnabled(_ platform: AgentPlatform) -> Bool {
        enabled[platform.rawValue] ?? false
    }

    var repoDisplay: String {
        let owner = repoOwner.trimmingCharacters(in: .whitespaces)
        let name = repoName.trimmingCharacters(in: .whitespaces)
        if owner.isEmpty || name.isEmpty { return "Skill Atlas" }
        return "\(owner)/\(name)"
    }
}

struct AtlasCatalogFile: Codable {
    var version: Int = 1
    var migratedFromCCSwitch: Bool = false
    var migrationSkipped: Bool = false
    var migratedAt: Int?
    var skills: [String: AtlasSkillRecord] = [:]
}

enum AtlasCatalog {
    static func load() -> AtlasCatalogFile {
        migrateLegacyIfNeeded()
        guard let data = try? Data(contentsOf: AtlasPaths.catalogURL),
              let file = try? JSONDecoder().decode(AtlasCatalogFile.self, from: data) else {
            return AtlasCatalogFile()
        }
        return file
    }

    static func save(_ file: AtlasCatalogFile) throws {
        try FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: AtlasPaths.catalogURL, options: .atomic)
    }

    static func upsert(_ record: AtlasSkillRecord) throws {
        var file = load()
        file.skills[record.directory] = record
        try save(file)
    }

    /// 旧版写在 Application Support。一次性搬进 ~/.skill-atlas/ 后删除旧文件。
    static func migrateLegacyIfNeeded() {
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

struct MigrationLink: Codable {
    var platform: String
    var linkPath: String
    var originalTarget: String
}

struct MigrationLog: Codable {
    var createdAt: Int
    var links: [MigrationLink]
    var cloned: [String]
}

enum FileClone {
    /// APFS clonefile（`cp -cR`）。目标已存在则跳过。失败不回退成普通拷贝。
    static func cloneDirectory(from: URL, to: URL) throws {
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

enum LinkTool {
    static func destination(of url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else { return "" }
            var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
            let count = readlink(pointer, &buffer, buffer.count)
            guard count > 0 else { return "" }
            return String(bytes: buffer.prefix(count).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
        }
    }

    static func isSymlink(_ url: URL) -> Bool {
        !destination(of: url).isEmpty || {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
        }()
    }

    /// 只替换软链；真实目录不动（可能是未迁的本地直装）
    static func replaceSymlink(at link: URL, pointingTo dest: URL) throws {
        let fileManager = FileManager.default
        if isSymlink(link) || !destination(of: link).isEmpty {
            try? fileManager.removeItem(at: link)
        } else if fileManager.fileExists(atPath: link.path) {
            return
        }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: dest)
    }

    static func removeOurSymlink(at link: URL) throws {
        let dest = destination(of: link)
        guard !dest.isEmpty else { return }
        let resolved = URL(fileURLWithPath: dest).resolvingSymlinksInPath().standardizedFileURL.path
        let library = AtlasPaths.libraryRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let parked = AtlasPaths.disabledRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let ours = resolved == library || resolved.hasPrefix(library + "/")
            || resolved == parked || resolved.hasPrefix(parked + "/")
            || dest.contains(".skill-atlas/skills")
        if ours { try FileManager.default.removeItem(at: link) }
    }
}

enum SkillMigrator {
    static func shouldOffer(hasCCSwitch: Bool) -> Bool {
        let catalog = AtlasCatalog.load()
        return hasCCSwitch && !catalog.migratedFromCCSwitch && !catalog.migrationSkipped
    }

    static func canMigrate(hasCCSwitch: Bool) -> Bool {
        hasCCSwitch && !AtlasCatalog.load().migratedFromCCSwitch
    }

    static func canRollback() -> Bool {
        FileManager.default.fileExists(atPath: AtlasPaths.migrationLog.path)
    }

    static func skip() throws {
        var catalog = AtlasCatalog.load()
        catalog.migrationSkipped = true
        try AtlasCatalog.save(catalog)
    }

    struct Plan {
        var total: Int
        var alreadyInLibrary: Int
        var toClone: Int
        var destination: String
    }

    static func plan() -> Plan {
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

    static func migrate(onProgress: @escaping @Sendable (String) -> Void) throws {
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

    static func rollback() throws {
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

    static func loadLog() -> MigrationLog? {
        guard let data = try? Data(contentsOf: AtlasPaths.migrationLog) else { return nil }
        return try? JSONDecoder().decode(MigrationLog.self, from: data)
    }

    // MARK: 清理 CC Switch 副本（迁移完成后回收磁盘）
    //
    // 迁移用 clonefile 复制，CC Switch 原目录会留一份副本。清理 = 把已迁入
    // 且校验通过的原目录移入废纸篓。数据库 cc-switch.db 永远不动。
    // 校验三关：已在本库、库内 SKILL.md 可读非空、启用平台的挂载都指进本库。

    struct CleanupItem: Identifiable {
        var directory: String
        var ok: Bool
        var reason: String
        var sizeBytes: Int64
        var id: String { directory }
    }

    /// CC Switch 源目录里是否还留着技能副本（决定设置页是否出清理入口）
    static func hasSourceLeftovers() -> Bool {
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
    static func cleanupCandidates() -> [CleanupItem] {
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
    static func cleanup(_ directories: [String]) throws -> Int {
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

    static func directorySize(_ url: URL) -> Int64 {
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

enum SkillActions {
    static func setPlatform(directory: String, platform: AgentPlatform, enabled: Bool) throws {
        var catalog = AtlasCatalog.load()
        guard var record = catalog.skills[directory] else {
            throw AtlasError(LF("「%@」不在 Skill Atlas 库中", directory))
        }
        record.enabled[platform.rawValue] = enabled
        catalog.skills[directory] = record
        try AtlasCatalog.save(catalog)

        let source = activeSource(directory: directory)
        let root = platform.resolvedRoot(home: AtlasPaths.home)
        let link = root.appendingPathComponent(directory)
        if enabled {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try LinkTool.replaceSymlink(at: link, pointingTo: source)
        } else {
            try LinkTool.removeOurSymlink(at: link)
        }
    }

    static func setDisabled(directory: String, disabled: Bool) throws {
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

    static func activeSource(directory: String) -> URL {
        let active = AtlasPaths.libraryRoot.appendingPathComponent(directory)
        if FileManager.default.fileExists(atPath: active.path) { return active }
        return AtlasPaths.disabledRoot.appendingPathComponent(directory)
    }

    /// 卸载：先移走本应用建的平台软链。
    /// trashLibrary = false 只摘挂载，库内目录与记录保留（全部平台标为关闭）。
    /// trashLibrary = true 再把源目录移入废纸篓（可还原），并去掉库记录。
    /// CC Switch 原目录永不删除。
    static func uninstall(skill: Skill, trashLibrary: Bool) throws {
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
}

enum SkillBackup {
    static let keep = 20

    /// 卸载前备份到 ~/.skill-atlas/skill-backups/，保留最近 20 个。
    static func snapshot(source: URL, directory: String) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: AtlasPaths.backupsRoot, withIntermediateDirectories: true)
        let stamp = backupStamp.string(from: Date())
        let dest = AtlasPaths.backupsRoot.appendingPathComponent("\(directory)-\(stamp)")
        do {
            try FileClone.cloneDirectory(from: source, to: dest)
        } catch {
            if fileManager.fileExists(atPath: dest.path) { try? fileManager.removeItem(at: dest) }
            try fileManager.copyItem(at: source, to: dest)
        }
        prune()
    }

    private static let backupStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    static func prune() {
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

enum SkillGit {
    struct Status {
        var available: Bool
        var detail: String
    }

    static func check(source: URL, branch: String) -> Status {
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
    static func upstreamDiff(source: URL, branch: String) -> (stat: String, skillDiff: String) {
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

    static func pullFF(source: URL) throws {
        let result = run(["pull", "--ff-only"], in: source)
        guard result.status == 0 else {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw AtlasError(LF("快进更新失败：%@", detail.isEmpty ? L("git pull --ff-only 未成功") : detail))
        }
    }

    private static func run(_ arguments: [String], in directory: URL) -> (status: Int32, stdout: String, stderr: String) {
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
        func read(_ pipe: Pipe) -> String {
            String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return (process.terminationStatus, read(out), read(err))
    }
}
