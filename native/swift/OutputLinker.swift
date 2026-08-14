import AppKit
import Foundation

// MARK: - 产出物回链（二期 F4）
//
// Filing 规则「一任务一目录」（projects/<体裁>/<YYYYMMDD_主题>/）让回链几乎零成本：
// 体裁 ← SkillLauncher.genreMap 反查，目录名自带日期与主题。
// 只读扫描、详情页展示最近 5 次、点击 open、一键重跑上次主题。

struct OutputRecord: Identifiable {
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
    /// 技能的最近产出（按目录名日期降序，最多 limit 条）
    static func recentOutputs(for skill: Skill, limit: Int = 5) -> [OutputRecord] {
        guard let genre = SkillLauncher.genre(for: skill) else { return [] }
        let genreDir = SkillLauncher.workRoot
            .appendingPathComponent("projects")
            .appendingPathComponent(genre)
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: genreDir.path) else { return [] }

        var records: [OutputRecord] = []
        for name in names where !name.hasPrefix(".") {
            // 目录名约定：YYYYMMDD_主题
            guard name.count >= 9, name.prefix(8).allSatisfy(\.isNumber),
                  name.dropFirst(8).first == "_" else { continue }
            let directory = genreDir.appendingPathComponent(name)
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
