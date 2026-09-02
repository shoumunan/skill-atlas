import Foundation

/// 最近一次技能更新跑完的账：检查 / 更新 / 失败原因（skills-hub Updates 页）。
package struct UpdateFailure: Codable, Identifiable, Equatable {
    package var name: String
    package var reason: String
    package var id: String { name + reason }

    package init(name: String, reason: String) {
        self.name = name
        self.reason = reason
    }
}

package struct UpdateRun: Codable, Equatable {
    package var at: Int
    package var checked: Int
    package var updated: Int
    package var skipped: Int
    package var failures: [UpdateFailure]

    package init(at: Int, checked: Int, updated: Int, skipped: Int, failures: [UpdateFailure]) {
        self.at = at
        self.checked = checked
        self.updated = updated
        self.skipped = skipped
        self.failures = failures
    }
}

package enum UpdateRunLog {
    package static var url: URL { AtlasPaths.root.appendingPathComponent("update-run.json") }

    package static func load() -> UpdateRun? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UpdateRun.self, from: data)
    }

    package static func save(_ run: UpdateRun) {
        try? FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(run).write(to: url, options: .atomic)
    }
}
