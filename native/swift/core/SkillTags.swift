import Foundation

/// 标签只用于查找和整理，不改变同步目录（skills-hub FAQ 同款）。
package struct SkillTag: Codable, Identifiable, Hashable {
    package var id: String
    package var name: String
}

package struct SkillTagsFile: Codable {
    package var tags: [SkillTag] = []
    /// 技能目录名 → 标签 id
    package var links: [String: [String]] = [:]
}

package enum SkillTags {
    package static var url: URL { AtlasPaths.root.appendingPathComponent("skill-tags.json") }

    package static func load() -> SkillTagsFile {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SkillTagsFile.self, from: data) else {
            return SkillTagsFile()
        }
        return file
    }

    package static func save(_ file: SkillTagsFile) throws {
        try FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    package static func tags(for directory: String) -> [SkillTag] {
        let file = load()
        let ids = Set(file.links[directory] ?? [])
        return file.tags.filter { ids.contains($0.id) }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    package static func names(for directory: String) -> [String] {
        tags(for: directory).map(\.name)
    }

    @discardableResult
    package static func ensure(_ name: String) throws -> SkillTag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AtlasError(L("标签名不能空")) }
        var file = load()
        if let existing = file.tags.first(where: { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            return existing
        }
        let tag = SkillTag(id: UUID().uuidString, name: trimmed)
        file.tags.append(tag)
        try save(file)
        return tag
    }

    package static func rename(id: String, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AtlasError(L("标签名不能空")) }
        var file = load()
        guard let index = file.tags.firstIndex(where: { $0.id == id }) else { return }
        file.tags[index].name = trimmed
        try save(file)
    }

    package static func delete(id: String) throws {
        var file = load()
        file.tags.removeAll { $0.id == id }
        for key in file.links.keys {
            file.links[key]?.removeAll { $0 == id }
            if file.links[key]?.isEmpty == true { file.links[key] = nil }
        }
        try save(file)
    }

    package static func set(directory: String, tagIDs: [String]) throws {
        var file = load()
        let known = Set(file.tags.map(\.id))
        let cleaned = tagIDs.filter { known.contains($0) }
        if cleaned.isEmpty {
            file.links[directory] = nil
        } else {
            file.links[directory] = Array(Set(cleaned)).sorted()
        }
        try save(file)
    }

    package static func add(directory: String, tagID: String) throws {
        var ids = Set(load().links[directory] ?? [])
        ids.insert(tagID)
        try set(directory: directory, tagIDs: Array(ids))
    }

    package static func withCounts() -> [(tag: SkillTag, count: Int)] {
        let file = load()
        return file.tags.map { tag in
            (tag, file.links.values.filter { $0.contains(tag.id) }.count)
        }
        .sorted { $0.tag.name.localizedCompare($1.tag.name) == .orderedAscending }
    }

    package static func untaggedCount(directories: [String]) -> Int {
        let linked = Set(load().links.filter { !$0.value.isEmpty }.map(\.key))
        return directories.filter { !linked.contains($0) }.count
    }
}
