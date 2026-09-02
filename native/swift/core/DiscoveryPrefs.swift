import Foundation

/// 哪些已安装工具目录参与「可收编」扫描。与界面上点亮哪些软件相互独立（skills-hub 同款）。
package struct DiscoveryPrefsFile: Codable {
    /// 关掉的来源：平台 rawValue 或自定义工具 id
    package var disabledSources: [String] = []
}

package enum DiscoveryPrefs {
    package static var url: URL { AtlasPaths.root.appendingPathComponent("discovery-scan.json") }

    package static func load() -> DiscoveryPrefsFile {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(DiscoveryPrefsFile.self, from: data) else {
            return DiscoveryPrefsFile()
        }
        return file
    }

    package static func save(_ file: DiscoveryPrefsFile) throws {
        try FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    package static func isEnabled(_ key: String) -> Bool {
        !Set(load().disabledSources).contains(key)
    }

    package static func set(_ key: String, enabled: Bool) throws {
        var file = load()
        var set = Set(file.disabledSources)
        if enabled { set.remove(key) } else { set.insert(key) }
        file.disabledSources = set.sorted()
        try save(file)
    }
}
