import Foundation
import SQLite3

/// 技能快照索盘。对照 skills-hub 的 `skill_store`：真源仍是 ~/.skill-atlas/skills，
/// UI 与二次扫描读 SQLite，不再每次把全部 SKILL.md 读一遍。
///
/// 这是缓存，坏了就当 miss——下一次全量解析会重写。禁止在这里存意图
/// （enabled / 软链归属），那些仍只活在 atlas.json。
package enum SkillIndex {
    package struct Entry {
        package var cacheKey: String
        package var directory: String
        package var origin: SkillOrigin
        package var sourcePath: String
        package var skillFile: String
        package var mtime: Int
        package var size: Int
        package var disabled: Bool
        package var skill: Skill
    }

    package struct ScanOptions: Sendable {
        package var discoverLocals: Bool
        package static let full = ScanOptions(discoverLocals: true)
        package static let reconcile = ScanOptions(discoverLocals: false)
        package init(discoverLocals: Bool) { self.discoverLocals = discoverLocals }
    }

    package static func cacheKey(origin: SkillOrigin, directory: String) -> String {
        "\(origin.rawValue):\(directory)"
    }

    package static func fileStamp(_ url: URL) -> (mtime: Int, size: Int) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = Int((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        let size = (attributes?[.size] as? Int) ?? 0
        return (mtime, size)
    }

    /// 内容没变就可以复用这条：SKILL.md 的 (mtime, size) + 源路径 + 是否停用。
    package static func contentMatches(_ entry: Entry, skillFile: URL, sourcePath: String, disabled: Bool) -> Bool {
        guard entry.sourcePath == sourcePath, entry.disabled == disabled else { return false }
        let stamp = fileStamp(skillFile)
        return entry.mtime == stamp.mtime && entry.size == stamp.size
    }

    package static func loadEntries() -> [String: Entry] {
        guard FileManager.default.fileExists(atPath: AtlasPaths.skillIndexURL.path) else { return [:] }
        return (try? withConnection(readonly: true) { conn in
            var statement: OpaquePointer?
            let sql = "SELECT cache_key, directory, origin, source_path, skill_file, skill_mtime, skill_size, disabled, payload FROM skills"
            guard sqlite3_prepare_v2(conn, sql, -1, &statement, nil) == SQLITE_OK else { return [:] }
            defer { sqlite3_finalize(statement) }
            var result: [String: Entry] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let entry = decodeRow(statement) else { continue }
                result[entry.cacheKey] = entry
            }
            return result
        }) ?? [:]
    }

    /// 上一轮完整扫描结果，给 App 首帧立刻画表。挂载态可能过期，随后对账会纠正。
    package static func hydrate() -> AtlasData? {
        guard FileManager.default.fileExists(atPath: AtlasPaths.skillIndexURL.path) else { return nil }
        return try? withConnection(readonly: true) { conn in
            var statement: OpaquePointer?
            let sql = "SELECT payload FROM snapshot WHERE id = 1"
            guard sqlite3_prepare_v2(conn, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let bytes = sqlite3_column_blob(statement, 0) else { return nil }
            let length = Int(sqlite3_column_bytes(statement, 0))
            let data = Data(bytes: bytes, count: length)
            return try? JSONDecoder().decode(AtlasData.self, from: data)
        }
    }

    package static func save(entries: [Entry], snapshot: AtlasData) {
        try? FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        try? withConnection(readonly: false) { conn in
            sqlite3_exec(conn, "BEGIN IMMEDIATE", nil, nil, nil)
            sqlite3_exec(conn, "DELETE FROM skills", nil, nil, nil)
            let insert = "INSERT INTO skills(cache_key, directory, origin, source_path, skill_file, skill_mtime, skill_size, disabled, payload) VALUES(?,?,?,?,?,?,?,?,?)"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(conn, insert, -1, &statement, nil) == SQLITE_OK else {
                sqlite3_exec(conn, "ROLLBACK", nil, nil, nil)
                return
            }
            defer { sqlite3_finalize(statement) }
            let encoder = JSONEncoder()
            for entry in entries {
                guard let payload = try? encoder.encode(entry.skill) else { continue }
                bindText(statement, 1, entry.cacheKey)
                bindText(statement, 2, entry.directory)
                bindText(statement, 3, entry.origin.rawValue)
                bindText(statement, 4, entry.sourcePath)
                bindText(statement, 5, entry.skillFile)
                sqlite3_bind_int64(statement, 6, Int64(entry.mtime))
                sqlite3_bind_int64(statement, 7, Int64(entry.size))
                sqlite3_bind_int64(statement, 8, entry.disabled ? 1 : 0)
                _ = payload.withUnsafeBytes { raw in
                    sqlite3_bind_blob(statement, 9, raw.baseAddress, Int32(payload.count), SQLITE_TRANSIENT)
                }
                if sqlite3_step(statement) != SQLITE_DONE {
                    sqlite3_exec(conn, "ROLLBACK", nil, nil, nil)
                    return
                }
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
            }

            guard let snap = try? encoder.encode(snapshot) else {
                sqlite3_exec(conn, "ROLLBACK", nil, nil, nil)
                return
            }
            sqlite3_exec(conn, "DELETE FROM snapshot", nil, nil, nil)
            var snapStmt: OpaquePointer?
            let snapSQL = "INSERT INTO snapshot(id, payload, saved_at) VALUES(1, ?, ?)"
            guard sqlite3_prepare_v2(conn, snapSQL, -1, &snapStmt, nil) == SQLITE_OK else {
                sqlite3_exec(conn, "ROLLBACK", nil, nil, nil)
                return
            }
            defer { sqlite3_finalize(snapStmt) }
            _ = snap.withUnsafeBytes { raw in
                sqlite3_bind_blob(snapStmt, 1, raw.baseAddress, Int32(snap.count), SQLITE_TRANSIENT)
            }
            sqlite3_bind_int64(snapStmt, 2, Int64(Date().timeIntervalSince1970))
            guard sqlite3_step(snapStmt) == SQLITE_DONE else {
                sqlite3_exec(conn, "ROLLBACK", nil, nil, nil)
                return
            }
            sqlite3_exec(conn, "COMMIT", nil, nil, nil)
        }
    }

    // MARK: - SQLite

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func withConnection<T>(readonly: Bool, _ body: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        let flags = readonly
            ? SQLITE_OPEN_READONLY
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(AtlasPaths.skillIndexURL.path, &database, flags, nil) == SQLITE_OK,
              let conn = database else {
            sqlite3_close(database)
            throw AtlasError("无法打开技能索盘")
        }
        defer { sqlite3_close(conn) }
        if !readonly {
            sqlite3_exec(conn, "PRAGMA journal_mode=WAL", nil, nil, nil)
            sqlite3_exec(conn, "PRAGMA synchronous=NORMAL", nil, nil, nil)
            try ensureSchema(conn)
        }
        return try body(conn)
    }

    private static func ensureSchema(_ conn: OpaquePointer) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS skills (
          cache_key TEXT PRIMARY KEY,
          directory TEXT NOT NULL,
          origin TEXT NOT NULL,
          source_path TEXT NOT NULL,
          skill_file TEXT NOT NULL,
          skill_mtime INTEGER NOT NULL,
          skill_size INTEGER NOT NULL,
          disabled INTEGER NOT NULL,
          payload BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS snapshot (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          payload BLOB NOT NULL,
          saved_at INTEGER NOT NULL
        );
        """
        guard sqlite3_exec(conn, sql, nil, nil, nil) == SQLITE_OK else {
            throw AtlasError("无法初始化技能索盘")
        }
    }

    private static func decodeRow(_ statement: OpaquePointer?) -> Entry? {
        guard let statement else { return nil }
        func text(_ index: Int32) -> String {
            guard let pointer = sqlite3_column_text(statement, index) else { return "" }
            return String(cString: pointer)
        }
        guard let origin = SkillOrigin(rawValue: text(2)),
              let bytes = sqlite3_column_blob(statement, 8) else { return nil }
        let length = Int(sqlite3_column_bytes(statement, 8))
        let data = Data(bytes: bytes, count: length)
        guard let skill = try? JSONDecoder().decode(Skill.self, from: data) else { return nil }
        return Entry(
            cacheKey: text(0),
            directory: text(1),
            origin: origin,
            sourcePath: text(3),
            skillFile: text(4),
            mtime: Int(sqlite3_column_int64(statement, 5)),
            size: Int(sqlite3_column_int64(statement, 6)),
            disabled: sqlite3_column_int64(statement, 7) != 0,
            skill: skill
        )
    }

    private static func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }
}
