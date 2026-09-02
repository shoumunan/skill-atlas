import Foundation

/// 技能目录文件树（详情里浏览 Markdown / 代码，不跟 .git）。
package struct SkillFileNode: Identifiable, Hashable {
    package var relativePath: String
    package var isDirectory: Bool
    package var id: String { relativePath }

    package var name: String {
        (relativePath as NSString).lastPathComponent
    }

    package var isMarkdown: Bool {
        relativePath.lowercased().hasSuffix(".md")
    }

    package var isText: Bool {
        let ext = (relativePath as NSString).pathExtension.lowercased()
        return ["md", "txt", "json", "yml", "yaml", "toml", "sh", "py", "js", "ts", "swift", "rs", "go", "rb", "xml", "html", "css", "svg"].contains(ext)
    }
}

package enum SkillFiles {
    package static func list(root: URL) -> [SkillFileNode] {
        let fileManager = FileManager.default
        guard let walker = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var nodes: [SkillFileNode] = []
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in walker {
            if url.lastPathComponent == ".git" {
                walker.skipDescendants()
                continue
            }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else { continue }
            let relative = String(path.dropFirst(rootPath.count + 1))
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: path, isDirectory: &isDir)
            nodes.append(SkillFileNode(relativePath: relative, isDirectory: isDir.boolValue))
        }
        return nodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.relativePath.localizedCompare($1.relativePath) == .orderedAscending
        }
    }

    package static func read(root: URL, relative: String, limit: Int = 200_000) -> String? {
        let url = root.appendingPathComponent(relative)
        guard let data = try? Data(contentsOf: url), data.count <= limit,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}
