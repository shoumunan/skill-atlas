import AppKit
import Foundation

// MARK: - 产出物回链（二期 F4）
//
// Filing 规则「一任务一目录」（projects/<体裁>/<YYYYMMDD_主题>/）让回链几乎零成本：
// 体裁 ← SkillLauncher.genreMap 反查，目录名自带日期与主题。
// 只读扫描、详情页展示最近 5 次、点击 open、一键重跑上次主题。

struct OutputRecord: Identifiable, Sendable {
    var directory: URL
    /// 目录名里的日期（yyyyMMdd）
    var dateText: String
    var topic: String
    /// 目录里的文件数（浅层）
    var fileCount: Int
    /// 最新交付物文件名（docx/pdf/pptx/html/md 优先）
    var latestDeliverable: String?

    var id: String { directory.path }
}

@MainActor
enum OutputLinker {
    /// 扫描结果缓存：key = 体裁目录路径，stamp = (目录 mtime, 顶层目录名清单)。
    /// 选中切换/方向键浏览命中缓存就不再打盘；真正扫盘放后台线程，
    /// 主线程只做一次 contentsOfDirectory + 一次 mtime（可承受）。
    private static var cache: [String: (stamp: (Date, [String]), records: [OutputRecord])] = [:]

    /// 技能的最近产出（按目录名日期降序，最多 limit 条）
    static func recentOutputs(for skill: Skill, limit: Int = 5) async -> [OutputRecord] {
        guard let genre = SkillLauncher.genre(for: skill) else { return [] }
        let genreDir = SkillLauncher.workRoot
            .appendingPathComponent("projects")
            .appendingPathComponent(genre)
        let key = genreDir.path
        let stamp = snapshot(of: genreDir)
        if let cached = cache[key], cached.stamp == stamp {
            return cached.records
        }
        let records = await Task.detached(priority: .userInitiated) {
            scan(genrePath: key, limit: limit)
        }.value
        cache[key] = (stamp, records)
        return records
    }

    private static func snapshot(of directory: URL) -> (Date, [String]) {
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        let mtime = (try? fileManager.attributesOfItem(atPath: directory.path))?[.modificationDate] as? Date
            ?? .distantPast
        return (mtime, names)
    }

    /// 真正扫盘（后台线程）：顶层目录逐个列内容，N+1 次 syscall 不占主线程
    private nonisolated static func scan(genrePath: String, limit: Int) -> [OutputRecord] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: genrePath) else { return [] }

        var records: [OutputRecord] = []
        for name in names where !name.hasPrefix(".") {
            // 目录名约定：YYYYMMDD_主题
            guard name.count >= 9, name.prefix(8).allSatisfy(\.isNumber),
                  name.dropFirst(8).first == "_" else { continue }
            let directory = URL(fileURLWithPath: genrePath).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let contents = (try? fileManager.contentsOfDirectory(atPath: directory.path))?
                .filter { !$0.hasPrefix(".") } ?? []
            let deliverableExtensions = ["docx", "pdf", "pptx", "html", "md", "png"]
            let deliverable = deliverableExtensions.lazy
                .compactMap { ext in contents.first { $0.lowercased().hasSuffix("." + ext) } }
                .first

            records.append(OutputRecord(
                directory: directory,
                dateText: String(name.prefix(8)),
                topic: String(name.dropFirst(9)),
                fileCount: contents.count,
                latestDeliverable: deliverable
            ))
        }
        return Array(
            records.sorted { $0.directory.lastPathComponent > $1.directory.lastPathComponent }
                .prefix(limit)
        )
    }

    static func open(_ record: OutputRecord) {
        NSWorkspace.shared.open(record.directory)
    }
}

// MARK: - 生产链路（二期 F6，静态图）
//
// 每一跳都有人工审校，所以只做「看得见下一跳」，不做自动编排。

enum ProductionChain {
    /// 下游：这个技能的产出通常喂给谁
    static let downstream: [String: [String]] = [
        "hotspot": ["to-voiceover", "to-xhs"],
        "to-voiceover": ["to-xhs"],
        "topic-daily": ["hotspot"],
        "fund-hotspot-page-writer": [],
    ]

    /// 硬依赖：谁停用会静默弄坏它
    static let dependencies: [String: [String]] = [
        "to-xhs": ["guizang-social-card-skill"],
    ]

    static func upstream(of directory: String) -> [String] {
        downstream.compactMap { key, values in values.contains(directory) ? key : nil }.sorted()
    }

    static func downstream(of directory: String) -> [String] {
        downstream[directory] ?? []
    }

    static func dependencies(of directory: String) -> [String] {
        dependencies[directory] ?? []
    }

    static func dependents(of directory: String) -> [String] {
        dependencies.compactMap { key, values in values.contains(directory) ? key : nil }.sorted()
    }

    static func hasChain(_ directory: String) -> Bool {
        !(upstream(of: directory).isEmpty && downstream(of: directory).isEmpty
            && dependencies(of: directory).isEmpty && dependents(of: directory).isEmpty)
    }
}
