import Foundation

/// 额外同步目标：内置预设（skills-hub 那批）或用户自加的目录。
/// 不进行内点阵，避免把 11 个品牌标冲掉；在设置和详情里开关。
package struct CustomTool: Codable, Identifiable, Hashable {
    package var id: String
    package var label: String
    package var skillsDir: String
    package var enabled: Bool

    package var root: URL {
        URL(fileURLWithPath: (skillsDir as NSString).expandingTildeInPath, isDirectory: true)
    }
}

package struct CustomToolsFile: Codable {
    package var tools: [CustomTool] = []
}

package enum ToolPresets {
    package struct Preset: Identifiable {
        package var id: String
        package var label: String
        package var skillsDir: String
        package var detectDir: String
    }

    /// skills-hub 内置表里、本库尚未一等对待的常用项。检测到本机有目录才推荐。
    package static let all: [Preset] = [
        .init(id: "trae", label: "Trae", skillsDir: "~/.trae/skills", detectDir: "~/.trae"),
        .init(id: "trae_cn", label: "Trae CN", skillsDir: "~/.trae-cn/skills", detectDir: "~/.trae-cn"),
        .init(id: "deepseek", label: "DeepSeek", skillsDir: "~/.dsh/skills", detectDir: "~/.dsh"),
        .init(id: "kimi", label: "Kimi", skillsDir: "~/.config/agents/skills", detectDir: "~/.config/agents"),
        .init(id: "qwen_code", label: "Qwen Code", skillsDir: "~/.qwen/skills", detectDir: "~/.qwen"),
        .init(id: "windsurf", label: "Windsurf", skillsDir: "~/.codeium/windsurf/skills", detectDir: "~/.codeium/windsurf"),
        .init(id: "copilot", label: "GitHub Copilot", skillsDir: "~/.copilot/skills", detectDir: "~/.copilot"),
        .init(id: "cline", label: "Cline", skillsDir: "~/.agents/skills", detectDir: "~/.agents"),
        .init(id: "continue", label: "Continue", skillsDir: "~/.continue/skills", detectDir: "~/.continue"),
        .init(id: "goose", label: "Goose", skillsDir: "~/.config/goose/skills", detectDir: "~/.config/goose"),
        .init(id: "antigravity", label: "Antigravity", skillsDir: "~/.gemini/config/skills", detectDir: "~/.gemini/config"),
        .init(id: "droid", label: "Droid", skillsDir: "~/.factory/skills", detectDir: "~/.factory"),
    ]

    package static func detected() -> [Preset] {
        let existing = Set(CustomTools.load().tools.map(\.id))
        return all.filter { preset in
            guard !existing.contains(preset.id) else { return false }
            let path = (preset.detectDir as NSString).expandingTildeInPath
            return FileManager.default.fileExists(atPath: path)
        }
    }
}

package enum CustomTools {
    package static var url: URL { AtlasPaths.root.appendingPathComponent("custom-tools.json") }

    package static func load() -> CustomToolsFile {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CustomToolsFile.self, from: data) else {
            return CustomToolsFile()
        }
        return file
    }

    package static func save(_ file: CustomToolsFile) throws {
        try FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    package static func active() -> [CustomTool] {
        load().tools.filter(\.enabled)
    }

    package static func add(id: String, label: String, skillsDir: String) throws {
        var file = load()
        guard !file.tools.contains(where: { $0.id == id }) else {
            throw AtlasError(LF("已有同名软件「%@」", id))
        }
        file.tools.append(CustomTool(id: id, label: label, skillsDir: skillsDir, enabled: true))
        try save(file)
    }

    package static func addPreset(_ preset: ToolPresets.Preset) throws {
        try add(id: preset.id, label: preset.label, skillsDir: preset.skillsDir)
    }

    package static func setEnabled(id: String, enabled: Bool) throws {
        var file = load()
        guard let index = file.tools.firstIndex(where: { $0.id == id }) else { return }
        file.tools[index].enabled = enabled
        try save(file)
    }

    package static func remove(id: String) throws {
        var file = load()
        file.tools.removeAll { $0.id == id }
        try save(file)
    }
}
