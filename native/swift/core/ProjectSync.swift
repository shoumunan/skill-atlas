import Foundation

/// 项目级同步：技能仍只在本库一份，软链写到项目目录（skills-hub 的 project scope）。
package struct SyncProject: Codable, Identifiable, Hashable {
    package var id: String
    package var path: String

    package var url: URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    package var displayName: String { url.lastPathComponent }
}

package struct ProjectSyncFile: Codable {
    package var projects: [SyncProject] = []
    /// 技能目录名 → 项目 id
    package var targets: [String: [String]] = [:]
}

package enum ProjectSync {
    package static var url: URL { AtlasPaths.root.appendingPathComponent("project-sync.json") }

    package static func load() -> ProjectSyncFile {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ProjectSyncFile.self, from: data) else {
            return ProjectSyncFile()
        }
        return file
    }

    package static func save(_ file: ProjectSyncFile) throws {
        try FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    package static func projects(for directory: String) -> [SyncProject] {
        let file = load()
        let ids = Set(file.targets[directory] ?? [])
        return file.projects.filter { ids.contains($0.id) }
    }

    package static func addProject(path: String) throws -> SyncProject {
        let expanded = (path as NSString).expandingTildeInPath
        var file = load()
        if let existing = file.projects.first(where: { $0.path == expanded || $0.path == path }) {
            return existing
        }
        let project = SyncProject(id: UUID().uuidString, path: expanded)
        file.projects.append(project)
        try save(file)
        return project
    }

    package static func removeProject(id: String) throws {
        var file = load()
        file.projects.removeAll { $0.id == id }
        for key in file.targets.keys {
            file.targets[key]?.removeAll { $0 == id }
            if file.targets[key]?.isEmpty == true { file.targets[key] = nil }
        }
        try save(file)
    }

    package static func set(directory: String, projectIDs: [String]) throws {
        var file = load()
        let known = Set(file.projects.map(\.id))
        let cleaned = projectIDs.filter { known.contains($0) }
        if cleaned.isEmpty {
            file.targets[directory] = nil
        } else {
            file.targets[directory] = Array(Set(cleaned)).sorted()
        }
        try save(file)
    }

    package static func isProjectScoped(_ directory: String) -> Bool {
        !(load().targets[directory] ?? []).isEmpty
    }
}
